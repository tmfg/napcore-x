#!/usr/bin/env bash
# TEMPORARY FIX: the NeTEx feed's OTH-codespace DayTypes have zero DayTypeAssignment data, so those lines never have any valid operating date and can't be routed.
#
# This patches _shared_data.xml inside the NeTEx zip so every OTH DayType
# gets a "runs every day of week" property plus a DayTypeAssignment tied to
# a single shared OperatingPeriod.
# Note: this script is quick and dirty, meant for quick testing
# Usage:
#   scripts/patch-netex-ferry-calendar.sh [input.zip] [output.zip]
#
# Both args default to local-test/input/netex/Napcorex.zip (in-place patch).
# Override the date window with FROM_DATE / TO_DATE env vars.
set -euo pipefail

cd "$(dirname "$0")/.."

INPUT="${1:-local-test/input/netex/Napcorex.zip}"
OUTPUT="${2:-$INPUT}"
FROM_DATE="${FROM_DATE:-2026-04-07}"
TO_DATE="${TO_DATE:-2026-12-31}"

REPO_ROOT="$(pwd)"
case "$OUTPUT" in
  /*) OUTPUT_PATH="$OUTPUT" ;;
  *) OUTPUT_PATH="$REPO_ROOT/$OUTPUT" ;;
esac

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "==> Extracting ${INPUT}"
unzip -q "$INPUT" -d "$tmp_dir" _shared_data.xml

python3 scripts/python/patch_netex_ferry_calendar.py "$tmp_dir/_shared_data.xml" "$FROM_DATE" "$TO_DATE"

echo "==> Repacking ${OUTPUT_PATH}"
# Copy the original zip and update just the one changed member in place,
# rather than re-zipping all ~1300 files from scratch.
cp "$INPUT" "$OUTPUT_PATH.tmp"
( cd "$tmp_dir" && zip -q "$OUTPUT_PATH.tmp" _shared_data.xml )
mv "$OUTPUT_PATH.tmp" "$OUTPUT_PATH"

echo "==> Done. Patched NeTEx ferry calendar written to ${OUTPUT_PATH}"
