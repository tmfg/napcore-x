#!/usr/bin/env bash
# Download an OSM PBF extract and crop it to a bounding box for local testing.
#
# Requires:
#   - curl
#   - osmconvert (apt install osmctools)
#
# Usage:
#   scripts/crop-osm.sh <url> <bbox> <output_path>
#
#   <bbox> is passed straight to osmconvert's -b= option, e.g. -0.5,51,0.5,52
#   (min_lon,min_lat,max_lon,max_lat).

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <url> <min_lon,min_lat,max_lon,max_lat> <output_path>" >&2
  exit 1
fi

OSM_URL="$1"
BBOX="$2"
OUTPUT_PATH="$3"

DOWNLOAD_PATH="$(mktemp -d)/download.pbf"

mkdir -p "$(dirname "${OUTPUT_PATH}")"

echo "==> Downloading ${OSM_URL}"
curl -fL --progress-bar -o "${DOWNLOAD_PATH}" "${OSM_URL}"

echo "==> Cropping to bbox ${BBOX}"
osmconvert "${DOWNLOAD_PATH}" \
  -b="${BBOX}" \
  --complete-ways \
  -o="${OUTPUT_PATH}"

echo "==> Done. Cropped file: ${OUTPUT_PATH}"
