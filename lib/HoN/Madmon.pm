package HoN::Madmon;

#use 5.10.0;
use base qw(Exporter);

use strict;

our @EXPORT_OK = qw(
    create_repo
    calc_deps
    apply_mod
    check_mod_updates
);

our %EXPORT_TAGS = (
    all => \@EXPORT_OK
);

use feature qw(say);

use XXX;

use Algorithm::Dependency::Ordered;
use Algorithm::Dependency::Source::HoA;
use HoN::Honmod;
use HoN::S2Z;
use List::Util qw(first);
use LWP::UserAgent;
use Text::Trim qw(trim);
use Text::Balanced qw(extract_multiple
                      extract_bracketed
                      extract_quotelike);

use version 0.77;

our $VERSION = "0.0.1";

our $user_agent_string = __PACKAGE__ . "/$VERSION";

# TODO OOPify

our $gamedir;
our $resfilename = "resources999.s2z";

my %orignames;
my %normnames;

sub create_repo
{
    ($gamedir) = @_;
    my $resfilepath = "$gamedir/$resfilename";

    unlink $resfilepath;
    my $repores = HoN::S2Z::Honmod->new(create => 1, filename => $resfilepath);
    $repores->read;
    $repores->parse;

    return $repores;
}

sub calc_deps
{
    my ($modres) = @_;
    my %deps;
    for my $m (@$modres) {
        my $xml = $m->xml;

        sub cleanup {
            map { $_->{nname} = fix_mod_name($_->{name}); $_ }
            grep { %$_ }
            map { $_->pointer } @_
        }

        my @reqs    = cleanup @{ $xml->{requirement} };
        my @afters  = cleanup @{ $xml->{applyafter} };
        my @befores = cleanup @{ $xml->{applybefore} };
        # TODO support applybefore

        my $name = $xml->{name}->pointer;
        warn "<applybefore/> not yet supported, skipping '$name'" and next if @befores;

        my $nname = fix_mod_name($name);
        $orignames{ $_->{nname} } = $_->{name } for @reqs, @afters, @befores;
        $normnames{ $_->{name } } = $_->{nname} for @reqs, @afters, @befores;
        $orignames{$nname} = $name;
        $normnames{$name } = $nname;
        $deps{ $nname } = {
            # TODO version
            name    => $name,
            nname   => $nname,  # normalized name
            reqs    => \@reqs,
            afters  => \@afters,
            befores => \@befores,
            mod     => $m,
        };
    }

    my %deptree = map {
        $_->{nname} => [ map { $_->{nname} } @{ $_->{reqs} }, @{ $_->{afters} } ]
    } sort { +@{ $a->{reqs} } - +@{ $b->{reqs} } } values %deps;

    WWW \%deptree;

    my $depsrc = Algorithm::Dependency::Source::HoA->new(\%deptree);
    my $depmkr = Algorithm::Dependency::Ordered->new(source => $depsrc, ignore_orphans => 1)
        or die "Failed to create dependency tree resolver";

    my $sched = $depmkr->schedule_all
        or die "Failed to find a schedule to enable all mods";
    print "Going to apply mods:\n", map { "\t$orignames{$_}\n" } @$sched;
    my @ordered = map { $deps{$_}->{mod} } @$sched;
    return \@ordered;
}

# this is from the original HoN Modification Manager
# this normalizes mod names and hides at least one known mistake in reqspec
# (Bang! Replay Renamer 0.52)
sub fix_mod_name
{
    (my $x = lc $_[0]) =~ y/a-z0-9//dc;
    return $x;
}

sub check_condition
{
    my ($repores, $modres, $what) = @_;
    my $sub = compile_condition($repores, $modres, $what);
    my $ok = $sub->();
    warn "Condition [ $what ] not met" unless $ok;

    return $ok;
}

