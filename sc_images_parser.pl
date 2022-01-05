#!/usr/bin/perl
# initial code from https://github.com/osm-hr/my-osm-notes by Matija Nalis <mnalis-git-openstreetmap@voyager.hr> GPLv3+ 2015-2020
# 
# parses OSM notes planet dump and geotag & locally cache StreetComplete images linked
# by Matija Nalis <mnalis-git-openstreetmap@voyager.hr> GPLv3+ 2021-12-24+
#
# Requirements (Debian): sudo apt-get install libxml-parser-perl wget exiftool
#

# FIXME: FIXMEs in code
# FIXME: add README.md, COPYING
# FIXME: cron example (and install cron)
# FIXME: detect and bail out early if wget/exiftool are not present

use utf8;

use strict;
use warnings;
use autodie;
use feature 'say';

use XML::Parser;
use Encode;
use Date::Parse qw /str2time/;
use Getopt::Long;
use Data::Dumper;

#$ENV{'PATH'} = '/usr/local/bin:/usr/bin:/bin';

#
# No user serviceable parts below
#

my $DEBUG = 1;						# use '-v 0' to disable any output
my $DECOMPRESSOR = 'bzcat'; $DECOMPRESSOR = 'pbzip2 -dc' if -x '/usr/bin/pbzip2';	# autodetect fast alternative for unpacking .bz2
my $PICTURE_DIR = './images';				# default directory to store geotagged pictures
my $MAX_AGE_DAYS = 14;					# ignore pictures in notes older than this many days
my $OSN_FILE = '';					# default .osn.bz2 file with OSM Notes XML
my %FILTER_USERS = ();

my $opt_help = '';
my $opt_filter_bbox = '';
my @opt_filter_user = ();

my $opts = GetOptions (	"verbose:+"		=>	\$DEBUG,
                        "picdir=s"		=>	\$PICTURE_DIR,
                        "maxdays=i"		=>	\$MAX_AGE_DAYS,
                        "notesfile=s"		=>	\$OSN_FILE,
                        "decompressor=s"	=>	\$DECOMPRESSOR,
                        "bbox=s"		=>	\$opt_filter_bbox,
                        "user=s"		=>	\@opt_filter_user,
                        "help|h|?"		=>	\$opt_help,
) or usage();

%FILTER_USERS = map { $_ => 1 } @opt_filter_user if @opt_filter_user;

#my %FILTER_BBOX = ( lon_min => 12.7076, lat_min => 41.6049, lon_max => 19.7065, lat_max => 46.5583 );	# Croatia example
my %FILTER_BBOX = ();
if (my @b = split /, */, $opt_filter_bbox) {
    $FILTER_BBOX{'lon_min'} = shift @b;
    $FILTER_BBOX{'lat_min'} = shift @b;
    $FILTER_BBOX{'lon_max'} = shift @b;
    $FILTER_BBOX{'lat_max'} = shift @b;
}

die "Directory --picdir=$PICTURE_DIR must exist" unless -d $PICTURE_DIR;
die "You should use either --bbox or --user to filter results" if !$opt_filter_bbox and !@opt_filter_user;

usage() if $opt_help or !$OSN_FILE;



my $pic_count = undef;
my $last_noteid = undef;
my $last_date = undef;
my $last_lat = undef;
my $last_lon = undef;
my $last_user = undef;
my $last_string = undef;

my $start_time = time;
$DEBUG > 1 && say "parsing $DECOMPRESSOR $OSN_FILE... ";

open my $xml_file, '-|', "$DECOMPRESSOR $OSN_FILE";

binmode STDOUT, ":utf8"; 

my $parser = new XML::Parser;

$parser->setHandlers( Start => \&start_element,
                      End => \&end_element,
                      Char => \&characters,
                    );

#use open qw( :encoding(UTF-8) :std );

$parser->parse($xml_file);

$DEBUG > 1 && say 'completed in ' . (time - $start_time) . ' seconds.';

exit 0;




#########################################
######### XML parser below ##############
#########################################


# when a '<foo>' is seen
sub start_element
{
    my ($parseinst, $element, %attrs) = @_;
    if ($element eq 'note') {
            $last_noteid	= $attrs{'id'};
            $last_lat		= $attrs{'lat'};
            $last_lon		= $attrs{'lon'};
            $last_date		= undef;
            $last_user		= undef;
            $last_string	= undef;
            $pic_count		= 0;		# each new note starts counting pictures from 1
            $DEBUG > 9 && say "New Note $last_noteid at $last_lat,$last_lon:";
            return;
    }

    if ($element eq 'comment') {
            $last_date		= $attrs{'timestamp'};
            $last_user		= $attrs{'user'} || '';
            $last_string	= '';
            $DEBUG > 9 && say "  New comment by $last_user on $last_date";
            return;
    }
}

