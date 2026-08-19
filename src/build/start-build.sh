#!/usr/bin/env sh
set -eu

INPUT_OSM_DIR="${INPUT_OSM_DIR:-/mnt/input/osm}"
INPUT_TRANSIT_DIR="${INPUT_TRANSIT_DIR:-/mnt/input/transit}"
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
# Validate input directories
# --------------------------------------------------

if [ ! -d "$INPUT_OSM_DIR" ]; then
  echo "ERROR: OSM directory does not exist: $INPUT_OSM_DIR"
  exit 1
fi

if [ ! -d "$INPUT_TRANSIT_DIR" ]; then
  echo "ERROR: Transit directory does not exist: $INPUT_TRANSIT_DIR"
  exit 1
fi

if [ ! -f "$OTP_HOME/build-config.json" ]; then
  echo "ERROR: build-config.json does not exist: $OTP_HOME/build-config.json"
  exit 1
fi

# --------------------------------------------------
# Load OSM
# --------------------------------------------------

echo ""
echo "========================================"
echo "Loading OSM data"
echo "========================================"

OSM_COUNT=0

for INPUT_PATH in \
  "$INPUT_OSM_DIR"/*.pbf \
  "$INPUT_OSM_DIR"/*.osm \
  "$INPUT_OSM_DIR"/*.osm.xml
do
  # Shell glob remains literal when nothing matches.
  [ -f "$INPUT_PATH" ] || continue

  BASENAME="$(basename "$INPUT_PATH")"

  cp "$INPUT_PATH" "$OTP_HOME/data/osm/$BASENAME"

  OSM_COUNT=$((OSM_COUNT + 1))

  echo "Loaded OSM: $INPUT_PATH"
done

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

for INPUT_PATH in "$INPUT_TRANSIT_DIR"/*.zip
do
  [ -f "$INPUT_PATH" ] || continue

  BASENAME="$(basename "$INPUT_PATH")"
  TARGET="$TRANSIT_DIR/$BASENAME"

  LOWER="$(printf '%s' "$BASENAME" | tr '[:upper:]' '[:lower:]')"

  # ------------------------------------------------
  # Determine feed type
  #
  # Contains "gtfs" -> GTFS
  # Everything else -> NeTEx
  # ------------------------------------------------

  case "$LOWER" in
    *gtfs*.zip)
      TYPE="gtfs"
      GTFS_COUNT=$((GTFS_COUNT + 1))
      ;;
    *)
      TYPE="netex"
      NETEX_COUNT=$((NETEX_COUNT + 1))
      ;;
  esac

  # ------------------------------------------------
  # Copy and, for GTFS, deduplicate trip_id
  # ------------------------------------------------

  if [ "$TYPE" = "gtfs" ]; then

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

  else

    # NeTEx is copied unchanged.
    cp "$INPUT_PATH" "$TARGET"

    echo "Loaded NeTEx unchanged: $INPUT_PATH"

  fi

  # ------------------------------------------------
  # Generate feed ID from filename
  # ------------------------------------------------

  FEED_ID="$(printf '%s' "$BASENAME" \
    | sed 's/\.[^.]*$//' \
    | tr '[:lower:]' '[:upper:]' \
    | sed 's/[^A-Z0-9_-]/_/g')"

  # ------------------------------------------------
  # Add JSON separator
  # ------------------------------------------------

  if [ "$FIRST" = false ]; then
    printf ',\n' >> "$TRANSIT_CONFIG"
  fi

  # ------------------------------------------------
  # Add transit feed
  # ------------------------------------------------

  jq -n \
    --arg type "$TYPE" \
    --arg feedId "$FEED_ID" \
    --arg source "file://$TARGET" \
    '{
      type: $type,
      feedId: $feedId,
      source: $source
    }' >> "$TRANSIT_CONFIG"

  FIRST=false
  TRANSIT_COUNT=$((TRANSIT_COUNT + 1))

  echo "Configured $TYPE feed:"
  echo "  feedId: $FEED_ID"
  echo "  source: file://$TARGET"

done

printf '\n]\n' >> "$TRANSIT_CONFIG"

# --------------------------------------------------
# Validate transit data
# --------------------------------------------------

if [ "$TRANSIT_COUNT" -eq 0 ]; then
  echo ""
  echo "ERROR: No transit ZIP files found in $INPUT_TRANSIT_DIR"
  exit 1
fi

echo ""
echo "GTFS feeds:  $GTFS_COUNT"
echo "NeTEx feeds: $NETEX_COUNT"
echo "Total feeds: $TRANSIT_COUNT"

# --------------------------------------------------
# Replace transitFeeds in build-config.json
# --------------------------------------------------

echo ""
echo "========================================"
echo "Generating OTP transitFeeds"
echo "========================================"

jq \
  --slurpfile transitFeeds "$TRANSIT_CONFIG" \
  '.transitFeeds = $transitFeeds[0]' \
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
echo "Final OTP transit configuration"
echo "========================================"

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