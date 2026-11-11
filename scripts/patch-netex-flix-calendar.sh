#!/usr/bin/env bash
# TEMPORARY TEST DATA: make every Flix ServiceJourney run every day.
# Usage: scripts/patch-netex-flix-calendar.sh [input.zip] [output.zip]
# Defaults: napcore_netex_de_flix.zip -> napcore_netex_de_flix-patched.zip
# Paths are relative to the workspace root.
# FROM_DATE / TO_DATE may override the inclusive date window (YYYY-MM-DD).
# Otherwise use today through its anniversary next year (Feb 29 -> Feb 28).
# Repairs _stops.xml and stop assignments before adding daily calendars.
# Timetable XML files remain unchanged.
# This does not change OTP's transitServiceStart / transitServiceEnd settings;
# those must include the desired dates when building a graph.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  exec python3 scripts/python/patch_netex_flix_calendar.py "$@"
fi
if (( $# > 2 )); then
  echo "Usage: $0 [input.zip] [output.zip]" >&2
  exit 1
fi

INPUT="${1:-local-test/input/netex/napcore_netex_de_flix.zip}"
OUTPUT="${2:-local-test/input/netex/napcore_netex_de_flix-patched.zip}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

python3 scripts/python/prepare_napcore_netex.py "$INPUT" "$tmp_dir/stops-fixed.zip"
python3 scripts/python/patch_netex_flix_calendar.py "$tmp_dir/stops-fixed.zip" "$OUTPUT"
