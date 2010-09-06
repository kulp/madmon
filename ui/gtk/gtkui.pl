#!/usr/bin/env perl
use strict;

package HoNModManGtkGUI;
use base qw( Gtk2::GladeXML::Simple );

use XXX;

use Config::General qw(ParseConfig SaveConfig);
use File::Basename;
use File::Temp qw(tempfile);
use Glib qw/TRUE FALSE/;
use Gtk2::Ex::Simple::List;
use Gtk2 '-init';
use Gtk2::SimpleList;
use PAR;
use String::Truncate qw(elide);

our $guidir;
BEGIN {
    $guidir = dirname $0;
    push @INC, "$guidir/../../lib"; #XXX
}
use HoN::Honmod;
use HoN::Madmon qw(:all);

my $gladefile = "$guidir/kui.glade";
my $confdir = scalar glob "~/.madmon";
my $conffile = "madmonrc";
my $confpath = "$confdir/$conffile";

our $VERSION = "0.0.1";
our $user_agent_string = __PACKAGE__ . "/$VERSION";

sub new
{
    my $class = shift;
    my $self;
    if (-f $gladefile) {
        $self = $class->SUPER::new($gladefile);
    } else {
        # Maybe we were packed with PAR
        my $tmp = File::Temp->new;
        print $tmp PAR::read_file(basename $gladefile);
        close $tmp;
        $self = $class->SUPER::new($tmp->filename);
    }

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
            enabledmodfile  => [],
            disabledmodfile => [],
        },
    );

    my %conf = $cg->getall;

    $self->{_config} = \%conf;

    $self->get_widget('applymodsbutton')->set_sensitive(+$self->{_config}{gamedir});
    # TODO clean this up
    $$_ = ref($$_) ? $$_ : [ $$_ ] for map { \$self->{_config}{$_."modfile"} } qw(enabled disabled);
    $self->add_mod_file_names($self->{_config}{enabledmodfile }, 1);
    $self->add_mod_file_names($self->{_config}{disabledmodfile}, 0);

    return $self;
}

sub add_mod_file_names
{
    my ($self, $files, $enabled) = @_;

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

            # TODO remove dupes
            push @{ $sl->{data} },
                [ $enabled, $pb, $mod->name, $mod->version, $mod->description, $filename ];
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
        $self->add_mod_file_names(\@filenames, 1);
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
    eval {
        while (my @indices = $sl->get_selected_indices) {
            splice(@{ $sl->{data} }, $indices[0], 1, ());
        }
    };

    $self->update_saved_mods($sl);

    1;
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

sub update_saved_mods
{
    my ($self, $sl) = @_;
    # TODO differentiate between "enabled" and "successfully applied"
    @{ $self->{_config}{enabledmodfile } } = map { $_->[5] } grep {  $_->[0] } @{ $sl->{data} };
    @{ $self->{_config}{disabledmodfile} } = map { $_->[5] } grep { !$_->[0] } @{ $sl->{data} };
}

sub _mods_from_list
{
    my ($self) = @_;

    my $sl = $self->get_widget('modtreeview');

    # TODO stop referring to fields by hardcoded column indices
    return map { HoN::Honmod->new(filename => $_->[5]) }
        grep { $_->[0] } # only enableds
        @{ $sl->{data} };
}

sub _repores
{
    my ($self) = @_;

    return $self->{repo} ||= create_repo($self->{_config}{gamedir} . "/game");
}

sub _ua
{
    my ($self) = @_;

    return $self->{ua} ||= LWP::UserAgent->new(agent => $user_agent_string);
}

sub applymodsbutton_clicked_cb
{
    my ($self, $widget) = @_;

    my $repores = $self->_repores;

    my @modres = $self->_mods_from_list;
    if (not @modres) {
        $self->_message(info => "No modules enabled!");
        return;
    }

    $_->read for @modres;

    my $ordered = calc_deps(\@modres);

    my $dp = $self->get_widget('dialogProgress');
    my $p = $self->get_widget('progressbar');
    $p->set_fraction(0);
    $dp->show;

    eval {
        my $l = $self->get_widget('progresslabel');

        my $canceled;
        $self->get_widget('buttonCancel')->signal_connect(clicked => sub { $canceled = 1 });

        for my $i (0 .. $#$ordered) {
            die "Canceled by user" if $canceled;

            my $modres = $ordered->[$i];
            $l->set_text("Applying '" . $modres->xml->{name} . "' ...");
            apply_mod($repores, $modres);
            # TODO make us more reponsive; this is a hack for single-threading
            Gtk2->main_iteration while Gtk2->events_pending;
            $p->set_fraction(($i + 1) / @$ordered);
        }
    };
    if ($@) {
        $self->_message(error => "Error while applying mods: $@");
    } else {
        $self->_message(info => "Successfully applied mods");
        $repores->save
            or _message(error => "Failed to save mods repo");
        my $sl = $self->get_widget('modtreeview');
        $self->update_saved_mods($sl);
    }

    $dp->hide;
}

sub imagemenuitemUpdate_activate_cb
{
    my ($self, $widget) = @_;

    my $repores = $self->_repores;
    my @updated;
    my $up = sub {
        my ($modres, $old, $new) = @_;
        my $xml = $modres->xml;
        my $name = $xml->{name};

        my $updateurl = "$xml->{updatedownloadurl}"; # force stringification of XML::Smart object
        if (!$updateurl) {
            $self->_message(warning => "Mod $name is out-of-date (old version: " .
                "$old; new version: $new) but there is no valid download URL for ".
                "the new version");
            return
        }
        $self->_message(info => "Updating mod $name from $old to $new");

        my $tfile = File::Temp->new;
        my $rsp = $self->_ua->get($updateurl, ":content_file" => $tfile->filename);
        if ($rsp->is_error) {
            $self->_message(error => "Error encountered while updating mod $name: " . $rsp->decoded_content);
        } else {
            replace_mod_file($modres, $tfile->filename);
            # TODO check for errors

            $modres->read; # force re-read (XXX remove unnecessary reads)

            push @updated, $modres;
        }
    };

    my @modres = $self->_mods_from_list;
    check_mod_updates($_, $up, undef) for @modres;
    if (@updated == 0) {
        $self->_message(info => "All mods already up-to-date");
    }
}

sub buttonEnableAll_clicked_cb
{
    my ($self, $widget) = @_;
    $_->[0] = 1 for @{ $self->get_widget('modtreeview')->{data} };
}

sub buttonToggleSelected_clicked_cb
{
    my ($self, $widget) = @_;
    my $sl = $self->get_widget('modtreeview');
    my @sel = $sl->get_selected_indices;
    $_->[0] = !$_->[0] for @{ $sl->{data} }[ @sel ];
}

sub buttonDisableAll_clicked_cb
{
    my ($self, $widget) = @_;
    $_->[0] = 0 for @{ $self->get_widget('modtreeview')->{data} };
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

