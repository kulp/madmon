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

my @mods = glob "$applydir/*.honmod";

# don't use foreach because we want to change @mods on the fly
while (my $modfilename = shift @mods) {
    # TODO retry logic
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

    for my $req (values %{ $modxml->{requirement}->pointer }) {
        die "Missing requirement $req"
            unless $repores->have($req);
    }

    for my $bad (values %{ $modxml->{incompatibility}->pointer }) {
        die "Present incompatibility $bad"
            if $repores->have($bad);
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
        my $filename = "$edits->{name}"; # force stringification of XML::Smart object
        say "Editing $filename ...";
        # search backward to find the last resources file that includes the file
        # we need to change
        SEARCH_RES:
        for my $res ($repores, reverse map { $_->read; $_ } @res) {
            if (my $file = $res->file($filename)) {
                say "... found $filename in $res->{filename} ...";

                my $str = $file->contents;

                do_edit(\$str, $edits);

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
    my ($str, $edit) = @_;

    # XXX use condition
    my $condition;
    my $len = 0;
    my $pos = -1;

    # XXX figure out why $len doesn't change when I think it should

    my $find = sub {
        my ($what) = @_;
        if (my $content = $what->{CONTENT}) {
            warn "content = $content";
            $pos = index $$str, $content, $pos; # XXX +1
            $len = length $content;
        } elsif (local $_ = $what->{position}) {
            $len = 0;

            /start|begin|head|before/ and $pos = 0;
            /end|tail|after|eof/      and $pos = length $$str;
            /(-?\d+)/                 and $pos += $1;
        }
        say "... seeking to $pos ...";
    };

    my $insert = sub {
        my ($what) = @_;
        my $content = $what->{CONTENT};
        say "... inserting $len characters ...";
        warn "Bad position $pos", return if $pos < 0;
        for ($what->{position}) {
            /before/ and substr($$str, $pos       , 0) = $content;
            /after/  and substr($$str, $pos + $len, 0) = $content;
        }
    };

    my $delete = sub {
        my ($what) = @_;
        say "... deleting $len characters ...";
        warn "Bad position $pos", return if $pos < 0;
        substr($$str, $pos, $len) = "";
    };

    my $replace = sub {
        my ($what) = @_;
        my $content = $what->{CONTENT};
        my $len2 = length $content;
        say "... replacing $len characters with $len2 characters ...";
        warn "Bad position $pos", return if $pos < 0;
        substr($$str, $pos, $len) = $content;
    };

    for (@{ $edit->pointer->{"/order"} }) {
        my $what = $edit->{$_}->pointer;
        /find|search|seek/ and $find->($what);
        /condition/        and $condition = $what;
        /insert|add/       and $insert->($what);
        /delete/           and $delete->($what);
        /replace/          and $replace->($what);
    }
}

$repores->save
    or die "Failed to write repo";

#XXX $modxml;
#XXX $res->mods;

