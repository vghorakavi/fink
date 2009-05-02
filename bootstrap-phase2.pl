# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet
#
# bootstrap-phase2.pl - perl script to install and bootstrap a Fink
#								 installation from source
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2009 The Fink Package Manager Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
#

use 5.008_001;	 # perl 5.8.1 or newer required
use strict;
use warnings;

use FindBin;
use lib "$FindBin::RealBin/perlmod";
use IO::Handle;

$| = 1;

my $homebase = $FindBin::RealBin;
chdir $homebase;

### check if we are unharmed ###

print "Checking package...";
require Fink::Bootstrap;
import Fink::Bootstrap qw(&check_host &check_files);
require Fink::FinkVersion;
import Fink::FinkVersion qw(&fink_version &default_binary_version &get_arch);

if( check_files() == 1 ) {
	exit 1;
}
printf " looks good (fink-%s).\n", fink_version();

### load some modules

require Fink::Services;
import Fink::Services qw(&read_config &execute);
require Fink::CLI;
import Fink::CLI qw(&print_breaking &prompt &prompt_boolean &prompt_selection);
import Fink::Bootstrap qw(&create_tarball &fink_packagefiles &copy_description &get_version_revision &get_selfupdatetrees);

### check if we like this system

print "Checking system...";
my ($host, $distribution);

$host = `update/config.guess`;
chomp($host);
if ($host =~ /^\s*$/) {
	print " ERROR: Can't determine host type.\n";
	exit 1;
}
print " $host\n";

$distribution = check_host($host,1);
if ($distribution eq "unknown") {
	exit(1);
}

my $arch = get_arch();
print "Distribution: $distribution\n";
print "Architecture: $arch\n";

### get version

my ($packageversion, $packagerevision) = &get_version_revision(".",$distribution);

### choose root method

if ($> != 0) {
	# not root now...prompt to determine how to relaunch self
	my $sel_intro = "Fink must be installed and run with superuser (root) ".
	    "privileges. Fink can automatically try to become ".
	    "root when it's run from a user account. Since you're ".
	    "currently running this script as a normal user, the ".
	    "method you choose will also be used immediately for ".
	    "this script. Avaliable methods:";
	my $answer = &prompt_selection("Choose a method:",
					intro   => $sel_intro,
					default => [ value => "sudo" ],
					choices => [
					  "Use sudo" => "sudo",
					  "Use su" => "su",
					  "None, fink must be run as root" => "none" ] );
	my $cmd = "'$homebase/bootstrap' .$answer";
	if ($#ARGV >= 0) {
		$cmd .= " '".join("' '", @ARGV)."'";
	}
	if ($answer eq "sudo") {
		my $env = '';
		$env = "/usr/bin/env PERL5LIB='$ENV{'PERL5LIB'}'" if (exists $ENV{'PERL5LIB'} and defined $ENV{'PERL5LIB'});
		$cmd = "/usr/bin/sudo $env $cmd";
	} elsif ($answer eq "su") {
		$cmd = "$cmd | /usr/bin/su";
	} else {
		print "ERROR: Can't continue as non-root.\n";
		exit 1;
	}
	print "\n";
	exit &execute($cmd, quiet=>1);
}

# we know we're root now

my ($rootmethod);

	if (defined $ARGV[0] and substr($ARGV[0],0,1) eq ".") {
		$rootmethod = shift;
		$rootmethod = substr($rootmethod,1);
	} else {
		print "\n";
		&print_breaking("Fink must be installed and run with superuser (root) ".
						"privileges. Fink can automatically try to become ".
						"root when it's run from a user account. ".
						"Avaliable methods:");
		$rootmethod = &prompt_selection("Choose a method:",
						default => [ value => "sudo" ],
						choices => [
						  "Use sudo" => "sudo",
						  "Use su" => "su",
						  "None, fink must be run as root" => "none" ] );
	}

umask oct("022");

### run some more system tests

print "Checking cc...";
if (-x "/usr/bin/cc") {
	print " looks good.\n";
} else {
	print " not found.\n";
	&print_breaking("ERROR: There is no C compiler on your system. ".
					"Make sure that the Developer Tools are installed.");
	exit 1;
}

print "Checking make...";
if (-x "/usr/bin/make") {
	my $response = `/usr/bin/make --version 2>&1`;
	if ($response =~ /GNU Make/si) {
		print " looks good.\n";
	} else {
		print " is not GNU make.\n";
		&print_breaking("ERROR: /usr/bin/make exists, but is not the ".
						"GNU version. You must correct this situation before ".
						"installing Fink. /usr/bin/make should be a symlink ".
						"pointing to /usr/bin/gnumake.");
		exit 1;
	}
} else {
	print " not found.\n";
	&print_breaking("ERROR: There is no make utility on your system. ".
					"Make sure that the Developer Tools are installed.");
	exit 1;
}

