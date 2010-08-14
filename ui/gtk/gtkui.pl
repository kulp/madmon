#!/usr/bin/env perl
use strict;

package HoNModManGtkGUI;
use base qw( Gtk2::GladeXML::Simple );

#use XXX;

use File::Temp qw(tempfile);
#use File::Basename qw(basename);
use Glib qw/TRUE FALSE/;
use Gtk2 '-init';
use Gtk2::SimpleList;
use String::Truncate qw(elide);

use lib "../../lib"; #XXX
use HoN::Honmod;

my $gladefile = "kui.glade";

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new( $gladefile );
    return $self;
}

sub add_mod_file_names
{
    my ($self, $files) = @_;

    my $tv = $self->get_widget('modtreeview');

    my $sl = Gtk2::SimpleList->new_from_treeview(
                    $tv, qw(
                    Enabled     bool
                    Icon        pixbuf
                    Name        text
                    Version     text
                    Description text
                    ));

    my @bads;
    for my $filename (@$files) {
        next unless -f $filename;
        eval { # just skip if we have an error
            my $mod = HoN::Honmod->new(filename => $filename);
            $mod->read;
            # TODO make elision width dependent on column width
            my $desc = elide($mod->description, 40, { at_space => 1 });
            my $iconstr = $mod->file("icon.png");
            my $pb;
            if ($iconstr) {
                my $tmp = File::Temp->new; # unlinks at DESTROY time
                my $iconfilename = $tmp->filename;
                print $tmp $iconstr->contents;
                close $tmp;
                $pb = Gtk2::Gdk::Pixbuf->new_from_file($iconfilename);
            }

            push @{ $sl->{data} }, [ 0, $pb, $mod->name, $mod->version, $desc ];
        };
        if ($@) {
            push @bads, $filename;
        }
    }

    if (@bads) {
        my $message = Gtk2::MessageDialog->new(
                $tv->get_toplevel, [], 'warning', 'ok',
                "Failed to load the following modules:\n" . join "\n", @bads);
        $message->run;
        $message->destroy;
    }
}

sub addmodbutton_clicked_cb
{
    my ($self, $widget) = @_;

    my $fc = Gtk2::FileChooserDialog->new(
            'Choose mod file(s)',
            $widget->get_toplevel,
            'open',
            'gtk-cancel' => 'cancel',
            'gtk-ok'     => 'ok'
        );

    $fc->set_select_multiple(TRUE);
    # TODO add shortcut to mods download folder ?
    #$fc->add_shortcut_folder('/tmp');

    if ($fc->run eq "ok") {
        my @filenames = $fc->get_filenames;
        $self->add_mod_file_names(\@filenames);
    }

    $fc->destroy;
}

sub show_about_box
{
    my ($self, $widget) = @_;
    $self->get_widget('aboutdialog')->show;
}

sub ignore_delete { return TRUE;    } 
sub gtk_main_quit { Gtk2->main_quit } 
sub hide_about    { $_[1]->hide;    } 

1;

package main;

HoNModManGtkGUI->new->run;

1;

