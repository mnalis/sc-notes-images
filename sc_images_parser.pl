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

use XML::SAX;
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
my $count = 0;
my $start_time = time;
say "parsing $OSN_FILE... ";

#open my $xml_file, '-|', "bzcat $OSN_FILE";
open my $xml_file, '-|', "pbzip2 -dc $OSN_FILE";

binmode STDOUT, ":utf8"; 

my $parser = XML::SAX::ParserFactory->parser(
  Handler => SAX_OSM_Notes->new
);

#use open qw( :encoding(UTF-8) :std );

$parser->parse_file($xml_file);

say 'completed in ' . (time - $start_time) . ' seconds.';

exit 0;




#########################################
######### SAX parser below ##############
#########################################

package SAX_OSM_Notes;

use base qw(XML::SAX::Base);
use Encode;
use Date::Parse qw /str2time/;
#use Data::Dumper;

use strict;
use warnings;

# when a '<foo>' is seen
sub start_element
{
   my ($this, $tag) = @_;
   
   if ($tag->{'LocalName'} eq 'note') {
     $pic_count = 0;	# each new note starts counting pictures from 1
     my $note_id = $tag->{'Attributes'}{'{}id'}{'Value'};
     #say "\n/mn/ start note_id=$note_id";
     $this->{'note_ID'} = $note_id;
     $this->{'last_date'} = undef;
     %{$this->{'users'}} = ();
     $this->{'lat'} = $tag->{'Attributes'}{'{}lat'}{'Value'};
     $this->{'lon'} = $tag->{'Attributes'}{'{}lon'}{'Value'};
     #Dumper($tag->{Attributes})
   }
   
   if ($tag->{'LocalName'} eq 'comment') {
     my $user_id = $tag->{'Attributes'}{'{}user'}{'Value'};
     my $action = $tag->{'Attributes'}{'{}action'}{'Value'};
     $this->{'last_action'} = $1 if $action =~ /^(?:re)?(opened|closed)$/;
     $this->{'text'} = '';
     if (defined($user_id)) {
       #say "  comment by user_id=$user_id, note_id=" . $this->{'note_ID'};
       $this->{'users'}{$user_id} = 1;
       $this->{'last_user'} = $user_id;
     }
     $this->{'last_date'} = $tag->{'Attributes'}{'{}timestamp'}{'Value'};
     #say '   comment timestamp: '  . $this->{'last_date'};
   }
   
   # call the super class to properly handle the event
   return $this->SUPER::start_element($tag)
}

# content of a element (stuff between <foo> and </foo>) - may be multiple, so concat() it!
sub characters
{
   my ($this, $tag) = @_;
   $this->{'text'} .= $tag->{'Data'};
}

# save each detected picture
sub save_pic($$) {
   my ($this, $url) = @_;
   my $note_id = $this->{'note_ID'};
   my $note_epoch = str2time($this->{'last_date'});
   my $lon = $this->{'lon'};
   my $lat = $this->{'lat'};
   my $user = $this->{'last_user'};
   
   my $diff_days = int ((time() - $note_epoch) / 86400);
   $pic_count++;	# N.B. needs to always increment it, even if not processing picture, or we'll miscount when we partly pass $MAX_AGE_DAYS
    
   if ($diff_days > $MAX_AGE_DAYS) {
       $DEBUG > 3 && say "Note $note_id: skipping; too old comment: $diff_days days";
       return '';
   }
   
   if (%FILTER_BBOX) {
       if ($lat < $FILTER_BBOX{'lat_min'} or $lat > $FILTER_BBOX{'lat_max'} or $lon < $FILTER_BBOX{'lon_min'} or $lon > $FILTER_BBOX{'lon_max'}) {
           $DEBUG > 3 && say "Note $note_id: skipping; outside of filtering BBOX [$FILTER_BBOX{'lon_min'}, $FILTER_BBOX{'lat_min'}, $FILTER_BBOX{'lon_max'}, $FILTER_BBOX{'lat_max'}] (has coordinates: $lon,$lat)";
           return '';
       }
   }

   if (%FILTER_USERS) {
       if (! $FILTER_USERS{$user}) {
           $DEBUG > 3 && say "Note $note_id: skipping; user '$user' not filtered for";
           return '';
       }
   }

   $DEBUG > 2 && say "Note $note_id: found pic at: $url (count=$pic_count, lat=$lat lon=$lon diff=$diff_days days)";

   my $pic_file = $PICTURE_DIR . '/' . $note_id . '_' . $pic_count . '.jpg';

   if (-f $pic_file) {
      $DEBUG > 1 && say "Note $note_id: skipping; $pic_file already downloaded";
   } else {
      $DEBUG > 0 && say "Note $note_id: Downloading $url to $pic_file, and adding GPS coordinates";
      system 'wget', '-q', $url, '-O', $pic_file;	# FIXME: make user configurable for eg. curl?
      system 'exiftool', '-q', '-P', '-overwrite_original', '-GPSLatitude=' . $lat, '-GPSLongitude=' . $lon, $pic_file;
   }
   return '';
}

# when a '</foo>' is seen
sub end_element
{
   my ($this, $tag) = @_;

  if ($tag->{'LocalName'} eq 'comment') {
    #say 'end_comment[' . $this->{'note_ID'} .  '], full text=' . $this->{'text'};	# full text of this comment
    if (defined $this->{'text'}) {
       $this->{'text'} =~ s{\b(https?://.*?\.jpg)\b}{save_pic($this,$1)}ge;
    }
    #say "comment tag=" . Dumper($tag);
  }
      
   return $this->SUPER::end_element($tag)
}

1;