sub do_copies
{
    my ($repores, $modres) = @_;
    my $modxml = $modres->xml;

    COPY:
    for my $copy (grep { %$_ } @{ $modxml->{copyfile} }) {
        my $filename = $copy->{name};
        my $source = $copy->{source} || $filename;
        say "Copying $filename into repo ...";
        if (my $what = $copy->{condition}) {
            if (not check_condition($repores, $modres, $what)) {
                warn "Conditions not met; skipping copy";
                next COPY;
            }
        }
        my $member = $modres->{zip}->memberNamed($source)
            or die "Member named $source missing !";
        # TODO don't use stringification, it's probably inefficient
        my $newmember = Archive::Zip::Member->newFromString(scalar $member->contents, $filename);
        $repores->{zip}->removeMember($filename);
        $repores->{zip}->addMember($newmember);
    }
}

sub do_edits
{
    my ($repores, $modres, $res) = @_;
    my $modxml = $modres->xml;

    EDIT:
    for my $edits (@{ $modxml->{editfile} }) {
        my $filename = "$edits->{name}"; # force stringification of XML::Smart object
        say "Editing $filename ...";

        if (my $what = $edits->{condition}) {
            if (not check_condition($repores, $modres, $what)) {
                warn "Conditions not met; skipping edit";
                next EDIT;
            }
        }
        # search backward to find the last resources file that includes the file
        # we need to change
        for my $res ($repores, reverse @$res) {
            if (my $file = $res->file($filename)) {
                say "... found $filename in $res->{filename} ...";

                my $str = $file->contents;

                do_edit($repores, $modres, \$str, $edits);

                my $member = Archive::Zip::Member->newFromString($str, $filename);

                # TODO encapsulation
                my $zip = $repores->{zip};
                $zip->removeMember($filename);
                $zip->addMember($member)
                    or die "Failed to add member";

                next EDIT;
            }
        }
    }
}

sub apply_mod
{
    my ($repores, $modres) = @_;
    my $modxml = $modres->xml;

    my $modname    = $modxml->{name};
    my $modversion = $modxml->{mmversion};

    my @resfiles = sort {
        ($a =~ /(\d+)/)[0] <=> ($b =~ /(\d+)/)[0]
    } grep !/$resfilename$/o, glob "$gamedir/resources*.s2z";
    my @res = map { HoN::S2Z->new(filename => $_) } @resfiles;
    die "Base resources file (resources0.s2z) not found"
        unless $res[0]->{filename} ne "resources0.s2z";

    for my $req (grep { %$_ } @{ $modxml->{requirement} }) {
        die "Missing requirement $req->{name}"
            unless $repores->have($req->{nname});
    }

    for my $bad (grep { %$_ } @{ $modxml->{incompatibility} }) {
        die "Present incompatibility $bad->{name}"
            if $repores->have($bad->{nname});
    }

    eval {
        do_copies($repores, $modres);
        $_->read for @res; # TODO read only on demand
        do_edits($repores, $modres, \@res);
    };
    if ($@) {
        warn "Caught error while applying mod: $@";
        die "Application of mod $modname $modversion failed; state is undefined";
    }

    $repores->installed($normnames{$modname}, $modversion);
}

# Takes a modres and two subs.
# Calls one of the subs (first if newer version avail, second otherwise) with
# parameters: (modres, oldversion, newversion)
sub check_mod_updates
{
    my ($modres, $update_action, $no_update_action) = @_;
    my $modxml = $modres->xml;

    my $modname    = $modxml->{name};
    my $modversion = $modxml->{mmversion};
    my $checkurl   = $modxml->{updatecheckurl};

    my $ua = LWP::UserAgent->new(agent => $user_agent_string);
    my $rsp = $ua->get("$checkurl");
    my $newv = $rsp->decoded_content;

    # If the versions don't parse but are not equal, assume we need to update;
    # some incorrectly-formatted modules (old MiniUI 1.3, for example), have
    # non-numeric versions (MiniUI "1.3.*")

    my $newer = eval { (version->parse($newv) > version->parse($modversion)) };
    my $sub = ($newer or ($@ and $newv ne $modversion))
                ? $update_action
                : $no_update_action;

    $sub->($modres, $modversion, $newv) if $sub;
}

