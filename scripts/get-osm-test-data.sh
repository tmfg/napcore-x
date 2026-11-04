#!/usr/bin/env bash
# Download OSM extracts, crop each to a region bbox for local testing, and
# bake ferry data (route=ferry ways/relations, ferry terminals) that would
# otherwise be dropped by cropping into each region's output file.
# Finnish regions also retain railway ways/relations and their referenced
# objects from the full Finland extract, preserving connections between cities.
#
# Requires:
#   - curl
#   - osmconvert (apt install osmctools)
#   - osmium (apt install osmium-tool)

set -euo pipefail

cd "$(dirname "$0")/.."

FERRY_TAG_FILTER=(w/route=ferry r/route=ferry n/amenity=ferry_terminal w/amenity=ferry_terminal)
RAILWAY_TAG_FILTER=(w/railway r/railway)

# Downloads $1 (url), crops it to bbox $2 (min_lon,min_lat,max_lon,max_lat,
# same format as osmconvert's -b= option), merges in ferry data extracted
# from the full download (before cropping, since a bbox crop would otherwise
# drop routes that cross open water), and saves the result to $3. Optional
# arguments after $3 add osmium tag filters, e.g. for Finnish railways.
handle_osm_file() {
  local url="$1"
  local bbox="$2"
  local output_path="$3"
  local tag_filters=("${FERRY_TAG_FILTER[@]}" "${@:4}")

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local download_path="${tmp_dir}/download.pbf"
  local connection_path="${tmp_dir}/connections.pbf"
  local cropped_path="${tmp_dir}/cropped.pbf"

  mkdir -p "$(dirname "${output_path}")"

  echo "==> Downloading ${url}"
  curl -fL --progress-bar -o "${download_path}" "${url}"

  echo "==> Extracting connection data (${tag_filters[*]})"
  osmium tags-filter "${download_path}" "${tag_filters[@]}" -o "${connection_path}"

  echo "==> Cropping to bbox ${bbox}"
  osmconvert "${download_path}" \
    -b="${bbox}" \
    --complete-ways \
    -o="${cropped_path}"

  echo "==> Merging connection data into cropped region"
  osmium merge "${cropped_path}" "${connection_path}" -O -o "${output_path}"

  echo "==> Done. Cropped file (with connection data): ${output_path}"
}

handle_osm_file "https://download.geofabrik.de/europe/estonia-latest.osm.pbf" "24.350442,59.269078,25.341958,59.668126" "local-test/input/osm/tallinn-cropped-$(date +%Y-%m-%d).osm.pbf"
handle_osm_file "https://download.geofabrik.de/europe/finland-latest.osm.pbf" "24.4429,60.1126,25.2613,60.3828" "local-test/input/osm/helsinki-cropped-$(date +%Y-%m-%d).osm.pbf" "${RAILWAY_TAG_FILTER[@]}"
handle_osm_file "https://download.geofabrik.de/europe/sweden-latest.osm.pbf" "17.679989,59.197248,18.465511,59.498305" "local-test/input/osm/stockholm-cropped-$(date +%Y-%m-%d).osm.pbf"
handle_osm_file "https://download.geofabrik.de/europe/germany/schleswig-holstein-latest.osm.pbf" "10.110924,53.652606,10.945885,54.02293" "local-test/input/osm/lubeck-travemunde-cropped-$(date +%Y-%m-%d).osm.pbf"
handle_osm_file "https://download.geofabrik.de/europe/austria-latest.osm.pbf" "16.0321,48.0444,16.727,48.4085" "local-test/input/osm/wien-cropped-$(date +%Y-%m-%d).osm.pbf"
handle_osm_file "https://download.geofabrik.de/europe/finland-latest.osm.pbf" "23.761145,61.490213,23.785247,61.50368" "local-test/input/osm/TRE-cropped-$(date +%Y-%m-%d).osm.pbf" "${RAILWAY_TAG_FILTER[@]}"
handle_osm_file "https://download.geofabrik.de/europe/finland-latest.osm.pbf" "22.211108,60.421149,22.315787,60.47171" "local-test/input/osm/TKU-cropped-$(date +%Y-%m-%d).osm.pbf" "${RAILWAY_TAG_FILTER[@]}"
handle_osm_file "https://download.geofabrik.de/europe/finland-latest.osm.pbf" "25.452547,64.990904,25.502809,65.023629" "local-test/input/osm/Oulu-cropped-$(date +%Y-%m-%d).osm.pbf" "${RAILWAY_TAG_FILTER[@]}"

curl -L "https://download.geofabrik.de/europe/germany/hamburg-latest.osm.pbf" \
 -o local-test/input/osm/hamburg-full-$(date +%Y-%m-%d).osm.pbf

echo "==> Done."
