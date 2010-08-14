package HoN::S2Z;

use strict;
use 5.10.0;

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use XML::Smart;

sub new
{
    my $class = shift;
    my (%args) = @_;
    return bless \%args => $class;
}

sub read
{
    my ($self) = @_;

    my $zip = $self->{zip} = Archive::Zip->new;

    if (!-e $self->{filename} and $self->{create}) {
        $zip->overwriteAs($self->{filename});
    }

    $zip->read($self->{filename}) == AZ_OK
        or die "Failed to read ZIP: $!";
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
    return $self->{zip}->zipfileComment(@_);
}

sub save
{
    # TODO permit writing to another filename
    my $self = shift;
    $self->{zip}->overwrite == AZ_OK
        or die "Failed to write file";
}

package HoN::S2Z::Honmod;

# TODO use my own naming / versioning ?
my $default_comment = <<EOM;
HoN Mod Manager v1.3.6.0 Output

Game Version: 1.0.6.1

Applied Mods: 
EOM

use base qw(HoN::S2Z);

use XXX;
use List::MoreUtils qw(firstidx);

sub read
{
    my ($self) = @_;
    my $result = $self->SUPER::read;
    $self->{zip}->zipfileComment($default_comment);
    return $result;
}

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
    my @applieds = map {
        my ($name, $version) = /^(.*)\s+\(v(.*)\)$/;
        $name ? () :
        {
            name    => $name,
            version => $version,
        }
    } @lines[(1 + firstidx { /Applied Mods: / } @lines) .. $#lines];

    %$self = ( %$self,
        game_version => $gversion,
        mod_version  => $mversion,
        applied_mods => \@applieds,
    );
}

sub mods
{
    return shift->{applied_mods};
}

sub have
{
    my ($self, $name) = @_;
    return unless $name;
    my %mods = map { $_->{name} => $_ } @{ $self->{applied_mods} };
    return $mods{$name};
}

sub installed
{
    my ($self, $mod, $ver) = @_;
    if ($mod) {
        push @{ $self->{applied_mods} }, +{
            name    => $mod,
            version => $ver,
        };
    }

    # TODO wantarray
    return @{ $self->{applied_mods} };
}

sub save
{
    my $self = shift;

    my $built = join "",
        map "$_->{name} (v$_->{version})\n",
        @{ $self->{applied_mods} };

    $self->comment($default_comment . $built);
    return $self->SUPER::save(@_);
}

1;

