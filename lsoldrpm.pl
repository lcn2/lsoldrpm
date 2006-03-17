#!/usr/bin/perl -wT
#
# lsoldrpm - list old RPMs found in a directory
#
# @(#) $Revision$
# @(#) $Id$
# @(#) $Source$
#
# Copyright (c) 2006 by Landon Curt Noll.  All Rights Reserved.
#
# Permission to use, copy, modify, and distribute this software and
# its documentation for any purpose and without fee is hereby granted,
# provided that the above copyright, this permission notice and text
# this comment, and the disclaimer below appear in all of the following:
#
#       supporting documentation
#       source copies
#       source works derived from this source
#       binaries derived from this source or from derived source
#
# LANDON CURT NOLL DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
# INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO
# EVENT SHALL LANDON CURT NOLL BE LIABLE FOR ANY SPECIAL, INDIRECT OR
# CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF
# USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.
#
# chongo (Landon Curt Noll, http://www.isthe.com/chongo/index.html) /\oo/\
#
# Share and enjoy! :-)

# An RPM in a diretory is considered old if there is a RPM for the
# same module with a newer version in that same directory.  For example,
# if we have these RPM files:
#
#	gcc-3.4.4-2.i386.rpm
#	gcc-3.4.5-2.i386.rpm
#
# then gcc-3.4.4-2.i386.rpm is an old RPM.  However if we have these RPMs:
#
#	audit-1.0.12-1.EL4.i386.rpm
#	audit-libs-1.0.12-1.EL4.i386.rpm
#
# then neither is an old RPM because they refer to two different modules.
#
# There is a special exception.  Multiple kernel RPMs may (and often are)
# installed on the same system.  Thus for these RPMs:
#
#	kernel-2.6.9-22.0.2.EL.i686.rpm
#	kernel-2.6.9-34.EL.i686.rpm
#	kernel-devel-2.6.9-22.0.2.EL.i686.rpm
#	kernel-devel-2.6.9-34.EL.i686.rpm
#	kernel-doc-2.6.9-22.0.2.EL.noarch.rpm
#	kernel-doc-2.6.9-34.EL.noarch.rpm
#
# none of them are considered old unless the -k flag is given.  With the
# exception of the kernel-utils RPM, all kernel-*.rpm files fit into
# this special case.

# requirements
#
use strict;
use bytes;
use vars qw($opt_v $opt_b $opt_k $opt_m $opt_n $opt_r);
use Getopt::Long;
use File::Find;
no warnings 'File::Find';
use File::Basename;

# required modules that are found in CPAN
#
BEGIN {
    # testing the modules
    my $found = -1;
    my @DBs = qw(RPM::VersionSort);
    for my $mod (@DBs) {
    	if (eval "require $mod") {
	    $mod->import();
	    ++$found;
	} else {
	    warn "$0: could not find CPAN module: $mod";
	    warn "$0: perhaps you need to do: perl -MCPAN -e '\$ENV{FTP_PASSIVE} = 1; install $mod;'\n";
	}
    }
    if ($found != $#DBs) {
	die "$0: required modules missing, see http://www.perl.com/CPAN/\n";
    }
};

# version - RCS style *and* usable by MakeMaker
#
my $VERSION = substr q$Revision: 1.1 $, 10;
$VERSION =~ s/\s+$//;

# my vars
#
my $untaint = qr|^([-+\w\s./]+)$|; 	# untainting path pattern
my @rpm;				# list of RPM filenames found
my %rpm_path;		# $rpm_path{$i} is dir path of $i without final /
#
# NOTE: For calc-devel-2.11.11-0.i686.rpm
#
#	RPM name:	calc-devel
#	RPM version:	2.11.11
#	RPM release	0
#	RPM ext:	i686.rpm
#
# NOTE: For java-1.4.2-ibm-devel-1.4.2.3-1jpp_14rh.i386.rpm
#
#	RPM name:	java-1.4.2-ibm-devel
#	RPM version:	1.4.2.3
#	RPM release:	1jpp_14rh
#	RPM ext:	i386.rpm
#
my %rpm_name;		# $rpm_name{$i} is the RPM name of RPM filename $i
my %rpm_ver;		# $rpm_ver{$i} is the RPM version of RPM filename $i
my %rpm_rel;		# $rpm_rel{$i} is the RPM release of RPM filename $i
my %rpm_ext;		# $rpm_ext{$i} is chars after release for filename $i
#
my %rpm_recent_ver;	# $rpm_recent_ver{$i} most recent RPM version of
			# the RPM name $i
