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

for my $modfilename (glob "$applydir/*.honmod") {
    apply_mod($modfilename);
}

sub apply_mod
{
    my ($modfilename) = @_;
    my $mod = HoN::Honmod->new(filename => $modfilename);
    my $modxml = $mod->read;

    my @resfiles = sort {
        ($a =~ /(\d+)/)[0] <=> ($b =~ /(\d+)/)[0]
    } grep !/$resfilename$/o, glob "$gamedir/resources*.s2z";
    my @res = map { HoN::S2Z->new(filename => $_) } @resfiles;
    my $prires = $res[0];
    my $modres = HoN::S2Z::Honmod->new(filename => $resfilepath);
    $modres->read;
    $modres->parse;

    while (my ($filename, $edits) = each %{ $modxml->{editfile} }) {
        say "$filename has edits";
        # search backward to find the last resources file that includes the file
        # we need to change
        SEARCH_RES:
        for my $res ($modres, reverse @res) {
            $res->read;
            if (my $file = $res->file($filename)) {
                say "res $res->{filename} has $filename";

                # TODO apply mods

                last SEARCH_RES;
            }
        }
    }
}

#XXX $modxml;
#XXX $res->mods;

