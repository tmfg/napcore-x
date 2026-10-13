#!/usr/bin/env bash
# Requires Bash, Info-ZIP zip/unzip and Python 3.
#
# Repairs a Stockholm NeTEx ZIP feed by restoring missing platform quays,
# fixing quay references, and writing a patched archive.
# Restored platforms use their station’s centroid coordinates.
# Usage:
#   scripts/repair-netex-stockholm.sh [input.zip] [output.zip]
#
# args default to local-test/input/netex/Napcorex.zip and local-test/input/netex/Napcorex-patched-stockholm.zip.
# The input archive is deleted after the patched output is successfully written.

set -euo pipefail

usage() {
    printf 'Usage: %s [input.zip [output.zip]]\n' "${0##*/}"
    printf 'Defaults: local-test/input/netex/Napcorex.zip local-test/input/netex/Napcorex-patched-stockholm.zip\n'
    printf 'Restored platforms use parent-station coordinates, not surveyed positions.\n'
}

fail() {
    printf 'Feed repair failed: %s\n' "$*" >&2
    exit 1
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    usage
    exit 0
fi
[[ $# -le 2 ]] || { usage >&2; exit 2; }
for tool in unzip zip python3 realpath mktemp cp mv rm rmdir cat sort uniq grep; do
    command -v "$tool" >/dev/null || fail "Required command is missing: $tool"
done

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
default_source="$script_directory/local-test/input/netex/Napcorex.zip"
default_destination="$script_directory/local-test/input/netex/Napcorex-patched-stockholm.zip"
source_file=$(realpath -e -- "${1:-$default_source}") || fail 'Source archive does not exist.'
destination=$(realpath -m -- "${2:-$default_destination}") || fail 'Cannot resolve output path.'
[[ -f $source_file ]] || fail 'Source must be a regular ZIP file.'
[[ $source_file != "$destination" && ! $source_file -ef $destination ]] ||
    fail 'Output must differ from the original feed.'
[[ ! -d $destination ]] || fail 'Output is a directory.'
output_directory=${destination%/*}
[[ -d $output_directory ]] || fail 'Output directory does not exist.'

work_directory=$(mktemp -d "$output_directory/.repair-netex.XXXXXXXX")
cleanup() {
    rm -f -- "$work_directory/_stops.xml" "$work_directory/_shared_data.xml" \
        "$work_directory/archive.zip" "$work_directory/entries" \
        "$work_directory/duplicates" "$work_directory/stats"
    rmdir -- "$work_directory"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'printf "Feed repair failed at line %s.\n" "$LINENO" >&2' ERR

unzip -Z1 "$source_file" > "$work_directory/entries"
sort "$work_directory/entries" | uniq -d > "$work_directory/duplicates"
[[ ! -s $work_directory/duplicates ]] || fail 'Duplicate ZIP entry names.'
for entry in _stops.xml _shared_data.xml; do
    grep -Fxq -- "$entry" "$work_directory/entries" || fail "Missing ZIP entry: $entry"
    unzip -p "$source_file" "$entry" > "$work_directory/$entry"
done

# Use an XML parser rather than line-based substitutions: NeTEx elements can
# span lines, use namespace prefixes and contain escaped text.
python3 "$script_directory/scripts/python/repair_netex_stockholm.py" "$work_directory"

# Updating a copy preserves all other entries and the original archive comment.
cp -- "$source_file" "$work_directory/archive.zip"
(
    cd -- "$work_directory"
    zip -q archive.zip _stops.xml _shared_data.xml
)
unzip -tq "$work_directory/archive.zip" >/dev/null
mv -f -- "$work_directory/archive.zip" "$destination"
rm -- "$source_file"
printf 'Repaired feed: %s\n' "$destination"
cat -- "$work_directory/stats"