sub nodos
{
    my @r = map { (my $x = $_) =~ s/\r//g; $x } @_;
    return wantarray ? @r : $r[0];
}

# Note that conditions, according to the de facto standard implementation, are
# parsed left-to-right in the absence of parentheses; that is, "and" and "or"
# operators have the same precedence
sub compile_condition
{
    my ($repores, $modres, $condition) = @_;

    my @textterms = grep length, map trim,
                        extract_multiple($condition,
                                        [ \&extract_bracketed,
                                          \&extract_quotelike,
                                          'not',
                                          qr/\b(and|or)\b/,
                                        ]);

    my @terms = map {
        /^\((.*)\)$/ ? compile_condition($repores, $modres, $1) :
        /^'(.*)'$/   ? do { my $name = $1; sub { $repores->have(fix_mod_name($name)) } } :
        #/^'(.*)'$/   ? do { my $name = $1; sub { warn $name; $test{$name} } } :
        $_ # default: pass through
    } @textterms;

    # make two passes through the terms, first doing unary operators (not) and
    # then binary operators (and, or)
    for (my $i = 0; $i < @terms; $i++) {
        # copy on lexical pad necessary for correct scoping
        my $next = $terms[$i + 1];

        $terms[$i] =~ /^not$/ and splice(@terms, $i, 2, sub { not $next->() });
    }

    my $final = $terms[0];
    die "Invalid condition:\n\t$condition" unless ref($final) eq "CODE";
    for (my $i = 0; $i < @terms; $i++) {
            my $prev = $final;
        my $j = $i + 1;
        local $_ = $terms[$i]; # convenience alias

        /^and$/ and (++$i, $final = sub { $prev->() && $terms[$j]->() });
        /^or$/  and (++$i, $final = sub { $prev->() || $terms[$j]->() });
    }

    return $final;
}

sub do_edit
{
    my ($repores, $modres, $str, $edit) = @_;

    my $pos = 0;
    my $len = 0;

    my $find = sub {
        my ($what, $up) = @_;
        if (local $_ = $what->{position}) {
            $len = 0;

            /start|begin|head|before/ and $pos = 0;
            /end|tail|after|eof/      and $pos = length $$str;
            /(-?\d+)/                 and $pos += $1;
        } elsif (my $content = nodos trim $what->{CONTENT}) {
            if ($up) {
                $pos = index substr($$str, 0, $pos), $content;
            } else {
                $pos = index $$str, $content, $pos; # XXX +1
            }
            $len = length $content;
        }
        say "... seeking to $pos ...";
    };

    my $insert = sub {
        my ($what) = @_;
        my $content = nodos $what->{CONTENT};
        say "... inserting $len characters ...";
        warn "Bad position $pos" and return if $pos < 0;
        for ($what->{position}) {
            /before/ and substr($$str, $pos       , 0) = $content;
            /after/  and substr($$str, $pos + $len, 0) = $content;
        }
    };

    my $delete = sub {
        my ($what) = @_;
        say "... deleting $len characters ...";
        warn "Bad position $pos" and return if $pos < 0;
        substr($$str, $pos, $len) = "";
    };

    my $replace = sub {
        my ($what) = @_;
        my $content = nodos $what->{CONTENT};
        my $len2 = length $content;
        say "... replacing $len characters with $len2 characters ...";
        warn "Bad position $pos" and return if $pos < 0;
        substr($$str, $pos, $len) = $content;
    };

    my %ctr;
    for (@{ $edit->pointer->{"/order"} }) {
        my $what = ${ $edit->{$_} }[ $ctr{$_}++ ]->pointer;
        /(find|search|seek)(up)?/ and $find->($what, defined $2);
        /insert|add/              and $insert->($what);
        /delete/                  and $delete->($what);
        /replace/                 and $replace->($what);
    }
}

1;

