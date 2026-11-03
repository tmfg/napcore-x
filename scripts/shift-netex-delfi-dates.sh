#!/usr/bin/env bash

# Repairs german NeTEx-DELFI ZIP feed by shifting transitservice dates from 2025 to 2026.

# Usage:
#   scripts/shift-netex-delfi-dates.sh [input.zip]
#
# If no input ZIP file is specified, the default is local-test/input/netex/netex-delfi.zip.


set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ARCHIVE="${1:-${REPO_ROOT}/local-test/input/netex/netex-delfi.zip}"

exec python3 "${SCRIPT_DIR}/python/shift-netex-delfi-dates.py" "$ARCHIVE"
