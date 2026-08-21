#!/usr/bin/env bash
# Download and crop the OSM extract used for local testing, via crop-osm.sh.
#
# Usage:
#   scripts/get-osm-data.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# Hardcoded urls and coords for testing

./scripts/crop-osm.sh "https://download.geofabrik.de/europe/estonia-latest.osm.pbf" "24.350442,59.269078,25.341958,59.668126" "local-test/input/osm/tallinn-cropped-$(date +%Y-%m-%d).osm.pbf"
./scripts/crop-osm.sh "https://download.geofabrik.de/europe/finland-latest.osm.pbf" "24.608621,60.125985,25.271921,60.327156" "local-test/input/osm/helsinki-cropped-$(date +%Y-%m-%d).osm.pbf"
./scripts/crop-osm.sh "https://download.geofabrik.de/europe/sweden-latest.osm.pbf" "17.679989,59.197248,18.465511,59.498305" "local-test/input/osm/stockholm-cropped-$(date +%Y-%m-%d).osm.pbf"
./scripts/crop-osm.sh "https://download.geofabrik.de/europe/germany/schleswig-holstein-latest.osm.pbf" "10.110924,53.652606,10.945885,54.02293" "local-test/input/osm/lubeck-travemunde-cropped-$(date +%Y-%m-%d).osm.pbf"
curl -L "https://download.geofabrik.de/europe/germany/hamburg-latest.osm.pbf" \
 -o local-test/input/osm/hamburg-full-$(date +%Y-%m-%d).osm.pbf
