package HoN::Honmod;

use strict;
use 5.10.0;

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use XML::Smart;

use HoN::S2Z;

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

    my $xmlstr = $self->{xmlstr} = $zip->memberNamed("mod.xml");

    my $xml = XML::Smart->new(scalar $xmlstr->contents);

    $xml = $xml->cut_root;

    return $xml;
}

1;

