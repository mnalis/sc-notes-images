#!/usr/bin/perl -T
# initial code from https://github.com/osm-hr/my-osm-notes by Matija Nalis <mnalis-git-openstreetmap@voyager.hr> GPLv3+ 2015-2020
# 
# parses OSM notes planet dump and locally cache StreetComplete images linked,
# by Matija Nalis <mnalis-git-openstreetmap@voyager.hr> GPLv3+ 2021-12-24+
#
# Requirements (Debian): sudo apt-get install libxml-sax-perl wget exiftool libxml-sax-expatxs-perl
#

# FIXME: FIXMEs in code
# FIXME: add README.md, COPYING
# FIXME: speedup! orignally 14+ minutes, while bzcat is 1minute, and pbzip2 -dc is 15 seconds! Down to 6 minutes with libxml-sax-expatxs-perl
# FIXME: cmdline arguments for FILTER_BBOX, FILTER_USERS
# FIXME: cron example (and install cron)

use utf8;

use strict;
use warnings;
use autodie;
use feature 'say';

use XML::Parser;
use Encode;
use Date::Parse qw /str2time/;
#use Data::Dumper;

$ENV{'PATH'} = '/usr/bin:/bin';

my $PICTURE_DIR = './images';
my $MAX_AGE_DAYS = 14;	# ignore pictures in notes older than this many days

#my %FILTER_USERS = map { $_ => 1 } ('Matija Nalis', 'mnalis ALTernative');
my %FILTER_USERS = ();

my %FILTER_BBOX = ( lon_min => 12.7076, lat_min => 41.6049, lon_max => 19.7065, lat_max => 46.5583 );
#my %FILTER_BBOX = ();


my $OSN_FILE = 'OK.planet-notes-latest.osn.bz2';
$OSN_FILE = 'example2.xml.bz2';	# FIXME DELME

#
# No user serviceable parts below
#

my $DEBUG = $ENV{DEBUG} || 0;
my $pic_count = undef;
my $last_noteid = undef;
my $last_date = undef;
my $last_lat = undef;
my $last_lon = undef;
my $last_user = undef;
my $last_string = undef;

my $start_time = time;
$DEBUG > 1 && say "parsing $OSN_FILE... ";

#open my $xml_file, '-|', "bzcat $OSN_FILE";
open my $xml_file, '-|', "pbzip2 -dc $OSN_FILE";

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
    my( $parseinst, $element, %attrs ) = @_;
    SWITCH: {
           if ($element eq 'note') {
                   $last_noteid	= $attrs{'id'};
                   $last_lat	= $attrs{'lat'};
                   $last_lon	= $attrs{'lon'};
                   $last_date	= undef;
                   $last_user	= undef;
                   $last_string = undef;
                   $pic_count	= 0;		# each new note starts counting pictures from 1
                   $DEBUG > 9 && say "New Note $last_noteid at $last_lat,$last_lon:";
                   last SWITCH;
           }

           if ($element eq 'comment') {
                   $last_date	= $attrs{'timestamp'};
                   $last_user	= $attrs{'user'} || '';
                   $last_string = '';
                   $DEBUG > 9 && say "  New comment by $last_user on $last_date";
                   last SWITCH;
           }
    }
}

# content of a element (stuff between <foo> and </foo>) - may be multiple, so concat() it!
sub characters
{
    my( $parseinst, $data ) = @_;
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
      system 'wget', '-q', $url, '-O', $pic_file;	# FIXME: make user configurable for eg. curl?
      system 'exiftool', '-q', '-P', '-overwrite_original', '-GPSLatitude=' . $last_lat, '-GPSLongitude=' . $last_lon, $pic_file;
   }
   return '';
}

# when a '</foo>' is seen
sub end_element
{
    my( $parseinst, $element ) = @_;
    if ($element eq 'comment') {
        $last_string =~ s{\b(https?://.*?\.jpg)\b}{save_pic($1)}ge if defined $last_string;
    }
}
