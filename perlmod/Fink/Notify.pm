# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Notify module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2005 The Fink Package Manager Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA      02111-1307, USA.
#

package Fink::Notify;

use Fink::Config qw($config);

BEGIN {
        use Exporter ();
        our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
        $VERSION         = (qw$Revision$)[-1];
        @ISA             = qw(Exporter);
        @EXPORT          = qw();
        %EXPORT_TAGS = ( );                     # eg: TAG => [ qw!name1 name2! ],

        # your exported package globals go here,
        # as well as any optionally exported functions
        @EXPORT_OK       = qw();
}

END { }                         # module clean-up code here (global destructor)

=head1 NAME

Fink::Notify - functions for notifying the user out-of-band

=head1 DESCRIPTION

Fink::Notify is a pluggable system for notifying users of events that
happen during package installation/removal.

=head1 SYNOPSIS

  use Fink::Notify;

  my $notifier = Fink::Notify->new('Growl');
  $notifier->notify(
    event       => 'finkPackageInstallationPassed',
    description => 'Installation of package [foo] passed!',
  );

=head1 METHODS

=over 4

=item new([PluginType]) - get a new notifier object

Get a new notifier object, optionally specifying the notification
plugin to use.  If one is not specified, it will use the default
plugin specified in the user's fink.conf.

=cut

sub new {
	my $class = shift;

	my $plugin = shift || $config->param_default('NotifyPlugin', 'Growl');

	my $self;

	eval "require Fink::Notify::$plugin";
	eval "\$self = Fink::Notify::$plugin->new()";

	if ($@) {
		$self = bless({}, $class);
	}

	return $self;
}

=item events() - the list of supported events

The default events are:

	finkPackageBuildPassed
	finkPackageBuildFailed
	finkPackageInstallationPassed
	finkPackageInstallationFailed
	finkPackageRemovalPassed
	finkPackageRemovalFailed

These events can be overridden in a plugin by overriding the events() method.

=cut

our @events = qw(
	finkPackageBuildPassed
	finkPackageBuildFailed
	finkPackageInstallationPassed
	finkPackageInstallationFailed
	finkPackageRemovalPassed
	finkPackageRemovalFailed
);

sub events {
	return wantarray? @events : \@events;
}


=item notify(%args) - notify the user of an event

  $notifier->notify(
    event => 'finkPackageInstallationFailed',
    title => 'Holy cow!  Something bad happened!',
    description => 'Something really bad has occurred, while installing foo.',
  );

Supported Arguments:

=over 4

=item * event

The event name to notify on.

=item * description

The description of what has occurred.

=item * title (optional)

The title of the event.

=back

=cut

sub notify {
	my $self = shift;
	my %args = @_;

	my %default_titles = (
		finkPackageBuildPassed        => 'Fink Build Passed.',
		finkPackageBuildFailed        => 'Fink Build Failed!',
		finkPackageInstallationPassed => 'Fink Installation Passed.',
		finkPackageInstallationFailed => 'Fink Installation Failed!',
		finkPackageRemovalPassed      => 'Fink Removal Passed.',
		finkPackageRemovalFailed      => 'Fink Removal Failed!',
	);

	return undef if (not exists $args{'event'} or not exists $args{'description'});
	$args{'title'} = $default_titles{$args{'event'}} unless (exists $args{'title'} and defined $args{'title'});

	$self->do_notify(%args);
}


=item about() - about the output plugin

This method returns the name and version of the output plugin
currently loaded.

=cut

sub about {
	my $self = shift;

	my @about = ('Null', $VERSION);
	return wantarray? @about : \@about;
}

=item do_notify() - perform a notification (internal)

This is an internal method used to perform a notification.

=cut

sub do_notify {
	return 1;
}

=back

=cut