#!/usr/bin/perl

use strict;
#use 5.10.0;
use feature qw(say);

use XXX;
use HoN::Honmod;
use HoN::S2Z;

my $gamedir = "."; # XXX
my $resfilename = "resources999.s2z";
my $resfilepath = "$gamedir/resources999.s2z";
my ($applydir) = @ARGV;
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

    my @resfiles = sort {
        ($a =~ /(\d+)/)[0] <=> ($b =~ /(\d+)/)[0]
    } grep !/$resfilename$/o, glob "$gamedir/resources*.s2z";
    my @res = map { HoN::S2Z->new(filename => $_) } @resfiles;
    my $prires = $res[0];

    for my $req (keys %{ $modxml->{requirement} }) {
        if (not $repores->have($req)) {
            # TODO upgrade to die()
            warn "Missing requirement $req";
        }
    }

    while (my ($filename, $copy) = each %{ $modxml->{copyfile} }) {
        say "Copying $filename into repo ...";
        my $member = $modres->{zip}->memberNamed($copy->{source});
        # TODO don't use stringification, it's probably inefficient
        my $newmember = Archive::Zip::Member->newFromString(scalar $member->contents, $filename);
        $repores->{zip}->removeMember($filename);
        $repores->{zip}->addMember($newmember);
    }

    while (my ($filename, $edits) = each %{ $modxml->{editfile} }) {
        say "$filename has edits";
        # search backward to find the last resources file that includes the file
        # we need to change
        SEARCH_RES:
        for my $res (reverse @res) {
            $res->read;
            if (my $file = $res->file($filename)) {
                say "res $res->{filename} has $filename";

                # TODO encapsulation
                my $zip = $repores->{zip};
                my $str = $file->contents;

                do_edit($str, $edits);

                # TODO apply mods to $str
                my $member = Archive::Zip::Member->newFromString($str, $filename);
                $zip->removeMember($filename);
                $zip->addMember($member);

                last SEARCH_RES;
            }
        }
    }

    my $modname = $modxml->{name};
    my $modversion = $modxml->{mmversion};

    $repores->installed($modname, $modversion);
}

sub do_edit
{
    my ($str, $edits) = @_;
    warn "not editing ".\$str." with $edits";
}

$repores->save
    or die "Failed to write repo";

#XXX $modxml;
#XXX $res->mods;

