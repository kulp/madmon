#!/usr/bin/perl

use strict;
#use 5.10.0;
use feature qw(say);

use XXX;
use HoN::Honmod;
use HoN::S2Z;
use List::Util qw(first);

my $gamedir = "."; # XXX
my $resfilename = "resources999.s2z";
my $resfilepath = "$gamedir/$resfilename";
my ($applydir) = @ARGV;
unlink $resfilepath;
my $repores = HoN::S2Z::Honmod->new(create => 1, filename => $resfilepath);
$repores->read;
$repores->parse;

for my $modfilename (glob "$applydir/*.honmod") {
    apply_mod($modfilename);
}

sub apply_mod
{
    my ($modfilename) = @_;
    my $modres = HoN::Honmod->new(filename => $modfilename);
    my $modxml = $modres->read;

    my $modname    = $modxml->{name};
    my $modversion = $modxml->{mmversion};

    my @resfiles = sort {
        ($a =~ /(\d+)/)[0] <=> ($b =~ /(\d+)/)[0]
    } grep !/$resfilename$/o, glob "$gamedir/resources*.s2z";
    my @res = map { HoN::S2Z->new(filename => $_) } @resfiles;
    my $prires = $res[0];

    for my $req (@{ $modxml->{requirement} }) {
        if (not $repores->have($req->{name})) {
            # TODO upgrade to die()
            warn "Missing requirement $req->{name}";
        }
    }

    for my $bad (@{ $modxml->{incompatibility} }) {
        if ($repores->have($bad->{name})) {
            # TODO upgrade to die()
            warn "Present incompatibility $bad->{name}";
        }
    }

    for my $copy (@{ $modxml->{copyfile} }) {
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

    for my $edits (@{ $modxml->{editfile} }) {
        my $pos = 0; # position in file
        my $filename = "$edits->{name}"; # force stringification of XML::Smart object
        say "Editing $filename ...";
        # search backward to find the last resources file that includes the file
        # we need to change
        SEARCH_RES:
        for my $res ($repores, reverse map { $_->read; $_ } @res) {
            if (my $file = $res->file($filename)) {
                say "... found $filename in $res->{filename} ...";

                my $str = $file->contents;

                do_edit(\$str, $edits, \$pos);

                my $member = Archive::Zip::Member->newFromString($str, $filename);

                # TODO encapsulation
                my $zip = $repores->{zip};
                $zip->removeMember($filename);
                $zip->addMember($member)
                    or die "Failed to add member";

                last SEARCH_RES;
            }
        }
    }

    $repores->installed($modname, $modversion);
}

sub do_edit
{
    # TODO move $pos into this function
    my ($str, $edit, $pos) = @_;
    #warn "not editing ".\$str." with $edit";

    # XXX use condition
    my $condition;
    my $len = 0;

    my $find = sub {
        my ($what) = @_;
        say "... seeking ...";
        if (my $content = $what->{CONTENT}) {
            $$pos = index $$str, $content, $$pos;
            $len = length $content;
        } elsif (local $_ = $what->{position}) {
            $len = 0;

            /start|begin|head|before/ and $$pos = 0;
            /end|tail|after|eof/      and $$pos = length $$str;
            /(-?\d+)/                 and $$pos += $1;
        }
    };

    my $insert = sub {
        my ($what) = @_;
        my $content = $what->{CONTENT};
        say "... inserting ...";
        for ($what->{position}) {
            /before/ and substr($$str, $$pos       , 0) = $content;
            /after/  and substr($$str, $$pos + $len, 0) = $content;
        }
    };

    my $top = $edit->pointer;
    for (@{ $top->{"/order"} }) {
        my $what = $edit->{$_};
        /find|search|seek/ and $find->($what);
        /condition/        and $condition = $what;
        /insert|add/       and $insert->($what);
    }
}

$repores->save
    or die "Failed to write repo";

#XXX $modxml;
#XXX $res->mods;