my %rpm_recent_rel;	# $rpm_recent_ver{$i} most recent RPM release of
			# the RPM name $i
my %rpm_recent_ext;	# $rpm_recent_ext{$i} most recent RPM after rel chars
			# the RPM name $i

# usage and help
#
my $usage = "$0 [-b] [-k] [-m | -r] [-n] [-v lvl] dir";
my $help = qq{$usage

	-b	banenames, ignore leading path to RPMs (default: list path)
	-k	list older kernel based RPM (default: don't)
	-m	just list module names (default: list filename)
	-r	just list module-version-release names (default: list filename)
	-n	print newest RPMs (default: list just older RPMs)
	-v lvl	verbose / debug level

	dir	directory into which RPM files may be found
};
my %optctl = (
    "b" => \$opt_b,
    "k" => \$opt_k,
    "m" => \$opt_m,
    "n" => \$opt_n,
    "r" => \$opt_r,
    "v=i" => \$opt_v
);


# function prototypes
#
sub error($$);
sub debug($$);


# setup
#
MAIN: {
    my %find_opt;	# File::Find directory tree walk options
    my $dir;		# directory argument
    my $filename;
    my $name;		# RPM module name

    # setup
    #
    select(STDOUT);
    $| = 1;

    # set the defaults
    #
    $opt_v = 0;

    # parse args
    #
    if (!GetOptions(%optctl)) {
	error(1, "invalid command line\nusage: $help");
    }
    if ($#ARGV != 0) {
	error(2, "missing or extra argument\nusage: $help");
    }
    if (defined $opt_m && defined $opt_r) {
	error(3, "-m and -r conflict\nusage: $help");
    }
    $dir = $ARGV[0];

    # firewall
    #
    if (! -d $dir) {
	error(4, "not a directory: $dir");
    }
    if (! -r $dir) {
	error(5, "directory not readable: $dir");
    }
    if (! -x $dir) {
	error(6, "directory not searchable: $dir");
    }
    debug(1, "searching for old RPMs under $dir");

    # setup to walk the directory argument
    #
    $find_opt{wanted} = \&wanted; # call this on each non-pruned node
    $find_opt{bydepth} = 0;	# walk from top down, not from bottom up
    $find_opt{follow} = 0;	# do not follow symlinks
    $find_opt{no_chdir} = 0;	# OK to chdir as we walk the tree
    $find_opt{untaint} = 1;	# untaint dirs we chdir to
    $find_opt{untaint_pattern} = $untaint; # untaint pattern
    $find_opt{untaint_skip} = 1; # we will skip any dir that is tainted

    # find RPM files directly under the directory argument
    #
    find(\%find_opt, $dir);
    @rpm = sort(@rpm);

    # parse the found RPM set filenames
    #
    foreach $filename (@rpm) {

	# parse this RPM into name, version, release
	#
	if ($filename =~ m{^(.*)/(.+)-([^-]+)-(.+)\.([^.]+\.rpm)$}) {
	    # save parts
	    #
	    $rpm_path{$filename} = $1;
	    $rpm_name{$filename} = $2;
	    $rpm_ver{$filename} = $3;
	    $rpm_rel{$filename} = $4;
	    $rpm_ext{$filename} = $5;

	    # all kernel RPMs (except kernel-utils) are most recent unless -k
	    # so we pretend their name includes their version and release
	    #
	    # XXX - kernel-pcmcia-cs is also a non-kernel RPM
	    #
	    if (! defined $opt_k &&
	        ($rpm_name{$filename} eq "kernel" ||
		 ($rpm_name{$filename} =~ /^kernel-/ &&
	          $rpm_name{$filename} ne "kernel-utils"))) {
		debug(3, "RPM renaming kernel RPM: from $rpm_name{$filename}");
		debug(3, "                           to $rpm_name{$filename}" .
			  "-$rpm_ver{$filename}-$rpm_rel{$filename}");
		$rpm_name{$filename} .=
		    "-$rpm_ver{$filename}-$rpm_rel{$filename}";
	    }

	    # debug parse
	    #
	    debug(3, "RPM file: $filename");
	    debug(3, "RPM path: $rpm_path{$filename}");
	    debug(3, "RPM name: $rpm_name{$filename}");
	    debug(3, "RPM ver:  $rpm_ver{$filename}");
	    debug(3, "RPM rel:  $rpm_rel{$filename}");
	    debug(3, "RPM ext:  $rpm_ext{$filename}");
	} else {
	    debug(-1, "Warning: cannot parse filename: $filename");
	}
    }

    # determine the most recent version-release for each RPM module
    #
    foreach $filename (@rpm) {

	# if first time we have seen this RPM name, it will be the most recent
	#
    	$name = $rpm_name{$filename};
	if (! defined $rpm_recent_ver{$name}) {
	    debug(2, "found 1st RPM name: $name");
	    debug(2, "found 1st RPM ver:  $rpm_ver{$filename}");
	    debug(2, "found 1st RPM rel:  $rpm_rel{$filename}");
	    debug(2, "found 1st RPM ext:  $rpm_ext{$filename}");
	    $rpm_recent_ver{$name} = $rpm_ver{$filename};
	    $rpm_recent_rel{$name} = $rpm_rel{$filename};
	    $rpm_recent_ext{$name} = $rpm_ext{$filename};

	# compare RPM version and then RPM relese, same newer if we found it
	#
	} elsif (rpmvercmp($rpm_recent_ver{$name}, $rpm_ver{$filename}) < 0 ||
		 (rpmvercmp($rpm_recent_ver{$name}, $rpm_ver{$filename}) == 0 &&
		  rpmvercmp($rpm_recent_rel{$name}, $rpm_rel{$filename}) < 0)) {
	    debug(2, "found newer RPM name: $name");
	    debug(2, "found newer RPM ver:  $rpm_ver{$filename}");
	    debug(2, "  older was RPM ver:  $rpm_recent_ver{$name}");
	    debug(2, "found newer RPM rel:  $rpm_rel{$filename}");
	    debug(2, "  older was RPM rel:  $rpm_recent_rel{$name}");
	    debug(2, "found newer RPM ext:  $rpm_ext{$filename}");
	    debug(2, "  older was RPM ext:  $rpm_recent_ext{$name}");
	    $rpm_recent_ver{$name} = $rpm_ver{$filename};
	    $rpm_recent_rel{$name} = $rpm_rel{$filename};
	    $rpm_recent_ext{$name} = $rpm_ext{$filename};

	# this RPM is not newer
	#
	} else {
	    debug(3, "found older RPM name: $name");
	    debug(3, "found older RPM ver:  $rpm_ver{$filename}");
	    debug(3, "   newer is RPM ver:  $rpm_recent_ver{$name}");
	    debug(3, "found older RPM rel:  $rpm_rel{$filename}");
	    debug(3, "   newer is RPM rel:  $rpm_recent_rel{$name}");
	    debug(3, "found older RPM ext:  $rpm_ext{$filename}");
	    debug(3, "   newer is RPM ext:  $rpm_recent_ext{$name}");
	}
    }

    # if -n print the most recent RPMs - XXX this is wrong
    #
    # XXX - try building, for each RPM name, an array of hashes, each hash
    #	    of which has an RPM ver, RPM rel, RPM ext, RPM path so that
    #	    one can sort that array of hashes by version-release.
    #	    Then print the appropriatre the last or first-to-next-to-last
    #	    or all versions as needed.
    #
    if (defined $opt_n) {
	foreach $name (%rpm_name) {

	    # print leading path unless -b
	    #
	    print "$rpm_path{$name}/" unless defined $opt_b;

	    # print just RPM name if -m
	    #
	    if (defined $opt_m) {
		print "$name\n";

	    # print RPM name-version-release-version if -r
	    #
	    } elsif (defined $opt_r) {
		print "$name-$rpm_recent_ver{$name}-$rpm_recent_rel{$name}\n";

	    # print name-version-release-version.ext otherwise
	    #
	    } else {
		print "$name-$rpm_recent_ver{$name}-$rpm_recent_rel{$name}" .
		      ".$rpm_recent_ext{$name}\n";
	    }
	}
    }
}


# wanted - File::Find tree walking function called at each non-pruned node
#
# NOTE: The File::Find calls this function with this argument:
#
#	$_			current filename within $File::Find::dir
#
# and these global vaules set:
#
#	$File::Find::dir	current directory name
#	$File::Find::name 	complete pathname to the file
#	$File::Find::prune	set 1 one to prune current node out of path
#	$File::Find::topdir	top directory path ($srcdir)
#	$File::Find::topdev	device of the top directory
#	$File::Find::topino	inode number of the top directory
#				!= 0  ==> function being called by add_readme()
#
sub wanted($)
{
    my $filename = $_;		# current filename within $File::Find::dir
    my $filedev;		# device of $filename
    my $fileino;		# inode numner of $filename

    # initial debug
    #
    debug(5, "in wanted: arg: $filename");
    debug(6, "in wanted: File::Find::name: $File::Find::name");

    # stat the filename argment
    #
    ($filedev, $fileino) = stat($filename);
    debug(6, "filedev: $filedev");
    debug(6, "fileino: $fileino");

    # ignore but don't prune the initial directory (.)
    #
    if (-d $filename &&
    	$File::Find::topdev == $filedev &&
	$File::Find::topino == $fileino) {
	debug(4,
	  "in wanted: just passing through initial dir: $File::Find::topdir");
	debug(6, "File::Find::topdev: $File::Find::topdev");
	debug(6, "File::Find::topino: $File::Find::topino");
	return;
    }

    # prune a directory the initial directory (.)
    #
    if (-d $filename &&
    	($File::Find::topdev != $filedev || $File::Find::topino != $fileino)) {
	debug(6, "File::Find::topdev: $File::Find::topdev");
	debug(6, "File::Find::topino: $File::Find::topino");
	debug(4, "in wanted: prune sub-directory: $File::Find::name");
	$File::Find::prune = 1;
	return;
    }

    # ignore non-files
    #
    if (! -f $filename) {
	debug(4, "in wanted: prune non-file: $File::Find::name");
	$File::Find::prune = 1;
	return;
    }

    # ignore files that do not end in .rpm
    #
    if ($filename !~ /\.rpm$/) {
	debug(4, "in wanted: prune non-RPM-file: $File::Find::name");
	$File::Find::prune = 1;
	return;
    }

    # record the RPM file
    #
    debug(4, "in wanted: will process: $File::Find::name");
    push @rpm, $File::Find::name;
    return;
}


# error - report an error and exit
#
# given:
#       $exitval	exit code value
#       $msg		the message to print
#
sub error($$)
{
    my ($exitval, $msg) = @_;    # get args

    # parse args
    #
    if (!defined $exitval) {
	$exitval = 254;
    }
    if (!defined $msg) {
	$msg = "<<< no message supplied >>>";
    }
    if ($exitval =~ /\D/) {
	$msg .= "<<< non-numeric exit code: $exitval >>>";
	$exitval = 253;
    }

    # issue the error message
    #
    print STDERR "$0: $msg\n";

    # issue an error message
    #
    exit($exitval);
}


# debug - print a debug message is debug level is high enough
#
# given:
#       $min_lvl	minimum debug level required to print (<0 ==> warning)
#       $msg		message to print
#
# NOTE: The DEBUG[$min_lvl]: header is printed for $min_lvl >= 0 only.
#
# NOTE: When $min_lvl <= 0, the message is always printed
#
sub debug($$)
{
    my ($min_lvl, $msg) = @_;    # get args

    # firewall
    #
    if (!defined $min_lvl) {
    	error(97, "debug called without a minimum debug level");
    }
    if ($min_lvl !~ /-?\d/) {
    	error(98, "debug called with non-numeric debug level: $min_lvl");
    }
    if ($opt_v < $min_lvl) {
	return;
    }
    if (!defined $msg) {
    	error(99, "debug called without a message");
    }

    # issue the debug message
    #
    if ($min_lvl < 0) {
	print STDERR "$msg\n";
    } else {
	print STDERR "DEBUG[$min_lvl]: $msg\n";
    }
}
