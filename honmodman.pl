#!/usr/bin/env perl

use strict;
#use 5.10.0;
use feature qw(say);

use XXX;

use HoN::Honmod;
use HoN::Madmon qw(:all);

our $gamedir = "."; # XXX

climain(@ARGV) unless caller;

################################################################################

sub climain
{
    my ($applydir) = @_;
    my $repores = create_repo($gamedir);

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

