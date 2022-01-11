# sc-notes-images
Locally geotag and cache `.jpg` pictures mentioned in OSM Notes (like the ones from StreetComplete)

It can filter which notes to process either via username(s) or via bbox region.

Usually you would call it once a day from cron, like so:
- `cd /home/user1/public_html/sc-notes-images && ./download_planet_notes.sh --bbox=12.7076,41.6049,19.7065,46.5583`

or 

- `cd /home/user1/public_html/sc-notes-images && ./download_planet_notes.sh --user 'OSMuser1' --user 'some Other user'`


Use `sc_images_parser.pl --help` for help
