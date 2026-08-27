#!/usr/bin/env sh
set -eu

INPUT_OSM_DIR="${INPUT_OSM_DIR:-/mnt/input/osm}"
INPUT_GTFS_DIR="${INPUT_GTFS_DIR:-/mnt/input/gtfs}"
INPUT_NETEX_DIR="${INPUT_NETEX_DIR:-/mnt/input/netex}"
OUTPUT_GRAPH_DIR="${OUTPUT_GRAPH_DIR:-/mnt/output}"

OTP_HOME="/var/opentripplanner"
TRANSIT_DIR="/opt/otp-data/transit"

# --------------------------------------------------
# Prepare directories
# --------------------------------------------------

mkdir -p \
  "$OTP_HOME/data/osm" \
  "$TRANSIT_DIR" \
  "$OUTPUT_GRAPH_DIR"

# --------------------------------------------------
# Validate input
# --------------------------------------------------

# GTFS/NeTEx dirs are each optional (see transit feed count check below) -
# only OSM is always required.
if [ ! -d "$INPUT_OSM_DIR" ]; then
  echo "ERROR: OSM directory does not exist: $INPUT_OSM_DIR"
  exit 1
fi

if [ ! -f "$OTP_HOME/build-config.json" ]; then
  echo "ERROR: build-config.json does not exist: $OTP_HOME/build-config.json"
  exit 1
fi

# --------------------------------------------------
# Load OSM and generate osm sources
# --------------------------------------------------

echo ""
echo "========================================"
echo "Loading OSM data"
echo "========================================"

OSM_CONFIG="/tmp/osm-sources.json"
OSM_COUNT=0
OSM_FIRST=true

printf '[\n' > "$OSM_CONFIG"

