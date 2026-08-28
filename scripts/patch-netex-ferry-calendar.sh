#!/usr/bin/env bash
# TEMPORARY FIX: the NeTEx feed's OTH-codespace DayTypes (used by the real
# ferry lines, e.g. Helsinki-Tallinn) have zero DayTypeAssignment data, so
# those lines never have any valid operating date and can't be routed.
#
# This patches _shared_data.xml inside the NeTEx zip so every OTH DayType
# gets a "runs every day of week" property plus a DayTypeAssignment tied to
# a single shared OperatingPeriod, covering the same date window the
# FlixBus GTFS test feed is valid for (2026-04-07 to 2026-06-08). Remove
# this step once a NeTEx export with real ferry calendars is available.
#
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

python3 - "$tmp_dir/_shared_data.xml" "$FROM_DATE" "$TO_DATE" << 'EOF'
import re
import sys

path, from_date, to_date = sys.argv[1], sys.argv[2], sys.argv[3]
content = open(path, encoding="utf-8").read()

daytype_ids = sorted(set(re.findall(r'<DayType version="1" id="(OTH:DayType:[^"]+)"/>', content)))
if not daytype_ids:
    print("No un-patched OTH DayType declarations found - nothing to do.")
    sys.exit(0)

period_id = "OTH:OperatingPeriod:ferry-patch"


def add_props(m):
    day_id = m.group(1)
    return (
        f'<DayType version="1" id="{day_id}">'
        f'<properties><PropertyOfDay><DaysOfWeek>Everyday</DaysOfWeek></PropertyOfDay></properties>'
        f'</DayType>'
    )


# Every OTH DayType needs an "Everyday" property, since OperatingPeriodRef
# assignments only yield dates matching the DayType's own days-of-week.
content, n_daytypes = re.subn(
    r'<DayType version="1" id="(OTH:DayType:[^"]+)"/>', add_props, content
)

operating_period = (
    f'<OperatingPeriod version="1" id="{period_id}">'
    f'<FromDate>{from_date}T00:00:00</FromDate><ToDate>{to_date}T00:00:00</ToDate>'
    f'</OperatingPeriod>'
)
content = content.replace("<operatingPeriods>", "<operatingPeriods>" + operating_period, 1)

assignments = "".join(
    f'<DayTypeAssignment order="1" version="1" id="OTH:DayTypeAssignment:ferry-patch-{i}">'
    f'<OperatingPeriodRef ref="{period_id}" version="1"/>'
    f'<DayTypeRef ref="{day_id}" version="1"/>'
    f'</DayTypeAssignment>'
    for i, day_id in enumerate(daytype_ids)
)
content = content.replace("<dayTypeAssignments>", "<dayTypeAssignments>" + assignments, 1)

open(path, "w", encoding="utf-8").write(content)
print(f"Patched {n_daytypes} OTH DayType(s) with an Everyday property.")
print(f"Added {len(daytype_ids)} DayTypeAssignment(s) for {from_date}..{to_date}.")
EOF

echo "==> Repacking ${OUTPUT_PATH}"
# Copy the original zip and update just the one changed member in place,
# rather than re-zipping all ~1300 files from scratch.
cp "$INPUT" "$OUTPUT_PATH.tmp"
( cd "$tmp_dir" && zip -q "$OUTPUT_PATH.tmp" _shared_data.xml )
mv "$OUTPUT_PATH.tmp" "$OUTPUT_PATH"

echo "==> Done. Patched NeTEx ferry calendar written to ${OUTPUT_PATH}"