print "Checking head...";
if (-x "/usr/bin/head") {
	my $response = `/usr/bin/head -1 /dev/null 2>&1`;
	if ($response =~ /Unknown option/si) {
		print " is broken.\n";
		&print_breaking("ERROR: /usr/bin/head seems to be corrupted. ".
						"This can happen if you manually installed Perl libwww. ".
						"You'll have to restore /usr/bin/head from another ".
						"machine or from installation media.");
		exit 1;
	} else {
		print " looks good.\n";
	}
} else {
	print " not found.\n";
	&print_breaking("ERROR: There is no head utility on your system. ".
					"Make sure that the Developer Tools are installed.");
	exit 1;
}

### setup the correct packages directory
# (no longer needed: we just use $distribution directly...)
#
#if (-e "packages") {
#		rename "packages", "packages-old";
#		unlink "packages";
#}
#symlink "$distribution", "packages" or die "Cannot create symlink";

### choose installation path

# Check if a location has installed software
sub has_installed_software {
	my $loc = shift;
	return (0 != grep {-d "$loc/$_"} (qw/ bin lib include etc /));
}

my $retrying = 0;
my $nonstandard_warning = 0;

my $installto = shift || "";

OPT_BASEPATH: { ### install path redo block

# ask if the path wasn't passed as a parameter
if ($retrying || not $installto) {
	my $default = '/sw';
	while (1) {
		last if !has_installed_software($default);
		$default =~ /^(.*?)(\d*)$/;
		$default = $1 . (($2 || 1) + 1);
	}
	
	print "\n";
	if ($default ne '/sw' && !$nonstandard_warning) {
		print "It looks like you already have Fink installed in /sw, trying "
		.	"$default instead.\n\n"
		.	"WARNING: This is a non-standard location.\n\n";
		$nonstandard_warning = 1;
	}
	my $prompt = "Please choose the path where Fink should be installed. Note "
		. "that you will be able to use the binary distribution only if you "
		. "choose '/sw'.";
	$installto =
		&prompt($prompt, default => $default);
}
$retrying = 1;
print "\n";

# catch formal errors
if ($installto eq "") {
	print "ERROR: Install path is empty.\n";
	redo OPT_BASEPATH;
}
if (substr($installto,0,1) ne "/") {
	print "ERROR: Install path '$installto' doesn't start with a slash.\n";
	redo OPT_BASEPATH;
}
if ($installto =~ /\s/) {
	print "ERROR: Install path '$installto' contains whitespace.\n";
	redo OPT_BASEPATH;
}

# remove any trailing slash(es)
$installto =~ s,^(/.*?)/*$,$1,;

# check well-known path (NB: these are regexes!)
foreach my $forbidden (
	qw(/ /etc /usr /var /bin /sbin /lib /tmp /dev
	   /usr/lib /usr/include /usr/bin /usr/sbin /usr/share
	   /usr/libexec /usr/X11R6 /usr/X11
	   /root /private /cores /boot
	   /debian /debian/.*)
) {
	if ($installto =~ /^$forbidden$/i) {
		print "ERROR: Refusing to install into '$installto'.\n";
		redo OPT_BASEPATH;
	}
}
if ($installto =~ /^\/usr\/local$/i) {
	my $answer =
		&prompt_boolean("Installing Fink in /usr/local is not recommended. ".
						"It may conflict with third party software also ".
						"installed there. It will be more difficult to get ".
						"rid of Fink when something breaks. Are you sure ".
						"you want to install to /usr/local?", default => 0);
	if ($answer) {
		&print_breaking("You have been warned. Think twice before reporting ".
						"problems as a bug.");
	} else {
		redo OPT_BASEPATH;
	}
} elsif (-d $installto) {
	# check existing contents
	if (has_installed_software $installto) {
		&print_breaking("ERROR: '$installto' exists and contains installed ".
						"software. Refusing to install there.");
		redo OPT_BASEPATH;
	} else {
		&print_breaking("WARNING: '$installto' already exists. If bootstrapping ".
						"fails, try removing the directory altogether and ".
						"re-run bootstrap.");
	}
} else {
	&print_breaking("OK, installing into '$installto'.");
}
print "\n";
}

### create directories

print "Creating directories...\n";

if (not -d $installto) {
	if (&execute("/bin/mkdir -p -m755 $installto")) {
		print "ERROR: Can't create directory '$installto'.\n";
		exit 1;
	}
}

my $selfupdatetrees = get_selfupdatetrees($distribution);

my @dirlist = qw(etc etc/alternatives etc/apt src fink fink/debs var var/lib var/lib/fink);
push @dirlist, "fink/$selfupdatetrees", "fink/$selfupdatetrees/stable", "fink/$selfupdatetrees/local";
foreach my $dir (qw(stable/main stable/crypto local/main)) {
	push @dirlist, "fink/$selfupdatetrees/$dir", "fink/$selfupdatetrees/$dir/finkinfo",
		"fink/$selfupdatetrees/$dir/binary-darwin-$arch";
}
foreach my $dir (@dirlist) {
	if (not -d "$installto/$dir") {
		if (&execute("/bin/mkdir -m755 $installto/$dir")) {
			print "ERROR: Can't create directory '$installto/$dir'.\n";
			exit 1;
		}
	}
}

unlink "$installto/fink/dists";

symlink "$distribution", "$installto/fink/dists" or die "ERROR: Can't create symlink $installto/fink/dists\n";

### for now, we simply symlink $distribution to $selfupdatetrees, but eventually we may need to do something more complicated

if (not $selfupdatetrees eq $distribution) {
	symlink "$selfupdatetrees", "$installto/fink/$distribution" or die "ERROR: Can't create symlink $installto/fink/$distribution\n";
}

### create fink tarball for bootstrap

my $packagefiles = &fink_packagefiles();

if ( &create_tarball($installto, "fink", $packageversion, $packagefiles) == 1 ) {
	exit 1;
}

### copy package info needed for bootstrap

{
my $script = "/bin/mkdir -p $installto/fink/dists/stable/main/finkinfo/base\n";
$script .= "/bin/cp $selfupdatetrees/*.info $selfupdatetrees/*.patch $installto/fink/dists/stable/main/finkinfo/base/\n";

if ( &copy_description($script,$installto, "fink", $packageversion, $packagerevision, "stable/main/finkinfo/base", "fink-$distribution.info", "fink.info.in" ) == 1 ) {
	exit 1;
}
}

### load the Fink modules

require Fink::Config;
require Fink::Engine;
require Fink::Configure;
require Fink::Bootstrap;

### setup initial configuration

print "Creating initial configuration...\n";
my ($configpath, $config);

$configpath = "$installto/etc/fink.conf";
open(CONFIG, '>', $configpath) or die "can't create configuration $configpath: $!\n";
print CONFIG <<"EOF";
# Fink configuration, initially created by bootstrap
Basepath: $installto
RootMethod: $rootmethod
Trees: local/main stable/main stable/crypto
Distribution: $distribution
SelfUpdateTrees: $selfupdatetrees
EOF

close(CONFIG) or die "can't write configuration $configpath: $!\n";

$config = &read_config($configpath);
# override path to data files (update, mirror)
no warnings 'once';
$Fink::Config::libpath = $homebase;
use warnings 'once';
Fink::Engine->new_with_config($config);

### interactive configuration

Fink::Configure::configure();

### bootstrap

Fink::Bootstrap::bootstrap();

### remove dpkg-bootstrap.info and dpkg-bootstrap.patch, to avoid later confusion

&execute("/bin/rm -f $installto/fink/dists/stable/main/finkinfo/base/dpkg-bootstrap.info $installto/fink/dists/stable/main/finkinfo/base/dpkg-bootstrap.patch");

### copy included package info tree if present

my $showversion = "";
if ($packageversion !~ /cvs/) {
	$showversion = "-$packageversion";
}

my $endmsg = "Internal error.";

my $dbv = default_binary_version($distribution);
if (-d "$homebase/pkginfo") {
	if (&execute("cd $homebase/pkginfo && ./inject.pl $installto -quiet")) {
		# inject failed
		$endmsg = <<"EOF";
Copying the package description tree failed. This is no big harm;
your Fink installation should work nonetheless.
You can add the package descriptions at a later time if you want to
compile packages yourself.
You can get them
EOF
if (defined $dbv) {
$endmsg .= "by installing the dists-$distribution-$dbv.tar.gz
tarball, or";
}
		$endmsg .= " by running the command 'fink selfupdate'.";
	} else {
		# inject worked
		$endmsg = <<"EOF";
You should now have a working Fink installation in '$installto'.
EOF
	}
} else {
	# this was not the 'full' tarball
	$endmsg = <<"EOF";
You should now have a working Fink installation in '$installto'.
You still need package descriptions if you want to compile packages yourself.
You can get them
EOF
if (defined $dbv) {
$endmsg .= "by installing the dists-$distribution-$dbv.tar.gz
tarball, or";
}
	$endmsg .= " by running the command 'fink selfupdate'.";
}

### create Packages.gz files for apt

# set PATH so we find dpkg-scanpackages
$ENV{PATH} = "$installto/sbin:$installto/bin:".$ENV{PATH};

Fink::Engine::cmd_scanpackages();

### the final words...

$endmsg =~ s/\s+/ /gs;
$endmsg =~ s/ $//;

print "\n";
&print_breaking($endmsg);
print "\n";
&print_breaking(
    "Run '. $installto/bin/init.sh' to set up this terminal session ".
    "environment to use Fink. To make the software installed by Fink ".
    "available in all of your future terminal shells, add ".
    "'. $installto/bin/init.sh' to the init script '.profile' or ".
    "'.bash_profile' in your home directory. The program ".
    "$installto/bin/pathsetup.sh can help with this. Enjoy."
);
print "\n";

### eof
exit 0;