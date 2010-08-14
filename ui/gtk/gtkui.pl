#!/usr/bin/env perl
use strict;

package HoNModManGtkGUI;
use base qw( Gtk2::GladeXML::Simple );

use feature "say";

use XXX;

use Config::General qw(ParseConfig SaveConfig);
use File::Temp qw(tempfile);
use Glib qw/TRUE FALSE/;
use Gtk2::Ex::Simple::List;
use Gtk2 '-init';
use Gtk2::SimpleList;
use String::Truncate qw(elide);

use lib "../../lib"; #XXX
use HoN::Honmod;
use HoN::Madmon qw(:all);

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
                    Filename    hidden
                    ));

    $sl->get_selection->set_mode('multiple');

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

    my $confdir = scalar glob "~/.madmon";
    my $conffile = "madmonrc";
    my $confpath = "$confdir/$conffile";
    if (!-d $confdir) {
        mkdir $confdir
            or die "Could not create madmon conf directory '$confdir'";
    }
    if (!-f $confpath) {
        open my $fh, ">", $confpath;
    }

    my $cg = $self->{_cg} = Config::General->new(
        -ConfigFile => $conffile,
        -ConfigPath => $confdir,
        -DefaultConfig => {
            #gamedir     => (scalar glob '~/HoN'),
            appliedmods => [],
        },
    );

    my %conf = $cg->getall;

    $self->{_config} = \%conf;

    $self->get_widget('applymodsbutton')->set_sensitive(+$self->{_config}{gamedir});

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

            #push @{ $self->{_config}{modfiles} }, $filename;
            push @{ $sl->{data} }, [ 1, $pb, $mod->name, $mod->version, $mod->description, $filename ];
        };
        if ($@) {
            push @bads, $filename;
        }
    }

    if (@bads) {
        $self->_message(warning => "Failed to load the following modules:\n" . join "\n", @bads);
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
    if (my $dl = $self->{_config}{downloaddir}) {
        $fc->add_shortcut_folder($dl);
    }

    if ($fc->run eq "ok") {
        my @filenames = $fc->get_filenames;
        $self->add_mod_file_names(\@filenames);
    }

    $fc->destroy;
}

sub delmodbutton_clicked_cb
{
    my ($self, $widget) = @_;
    my $sl = $self->get_widget('modtreeview');
    # TODO redo this, there must be a better way
    # tried setting $sl->{data} wholesale but I get a segfault
    # at least this way ensures my indices are up-to-date
    while (my @indices = $sl->get_selection->get_selected_rows->get_indices) {
        splice(@{ $sl->{data} }, $indices[0], 1, ());
    }
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

    $dc->set_current_folder($self->{_config}{gamedir}) if $self->{_config}{gamedir};

    while ($dc->run eq "ok") {
        my $dir = $dc->get_filename;
        if (-d $dir and -d "$dir/game") {
            $self->{_config}{gamedir} = $dir;
            last;
        } else {
            $self->_message(warning => "The selected directory is not a valid HoN directory");
            delete $self->{_config}{gamedir};
        }
    }

    $self->get_widget('applymodsbutton')->set_sensitive(+$self->{_config}{gamedir});

    $dc->destroy;
}

sub show_about_box
{
    my ($self, $widget) = @_;
    $self->get_widget('aboutdialog')->show;
}

sub _message
{
    my ($self, $type, $text) = @_;
    my $message = Gtk2::MessageDialog->new($self->get_widget('mainwindow'), [], $type, 'ok', $text);
    $message->run;
    $message->destroy;
}

sub applymodsbutton_clicked_cb
{
    my ($self, $widget) = @_;

    # TODO progress bar
    warn "applying mods";
    my $sl = $self->get_widget('modtreeview');

    my $repores = create_repo($self->{_config}{gamedir} . "/game");

    my @modres = map { HoN::Honmod->new(filename => $_->[5]) }
        grep { $_->[0] } # only enableds
        @{ $sl->{data} };

    if (not @modres) {
        $self->_message(info => "No modules enabled!");
        return;
    }

    $_->read for @modres;

    my $ordered = calc_deps(\@modres);

    eval {
        for my $modres (@$ordered) {
            say "Applying mod " . $modres->{filename} . " ...";
            apply_mod($repores, $modres);
        }
    };
    if ($@) {
        $self->_message(error => "Error while applying mods: $@");
    } else {
        $self->_message(info => "Successfully applied mods");
        $repores->save
            or _message(error => "Failed to save mods repo");
    }
}

sub ignore_delete { return TRUE;    } 
sub hide_about    { $_[1]->hide;    } 

sub main_quit {
    my ($self, $widget) = @_;

    $self->{_cg}->save_file(($self->{_cg}->files)[0], $self->{_config});

    Gtk2->main_quit;
} 

1;

package main;

HoNModManGtkGUI->new->run;

1;

