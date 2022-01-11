# sc-notes-images
Locally geotag and cache pictures from OSM Notes (like from StreetComplete)

usually you would call it once a day from cron, like so:
- cd /home/user1/public_html/sc-notes-images && ./download_planet_notes.sh --bbox=12.7076,41.6049,19.7065,46.5583
or 
- cd /home/user1/public_html/sc-notes-images && ./download_planet_notes.sh --user 'OSMuser1' --user 'some Other user'
