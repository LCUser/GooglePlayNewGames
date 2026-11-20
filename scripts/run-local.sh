#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_FILE="$ROOT_DIR/playapi-key.local"
BUNDLE_ID="com.local.GooglePlayNewGames"

if [[ $# -ne 2 || ( "$1" != "simulator" && "$1" != "device" ) ]]; then
    printf 'Usage: %s simulator|device <device-identifier>\n' "$0" >&2
    exit 2
fi

if [[ ! -f "$KEY_FILE" ]]; then
    printf 'Missing local API key file: playapi-key.local\n' >&2
    exit 1
fi

exec 3< "$KEY_FILE"
API_KEY=""
if ! IFS= read -r API_KEY <&3 && [[ -z "$API_KEY" ]]; then
    exec 3<&-
    printf 'Local API key file is empty or invalid.\n' >&2
    exit 1
fi
if [[ -z "$API_KEY" ]]; then
    exec 3<&-
    printf 'Local API key file is empty or invalid.\n' >&2
    exit 1
fi

if IFS= read -r EXTRA_LINE <&3; then
    exec 3<&-
    printf 'Local API key file must contain exactly one line.\n' >&2
    unset API_KEY EXTRA_LINE
    exit 1
fi
exec 3<&-

DEVICE_ID="$2"
if [[ "$1" == "simulator" ]]; then
    SIMCTL_CHILD_PLAYAPI_KEY="$API_KEY" \
        xcrun simctl launch --terminate-running-process "$DEVICE_ID" "$BUNDLE_ID"
else
    DEVICECTL_CHILD_PLAYAPI_KEY="$API_KEY" \
        xcrun devicectl device process launch --terminate-existing --device "$DEVICE_ID" "$BUNDLE_ID"
fi

unset API_KEY