for INPUT_PATH in \
  "$INPUT_OSM_DIR"/*.pbf \
  "$INPUT_OSM_DIR"/*.osm \
  "$INPUT_OSM_DIR"/*.osm.xml
do
  # Shell glob remains literal when nothing matches.
  [ -f "$INPUT_PATH" ] || continue

  BASENAME="$(basename "$INPUT_PATH")"
  TARGET="$OTP_HOME/data/osm/$BASENAME"

  cp "$INPUT_PATH" "$TARGET"

  if [ "$OSM_FIRST" = false ]; then
    printf ',\n' >> "$OSM_CONFIG"
  fi

  jq -n --arg source "file://$TARGET" '{ source: $source }' >> "$OSM_CONFIG"

  OSM_FIRST=false
  OSM_COUNT=$((OSM_COUNT + 1))

  echo "Loaded OSM: $INPUT_PATH"
done

printf '\n]\n' >> "$OSM_CONFIG"

if [ "$OSM_COUNT" -eq 0 ]; then
  echo "ERROR: No OSM files found in $INPUT_OSM_DIR"
  exit 1
fi

echo ""
echo "OSM files loaded: $OSM_COUNT"

echo ""
echo "OSM files in OTP:"
find "$OTP_HOME/data/osm" -maxdepth 1 -type f -print


# --------------------------------------------------
# Load transit and generate transitFeeds
# --------------------------------------------------

TRANSIT_CONFIG="/tmp/transit-feeds.json"

GTFS_COUNT=0
NETEX_COUNT=0
TRANSIT_COUNT=0
FIRST=true

printf '[\n' > "$TRANSIT_CONFIG"

# ------------------------------------------------
# Appends one processed feed to TRANSIT_CONFIG
# ------------------------------------------------

add_transit_feed() {
  FEED_TYPE="$1"
  FEED_TARGET="$2"
  FEED_BASENAME="$(basename "$FEED_TARGET")"

  FEED_ID="$(printf '%s' "$FEED_BASENAME" \
    | sed 's/\.[^.]*$//' \
    | tr '[:lower:]' '[:upper:]' \
    | sed 's/[^A-Z0-9_-]/_/g')"

  if [ "$FIRST" = false ]; then
    printf ',\n' >> "$TRANSIT_CONFIG"
  fi

  jq -n \
    --arg type "$FEED_TYPE" \
    --arg feedId "$FEED_ID" \
    --arg source "file://$FEED_TARGET" \
    '{
      type: $type,
      feedId: $feedId,
      source: $source
    }' >> "$TRANSIT_CONFIG"

  FIRST=false
  TRANSIT_COUNT=$((TRANSIT_COUNT + 1))

  echo "Configured $FEED_TYPE feed:"
  echo "  feedId: $FEED_ID"
  echo "  source: file://$FEED_TARGET"
}

# ------------------------------------------------
# GTFS: deduplicate trip_id, then load
# ------------------------------------------------

for INPUT_PATH in "$INPUT_GTFS_DIR"/*.zip
do
  [ -f "$INPUT_PATH" ] || continue

  BASENAME="$(basename "$INPUT_PATH")"
  TARGET="$TRANSIT_DIR/$BASENAME"

  GTFS_CLEAN_DIR="$(mktemp -d)"

  echo "Processing GTFS: $INPUT_PATH"

  unzip -q "$INPUT_PATH" -d "$GTFS_CLEAN_DIR"

  if [ ! -f "$GTFS_CLEAN_DIR/trips.txt" ]; then
    echo "ERROR: GTFS feed does not contain trips.txt: $INPUT_PATH"
    rm -rf "$GTFS_CLEAN_DIR"
    exit 1
  fi

  BEFORE_LINES=$(wc -l < "$GTFS_CLEAN_DIR/trips.txt")

  awk -F',' '
    NR==1 {
      for (i=1; i<=NF; i++) {
        if ($i=="trip_id") {
          idx=i
        }
      }

      if (!idx) {
        print "ERROR: trip_id column not found" > "/dev/stderr"
        exit 1
      }

      print
      next
    }

    {
      if (!($idx in seen)) {
        seen[$idx]=1
        print
      }
    }
  ' "$GTFS_CLEAN_DIR/trips.txt" \
    > "$GTFS_CLEAN_DIR/trips.txt.dedup"

  mv \
    "$GTFS_CLEAN_DIR/trips.txt.dedup" \
    "$GTFS_CLEAN_DIR/trips.txt"

  AFTER_LINES=$(wc -l < "$GTFS_CLEAN_DIR/trips.txt")

  REMOVED=$((BEFORE_LINES - AFTER_LINES))

  echo "GTFS deduplication:"
  echo "  Original rows: $BEFORE_LINES"
  echo "  Final rows:    $AFTER_LINES"
  echo "  Removed:       $REMOVED duplicate trip_id row(s)"

  # Replace the original ZIP with the cleaned ZIP.
  rm -f "$TARGET"

  (
    cd "$GTFS_CLEAN_DIR"
    zip -q -r -X "$TARGET" .
  )

  rm -rf "$GTFS_CLEAN_DIR"

  GTFS_COUNT=$((GTFS_COUNT + 1))

  add_transit_feed "gtfs" "$TARGET"
done

# ------------------------------------------------
# NeTEx: load unchanged
# ------------------------------------------------

for INPUT_PATH in "$INPUT_NETEX_DIR"/*.zip
do
  [ -f "$INPUT_PATH" ] || continue

  BASENAME="$(basename "$INPUT_PATH")"
  TARGET="$TRANSIT_DIR/$BASENAME"

  cp "$INPUT_PATH" "$TARGET"

  echo "Loaded NeTEx unchanged: $INPUT_PATH"

  NETEX_COUNT=$((NETEX_COUNT + 1))

  add_transit_feed "netex" "$TARGET"
done

printf '\n]\n' >> "$TRANSIT_CONFIG"

# --------------------------------------------------
# Validate transit data
# --------------------------------------------------

if [ "$TRANSIT_COUNT" -eq 0 ]; then
  echo ""
  echo "ERROR: No transit ZIP files found in $INPUT_GTFS_DIR or $INPUT_NETEX_DIR"
  exit 1
fi

echo ""
echo "GTFS feeds:  $GTFS_COUNT"
echo "NeTEx feeds: $NETEX_COUNT"
echo "Total feeds: $TRANSIT_COUNT"

# --------------------------------------------------
# Replace osm/transitFeeds in build-config.json
# --------------------------------------------------

echo ""
echo "========================================"
echo "Generating OTP osm and transitFeeds"
echo "========================================"

jq \
  --slurpfile osm "$OSM_CONFIG" \
  --slurpfile transitFeeds "$TRANSIT_CONFIG" \
  '.osm = $osm[0] | .transitFeeds = $transitFeeds[0]' \
  "$OTP_HOME/build-config.json" \
  > "$OTP_HOME/build-config.json.tmp"

mv \
  "$OTP_HOME/build-config.json.tmp" \
  "$OTP_HOME/build-config.json"

# --------------------------------------------------
# Display final configuration
# --------------------------------------------------

echo ""
echo "========================================"
echo "Final OTP configuration"
echo "========================================"

jq '.osm' "$OTP_HOME/build-config.json"
jq '.transitFeeds' "$OTP_HOME/build-config.json"

echo ""
echo "========================================"
echo "Transit files in OTP"
echo "========================================"

find "$TRANSIT_DIR" -maxdepth 1 -type f -print

# --------------------------------------------------
# Build OTP graph
# --------------------------------------------------

echo ""
echo "========================================"
echo "Building OTP graph"
echo "========================================"

/docker-entrypoint.sh --build --save

# --------------------------------------------------
# Validate graph
# --------------------------------------------------

if [ ! -f "$OTP_HOME/graph.obj" ]; then
  echo ""
  echo "ERROR: OTP graph build failed."
  echo "Expected graph:"
  echo "  $OTP_HOME/graph.obj"
  exit 1
fi

# --------------------------------------------------
# Copy graph to output
# --------------------------------------------------

cp \
  "$OTP_HOME/graph.obj" \
  "$OUTPUT_GRAPH_DIR/graph.obj"

echo ""
echo "========================================"
echo "Build completed successfully"
echo "========================================"

echo "Graph:"
echo "  $OUTPUT_GRAPH_DIR/graph.obj"
