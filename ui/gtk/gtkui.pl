#!/usr/bin/env perl
use strict;

use Glib qw/TRUE FALSE/;
use Gtk2 '-init';
use Gtk2::SimpleList;

package HoNModManGtkGUI;
use base qw( Gtk2::GladeXML::Simple );

my $gladefile = "kui.glade";

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new( $gladefile );
    return $self;
}

sub add_module_btn_clicked
{
    my ( $self, $widget ) = @_;
    warn "TODO";

    print "add_module_btn_clicked called from ", $widget->get_name, "\n";
}

sub show_about_box
{
    my ($self, $widget) = @_;
    $self->get_widget('aboutdialog')->show;
}

sub gtk_main_quit { Gtk2->main_quit }
sub hide_about { $_[1]->hide; }

1;

package main;
HoNModManGtkGUI->new->run;

1;

