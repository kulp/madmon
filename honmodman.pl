#!/usr/bin/perl

use strict;
use 5.10.0;
use feature qw(say);

use XXX;

use Algorithm::Dependency::Ordered;
use Algorithm::Dependency::Source::HoA;
use HoN::Honmod;
use HoN::S2Z;
use List::Util qw(first);
use Text::Trim qw(trim);
use Text::Balanced qw(extract_bracketed extract_quotelike);

our $gamedir = "."; # XXX
our $resfilename = "resources999.s2z";
our $resfilepath = "$gamedir/$resfilename";

my %orignames;
my %normnames;

climain(@ARGV) unless caller;

################################################################################

sub climain
{
	my ($applydir) = @_;
	my $repores = create_repo($resfilepath);

	my @mods = glob "$applydir/*.honmod";

	my @modres = map { HoN::Honmod->new(filename => $_) } @mods;
	$_->read for @modres;

	my $ordered = calc_deps(\@modres);

	for my $modres (@$ordered) {
		say "Applying mod " . $modres->{filename} . " ...";
		apply_mod($repores, $modres);
	}

	$repores->save
		or die "Failed to write repo";
}

sub create_repo
{
	my ($resfilepath) = @_;

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
			map { $_->{name} = fix_mod_name($_->{name}); $_ }
			grep { %$_ }
			map { $_->pointer } @_
		}

		my @reqs    = cleanup @{ $xml->{requirement} };
		my @afters  = cleanup @{ $xml->{applyafter} };
		my @befores = cleanup @{ $xml->{applybefore} };
		# TODO support applybefore

		my $origname = $xml->{name}->pointer;
		warn "<applybefore/> not yet supported, skipping '$origname'" and next if @befores;

		my $name = fix_mod_name($origname);
		$orignames{$name} = $origname;
		$normnames{$origname} = $name;
		$deps{ $name } = {
			# TODO version
			name    => $name,
			reqs    => \@reqs,
			afters  => \@afters,
			befores => \@befores,
			mod     => $m,
		};
	}

	my %deptree = map {
		$_->{name} => [ map { $_->{name} } @{ $_->{reqs} }, @{ $_->{afters} } ]
	} sort { +@{ $a->{reqs} } - +@{ $b->{reqs} } } values %deps;

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

sub do_copies
{
    my ($repores, $modres) = @_;
    my $modxml = $modres->xml;

    for my $copy (grep { %$_ } @{ $modxml->{copyfile} }) {
        my $filename = $copy->{name};
        my $source = $copy->{source} || $filename;
        say "Copying $filename into repo ...";
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
            unless $repores->have($req->{name});
    }

    for my $bad (grep { %$_ } @{ $modxml->{incompatibility} }) {
        die "Present incompatibility $bad->{name}"
            if $repores->have($bad->{name});
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

sub nodos
{
    my @r = map { (my $x = $_) =~ s/\r//g; $x } @_;
    return wantarray ? @r : $r[0];
}

sub compile_condition
{
	my ($repores, $modres, $condition) = @_;
	my ($middle, $after, $before) = extract_delimited($condition, "()");

    die $condition;
}

sub do_edit
{
    my ($repores, $modres, $str, $edit) = @_;

    my $pos = 0;
    my $len = 0;

    # XXX use condition
    my $condition = sub {
        my ($what) = @_;
        my $sub = compile_condition($repores, $modres, $what);
        die "Conditions not implemented; unsafe to continue";
    };

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
        /condition/               and $condition->($what);
        /insert|add/              and $insert->($what);
        /delete/                  and $delete->($what);
        /replace/                 and $replace->($what);
    }
}

