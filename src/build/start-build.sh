#!/usr/bin/env sh
set -eu

# Placeholder paths: replace with real mounted input/output paths at deploy time.
# INPUT_GTFS_PATH and INPUT_NETEX_PATH are individually optional, but at least
# one of the two must be provided.
INPUT_OSM_PATH="${INPUT_OSM_PATH:-<INPUT_OSM_PATH_PLACEHOLDER>}"
INPUT_GTFS_PATH="${INPUT_GTFS_PATH:-}"
INPUT_NETEX_PATH="${INPUT_NETEX_PATH:-}"
OUTPUT_GRAPH_DIR="${OUTPUT_GRAPH_DIR:-<OUTPUT_GRAPH_DIR_PLACEHOLDER>}"

if [ "$INPUT_OSM_PATH" = "<INPUT_OSM_PATH_PLACEHOLDER>" ] || \
   [ "$OUTPUT_GRAPH_DIR" = "<OUTPUT_GRAPH_DIR_PLACEHOLDER>" ]; then
  echo "Set INPUT_OSM_PATH and OUTPUT_GRAPH_DIR before running."
  exit 1
fi

if [ -z "$INPUT_GTFS_PATH" ] && [ -z "$INPUT_NETEX_PATH" ]; then
  echo "Set at least one of INPUT_GTFS_PATH or INPUT_NETEX_PATH before running."
  exit 1
fi

mkdir -p /var/opentripplanner/data/osm /opt/otp-data/transit "$OUTPUT_GRAPH_DIR"

# Load source data into the locations referenced by build-config.json.
cp "$INPUT_OSM_PATH" /var/opentripplanner/data/osm/estonia.pbf

HAS_GTFS=false
HAS_NETEX=false

if [ -n "$INPUT_GTFS_PATH" ]; then
  cp "$INPUT_GTFS_PATH" /opt/otp-data/transit/napcorexgtfs.zip
  HAS_GTFS=true

  # The upstream GTFS export contains duplicate trip_id rows in trips.txt (the
  # same trip_id reused across different routes), which OTP rejects with a
  # DuplicateEntityException. Deduplicate by keeping the first occurrence of
  # each trip_id before building.
  # TODO: figure out what to do long term.
  GTFS_CLEAN_DIR="$(mktemp -d)"
  unzip -q /opt/otp-data/transit/napcorexgtfs.zip -d "$GTFS_CLEAN_DIR"
  if [ -f "$GTFS_CLEAN_DIR/trips.txt" ]; then
    BEFORE_LINES=$(wc -l < "$GTFS_CLEAN_DIR/trips.txt")
    awk -F',' '
      NR==1 { for (i=1; i<=NF; i++) if ($i=="trip_id") idx=i; print; next }
      { if (!($idx in seen)) { seen[$idx]=1; print } }
    ' "$GTFS_CLEAN_DIR/trips.txt" > "$GTFS_CLEAN_DIR/trips.txt.dedup"
    mv "$GTFS_CLEAN_DIR/trips.txt.dedup" "$GTFS_CLEAN_DIR/trips.txt"
    AFTER_LINES=$(wc -l < "$GTFS_CLEAN_DIR/trips.txt")
    echo "Deduplicated trips.txt: removed $((BEFORE_LINES - AFTER_LINES)) duplicate trip_id row(s)."

    rm -f /opt/otp-data/transit/napcorexgtfs.zip
    (cd "$GTFS_CLEAN_DIR" && zip -q -r -X /opt/otp-data/transit/napcorexgtfs.zip .)
  fi
  rm -rf "$GTFS_CLEAN_DIR"
fi

if [ -n "$INPUT_NETEX_PATH" ]; then
  cp "$INPUT_NETEX_PATH" /opt/otp-data/transit/Napcorex.zip
  HAS_NETEX=true
fi

# Trim build-config.json's transitFeeds to only the feed types with data supplied,
# so OTP doesn't try to read a feed file that was never copied in.
# TODO: temporary workaround for loading only partial data. Ideally, the build-config.json would be generated dynamically at deploy time instead of being static (maybe)
jq --argjson hasGtfs "$HAS_GTFS" --argjson hasNetex "$HAS_NETEX" \
  '.transitFeeds |= map(select((.type == "gtfs" and $hasGtfs) or (.type == "netex" and $hasNetex)))' \
  /var/opentripplanner/build-config.json > /var/opentripplanner/build-config.json.tmp
mv /var/opentripplanner/build-config.json.tmp /var/opentripplanner/build-config.json

# Build and persist the OTP graph.
# NOTE: the base image's real entrypoint is /docker-entrypoint.sh, which always
# runs against the hardcoded /var/opentripplanner/ directory and appends any
# flags passed to it (see application/src/main/jib/docker-entrypoint.sh in the
# OpenTripPlanner source repo).
/docker-entrypoint.sh --build --save

if [ ! -f /var/opentripplanner/graph.obj ]; then
  echo "Graph build failed: /var/opentripplanner/graph.obj was not created."
  exit 1
fi

cp /var/opentripplanner/graph.obj "$OUTPUT_GRAPH_DIR/graph.obj"
echo "Graph build completed: $OUTPUT_GRAPH_DIR/graph.obj"