# content of a element (stuff between <foo> and </foo>) - may be multiple, so concat() it!
sub characters
{
    my ($parseinst, $data) = @_;
    $last_string .= $data;
}

# save each detected picture
sub save_pic($) {
   my ($url) = @_;
   my $note_epoch = str2time($last_date);
   
   my $diff_days = int ((time() - $note_epoch) / 86400);
   $pic_count++;	# N.B. needs to always increment it, even if not processing picture, or we'll miscount when we partly pass $MAX_AGE_DAYS
    
   if ($diff_days > $MAX_AGE_DAYS) {
       $DEBUG > 3 && say "Note $last_noteid: skipping; too old comment: $diff_days days";
       return '';
   }
   
   if (%FILTER_BBOX) {
       if ($last_lat < $FILTER_BBOX{'lat_min'} or $last_lat > $FILTER_BBOX{'lat_max'} or $last_lon < $FILTER_BBOX{'lon_min'} or $last_lon > $FILTER_BBOX{'lon_max'}) {
           $DEBUG > 3 && say "Note $last_noteid: skipping; outside of filtering BBOX [$FILTER_BBOX{'lon_min'}, $FILTER_BBOX{'lat_min'}, $FILTER_BBOX{'lon_max'}, $FILTER_BBOX{'lat_max'}] (has coordinates: $last_lon,$last_lat)";
           return '';
       }
   }

   if (%FILTER_USERS) {
       if (! $FILTER_USERS{$last_user}) {
           $DEBUG > 3 && say "Note $last_noteid: skipping; user '$last_user' not filtered for";
           return '';
       }
   }

   $DEBUG > 2 && say "Note $last_noteid: found pic at: $url (count=$pic_count, lat=$last_lat lon=$last_lon diff=$diff_days days)";

   my $pic_file = $PICTURE_DIR . '/' . $last_noteid . '_' . $pic_count . '.jpg';

   if (-f $pic_file) {
      $DEBUG > 1 && say "Note $last_noteid: skipping; $pic_file already downloaded";
   } else {
      $DEBUG > 0 && say "Note $last_noteid: Downloading $url to $pic_file, and adding GPS coordinates";
      system 'wget', '-q', '--no-clobber', $url, '-O', $pic_file;	# FIXME: make user configurable for eg. curl?
      if (-s $pic_file) {
          system 'exiftool', '-q', '-P', '-overwrite_original', '-GPSLatitude=' . $last_lat, '-GPSLongitude=' . $last_lon, $pic_file;
      } else {
          $DEBUG > 1 && say "Note $last_noteid: skipping geotagging; $pic_file does not exists or failed to download";
          unlink $pic_file;
      }
   }
   return '';
}

# when a '</foo>' is seen
sub end_element
{
    my ($parseinst, $element) = @_;
    if ($element eq 'comment') {
        $last_string =~ s{\b(https?://.*?\.jpg)\b}{save_pic($1)}ge if defined $last_string;	# call save_pic($url) for each URL containing .jpg  picture; we don't care about final value of $last_string
    }
}

# print help
sub usage {
        print STDERR <<EOF;
$0
  [--help]
  [--verbose=4]					// use "-v 0" to be quiet unless an error occurs
  [--picdir=/var/www/pictures]			// save pictures in this directory
  [--maxdays=14]				// ignore note comments older than this many days
  [--decompressor=bzcat]			// if not happy with autodetection
  [--bbox=12.7076,41.6049,19.7065,46.5583]	// limit only to specified BBOX (lon1,lat1,lon2,lat2)
  [--user='someuser']				// filter by OSM username, can be specified multiply times to match any of them
  --notesfile=OK.planet-notes-latest.osn.bz2	// specify OSM XML Notes file to parse

Variables:
  DEBUG:   $DEBUG
  PICDIR:  $PICTURE_DIR
  MAXDAYS: $MAX_AGE_DAYS
  OSNFILE: $OSN_FILE
  DECOMP:  $DECOMPRESSOR
EOF

        say '  USERS:   ' . join ', ', keys %FILTER_USERS;
        say '  BBOX (lon1,lat1,lon2,lat2): ' . (%FILTER_BBOX ? ('(' . $FILTER_BBOX{lon_min} . ', ' . $FILTER_BBOX{lat_min} . ', ' . $FILTER_BBOX{lon_max} . ', ' . $FILTER_BBOX{lat_max} . ')') : 'none');
        exit (2);
}
