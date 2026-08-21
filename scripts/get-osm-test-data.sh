#!/usr/bin/env bash
# Download OSM extracts, crop each to a region bbox for local testing, and
# extract ferry data (route=ferry ways/relations, ferry terminals) that would
# otherwise be dropped by cropping, merging it into a single ferry file.
#
# Requires:
#   - curl
#   - osmconvert (apt install osmctools)
#   - osmium (apt install osmium-tool)

set -euo pipefail

cd "$(dirname "$0")/.."

FERRY_OUTPUT_PATH="local-test/input/osm/ferry-$(date +%Y-%m-%d).osm.pbf"
FERRY_TAG_FILTER=(w/route=ferry r/route=ferry n/amenity=ferry_terminal w/amenity=ferry_terminal)

FERRY_FILES=()

# Downloads $1 (url), crops it to bbox $2 (min_lon,min_lat,max_lon,max_lat,
# same format as osmconvert's -b= option), and saves the result to $3.
# Also extracts ferry-related data from the full download (before cropping,
# since a bbox crop would otherwise drop routes that cross open water) into a
# temp file tracked in FERRY_FILES for the later merge step.
handle_osm_file() {
  local url="$1"
  local bbox="$2"
  local output_path="$3"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local download_path="${tmp_dir}/download.pbf"
  local ferry_path="${tmp_dir}/ferry.pbf"

  mkdir -p "$(dirname "${output_path}")"

  echo "==> Downloading ${url}"
  curl -fL --progress-bar -o "${download_path}" "${url}"

  echo "==> Extracting ferry data"
  osmium tags-filter "${download_path}" "${FERRY_TAG_FILTER[@]}" -o "${ferry_path}"
  FERRY_FILES+=("${ferry_path}")

  echo "==> Cropping to bbox ${bbox}"
  osmconvert "${download_path}" \
    -b="${bbox}" \
    --complete-ways \
    -o="${output_path}"

  echo "==> Done. Cropped file: ${output_path}"
}

handle_osm_file "https://download.geofabrik.de/europe/estonia-latest.osm.pbf" "24.350442,59.269078,25.341958,59.668126" "local-test/input/osm/tallinn-cropped-$(date +%Y-%m-%d).osm.pbf"
handle_osm_file "https://download.geofabrik.de/europe/finland-latest.osm.pbf" "24.608621,60.125985,25.271921,60.327156" "local-test/input/osm/helsinki-cropped-$(date +%Y-%m-%d).osm.pbf"
handle_osm_file "https://download.geofabrik.de/europe/sweden-latest.osm.pbf" "17.679989,59.197248,18.465511,59.498305" "local-test/input/osm/stockholm-cropped-$(date +%Y-%m-%d).osm.pbf"
handle_osm_file "https://download.geofabrik.de/europe/germany/schleswig-holstein-latest.osm.pbf" "10.110924,53.652606,10.945885,54.02293" "local-test/input/osm/lubeck-travemunde-cropped-$(date +%Y-%m-%d).osm.pbf"

curl -L "https://download.geofabrik.de/europe/germany/hamburg-latest.osm.pbf" \
 -o local-test/input/osm/hamburg-full-$(date +%Y-%m-%d).osm.pbf

echo "==> Merging ferry data from all regions into ${FERRY_OUTPUT_PATH}"
osmium merge "${FERRY_FILES[@]}" -O -o "${FERRY_OUTPUT_PATH}"

echo "==> Done. Merged ferry file: ${FERRY_OUTPUT_PATH}"
