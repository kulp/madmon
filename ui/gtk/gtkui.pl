#!/usr/bin/env perl
use strict;

package HoNModManGtkGUI;
use base qw( Gtk2::GladeXML::Simple );

#use XXX;

use File::Temp qw(tempfile);
#use File::Basename qw(basename);
use Glib qw/TRUE FALSE/;
use Gtk2 '-init';
#use Gtk2::Pango;
use Gtk2::SimpleList;
use Gtk2::Ex::Simple::List;
use String::Truncate qw(elide);

use lib "../../lib"; #XXX
use HoN::Honmod;

my $gladefile = "kui.glade";

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new( $gladefile );

    my $tv = $self->get_widget('modtreeview');
    my $sl = Gtk2::Ex::Simple::List->new_from_treeview(
                    $tv, qw(
                    Enabled     bool
                    Icon        pixbuf
                    Name        text
                    Version     text
                    Description text
                    ));

    my $renderer = Gtk2::CellRendererText->new;
    $renderer->set(ellipsize => "end");
    my $dcol = Gtk2::TreeViewColumn->new_with_attributes("Description", $renderer, text => 4);
    my $ncol = Gtk2::TreeViewColumn->new_with_attributes("Name"       , $renderer, text => 2);
    # remove auto-generated column and replace with an ellipsizing one
    $sl->remove_column($sl->get_column(4));
    $sl->insert_column($dcol,4);
    $sl->remove_column($sl->get_column(2));
    $sl->insert_column($ncol,2);

    $sl->get_column(1)->set('min-width' => 56); # Icon fixed width
    $sl->get_column(1)->set('max-width' => 56);
    $sl->get_column(2)->set('min-width' => 128); # Name min width
    $_->set_resizable(1) for map { $sl->get_column($_) } 1 .. 4;

    # TODO fix accelerator collision between Apply and Add
    #my $amb = $self->get_widget('addmodbutton');
    #$amb->set_use_underline(0);
    #$amb->set_label("gtk-add");
    #$amb->set_use_stock(1);

    return $self;
}

sub add_mod_file_names
{
    my ($self, $files) = @_;

    my $sl = $self->get_widget('modtreeview');

    my @bads;
    for my $filename (@$files) {
        next unless -f $filename;
        eval { # just skip if we have an error
            my $mod = HoN::Honmod->new(filename => $filename);
            $mod->read;
            my $iconstr = $mod->file("icon.png");
            my $pb;
            if ($iconstr) {
                my $tmp = File::Temp->new; # unlinks at DESTROY time
                my $iconfilename = $tmp->filename;
                print $tmp $iconstr->contents;
                close $tmp;
                $pb = Gtk2::Gdk::Pixbuf->new_from_file($iconfilename);
            }

            push @{ $sl->{data} }, [ 0, $pb, $mod->name, $mod->version, $mod->description ];
        };
        if ($@) {
            push @bads, $filename;
        }
    }

    if (@bads) {
        my $message = Gtk2::MessageDialog->new(
                $sl->get_toplevel, [], 'warning', 'ok',
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

sub menuitemSelectGameDir_activate_cb
{
    my ($self, $widget) = @_;

    my $dc = Gtk2::FileChooserDialog->new(
            'Select game directory',
            $widget->get_toplevel,
            'select-folder',
            'gtk-cancel' => 'cancel',
            'gtk-ok'     => 'ok'
        );

    $dc->set_current_folder($self->{gamedir}) if $self->{gamedir};

    while ($dc->run eq "ok") {
        my $dir = $dc->get_filename;
        if (-d $dir and -d "$dir/game") {
            $self->{gamedir} = $dir;
            last;
        } else {
            my $message = Gtk2::MessageDialog->new(
                    $widget->get_toplevel, [], 'warning', 'ok',
                    "The selected directory is not a valid HoN directory");
            $message->run;
            $message->destroy;
        }
    }

    $dc->destroy;
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

