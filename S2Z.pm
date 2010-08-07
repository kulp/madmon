package HoN::S2Z;

use strict;
use 5.10.0;

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use XML::Simple;

sub new
{
    my $class = shift;
    return bless { @_ } => $class;
}

sub read
{
    my ($self) = @_;

    my $zip = $self->{zip} = Archive::Zip->new;

    $zip->read($self->{filename}) == AZ_OK or die "Failed to read ZIP: $!";
}

sub file
{
    my ($self, $filename) = @_;
    my $xmlstr = $self->{zip}->memberNamed($filename);
    return $xmlstr;
}

sub comment
{
    my $self = shift;
    eval { return $self->{zip}->zipfileComment; };
}

package HoN::S2Z::Honmod;

use base qw(HoN::S2Z);

use XXX;
use List::MoreUtils qw(firstidx);

sub parse
{
    my $self = shift;
    my @lines = split /\n/, $self->comment;
    chomp, s/\r$// for @lines;

    my $mversion = $lines[0] =~ /HoN Mod Manager v(\S+) Output/
        or die "No magic";
    $lines[1] eq ""
        or die "Bad format";
    my $gversion = $lines[2] =~ /Game Version: (\S+)/
        or die "No game version";
    my %applieds = map {
        my ($name, $version) = /^(.*)\s+\(v(.*)\)$/;
        $name => {
            name    => $name,
            version => $version,
        }
    } @lines[(firstidx { /Applied Mods: / } @lines) .. $#lines];

    %$self = ( %$self,
        game_version => $gversion,
        mod_version  => $mversion,
        applied_mods => \%applieds,
    );
}

sub mods
{
    return shift->{applied_mods};
}

1;

