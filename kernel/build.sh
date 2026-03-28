#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA="$SCRIPT_DIR/metadata.json"

SOURCE_URL=$(jq -r '.source_url' "$METADATA")
EXPECTED_SHA=$(jq -r '.source_sha256' "$METADATA")
VERSION=$(jq -r '.version' "$METADATA")

OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output}"
mkdir -p "$OUTPUT_DIR"

echo "=== Building kernel $VERSION ==="

# Download
echo "Downloading kernel from $SOURCE_URL..."
curl -fSL -o "$OUTPUT_DIR/vmlinux" "$SOURCE_URL"

# Verify SHA256
echo "Verifying SHA256..."
ACTUAL_SHA=$(sha256sum "$OUTPUT_DIR/vmlinux" | awk '{print $1}')
if [ "$EXPECTED_SHA" != "UPDATE_WITH_ACTUAL_SHA256_AFTER_FIRST_DOWNLOAD" ] && [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    echo "ERROR: SHA256 mismatch!"
    echo "  Expected: $EXPECTED_SHA"
    echo "  Actual:   $ACTUAL_SHA"
    rm -f "$OUTPUT_DIR/vmlinux"
    exit 1
fi
if [ "$EXPECTED_SHA" = "UPDATE_WITH_ACTUAL_SHA256_AFTER_FIRST_DOWNLOAD" ]; then
    echo "WARNING: SHA256 not pinned yet. Actual SHA256: $ACTUAL_SHA"
    echo "  Update metadata.json with this value."
fi

# Validate format
# Cloud Hypervisor firmware (hypervisor-fw) may be ELF or a flat binary.
# We accept either ELF or a valid firmware blob.
echo "Validating kernel/firmware format..."
FILE_TYPE=$(file "$OUTPUT_DIR/vmlinux")
echo "  File type: $FILE_TYPE"
if echo "$FILE_TYPE" | grep -qE "(ELF|data|firmware)"; then
    echo "  Format OK"
else
    echo "WARNING: Unexpected file type. This may still work with Cloud Hypervisor."
    echo "  If direct boot fails, check that the correct asset was downloaded."
fi

# Compress
echo "Compressing..."
gzip -f -k "$OUTPUT_DIR/vmlinux"

echo "=== Kernel $VERSION ready: $OUTPUT_DIR/vmlinux.gz ==="
