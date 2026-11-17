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
#   - python3 (JSON parsing; no third-party packages)

set -euo pipefail

cd "$(dirname "$0")/.."

for tool in curl osmconvert osmium python3; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Missing required command: ${tool}" >&2
    exit 1
  fi
done

FERRY_TAG_FILTER=(w/route=ferry r/route=ferry n/amenity=ferry_terminal w/amenity=ferry_terminal)
RAILWAY_TAG_FILTER=(w/railway r/railway)

# Downloads $1 (url), reads one or more bbox regions from JSON config file $2,
# crops each to its region bbox for local testing, and merges ferry data
# extracted from the full download (before cropping, since a bbox crop would
# otherwise drop routes that cross open water). Optional arguments after $2
# add osmium tag filters, e.g. for Finnish railways.
handle_osm_file() (
  local url="$1"
  local config_file="$2"
  local tag_filters=("${FERRY_TAG_FILTER[@]}" "${@:3}")

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf -- "${tmp_dir}"' EXIT
  local download_path="${tmp_dir}/download.pbf"
  local connection_path="${tmp_dir}/connections.pbf"
  local cropped_path="${tmp_dir}/cropped.pbf"
  local extracts_path="${tmp_dir}/extracts"

  # Expand only the supported date placeholder, never shell commands from JSON.
  python3 scripts/python/parse_osm_extracts.py "${config_file}" > "${extracts_path}"

  echo "==> Downloading ${url}"
  curl -fL --progress-bar -o "${download_path}" "${url}"

  echo "==> Extracting connection data (${tag_filters[*]})"
  osmium tags-filter "${download_path}" "${tag_filters[@]}" -o "${connection_path}"

  echo "==> Processing extracts from ${config_file}"
  local output bbox
  while IFS= read -r -d '' output && IFS= read -r -d '' bbox; do
    mkdir -p -- "$(dirname -- "${output}")"

    echo "  ==> Cropping to bbox ${bbox} -> ${output}"

    osmconvert "${download_path}" \
      -b="${bbox}" \
      --complete-ways \
      -o="${cropped_path}"

    echo "  ==> Merging connection data into cropped region"
    osmium merge "${cropped_path}" "${connection_path}" -O -o "${output}"

    echo "  ==> Done. Cropped file (with connection data): ${output}"
    
    rm -f "${cropped_path}"
  done < "${extracts_path}"
)

handle_osm_file "https://download.geofabrik.de/europe/germany-latest.osm.pbf" "scripts/config/german-bbox.json"
handle_osm_file "https://download.geofabrik.de/europe/finland-latest.osm.pbf" "scripts/config/finland-bbox.json" "${RAILWAY_TAG_FILTER[@]}"
handle_osm_file "https://download.geofabrik.de/europe/austria-latest.osm.pbf" "scripts/config/wien-bbox.json"
handle_osm_file "https://download.geofabrik.de/europe/sweden-latest.osm.pbf" "scripts/config/stockholm-bbox.json"
handle_osm_file "https://download.geofabrik.de/europe/estonia-latest.osm.pbf" "scripts/config/tallinn-bbox.json"

curl -L "https://download.geofabrik.de/europe/germany/hamburg-latest.osm.pbf" \
 -o local-test/input/osm/hamburg-full-$(date +%Y-%m-%d).osm.pbf


echo "==> Done."
