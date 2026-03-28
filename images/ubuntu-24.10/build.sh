#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
METADATA="$SCRIPT_DIR/metadata.json"
IMAGE_NAME=$(jq -r '.name' "$METADATA")
SOURCE_URL=$(jq -r '.source_url' "$METADATA")
EXPECTED_SHA=$(jq -r '.source_sha256' "$METADATA")
SOURCE_FORMAT=$(jq -r '.source_format' "$METADATA")
CLOUD_INIT=$(jq -r '.cloud_init' "$METADATA")

OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output}"
mkdir -p "$OUTPUT_DIR"

echo "=== Building $IMAGE_NAME ==="

# Download
echo "Downloading from $SOURCE_URL..."
curl -fSL -o "$OUTPUT_DIR/${IMAGE_NAME}.source" "$SOURCE_URL"

# Verify SHA256
echo "Verifying SHA256..."
ACTUAL_SHA=$(sha256sum "$OUTPUT_DIR/${IMAGE_NAME}.source" | awk '{print $1}')
if [ "$EXPECTED_SHA" != "UPDATE_WITH_ACTUAL_SHA256_AFTER_FIRST_DOWNLOAD" ] && [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    echo "ERROR: SHA256 mismatch!"
    echo "  Expected: $EXPECTED_SHA"
    echo "  Actual:   $ACTUAL_SHA"
    rm -f "$OUTPUT_DIR/${IMAGE_NAME}.source"
    exit 1
fi
if [ "$EXPECTED_SHA" = "UPDATE_WITH_ACTUAL_SHA256_AFTER_FIRST_DOWNLOAD" ]; then
    echo "WARNING: SHA256 not pinned yet. Actual SHA256: $ACTUAL_SHA"
    echo "  Update metadata.json with this value."
fi

# Convert to raw
echo "Converting $SOURCE_FORMAT -> raw..."
if [ "$SOURCE_FORMAT" = "qcow2" ]; then
    qemu-img convert -f qcow2 -O raw "$OUTPUT_DIR/${IMAGE_NAME}.source" "$OUTPUT_DIR/${IMAGE_NAME}.raw"
    rm -f "$OUTPUT_DIR/${IMAGE_NAME}.source"
elif [ "$SOURCE_FORMAT" = "raw" ]; then
    mv "$OUTPUT_DIR/${IMAGE_NAME}.source" "$OUTPUT_DIR/${IMAGE_NAME}.raw"
else
    echo "ERROR: Unknown source format: $SOURCE_FORMAT"
    exit 1
fi

# Customize
echo "Customizing image..."
sudo bash "$REPO_ROOT/scripts/customize-image.sh" "$OUTPUT_DIR/${IMAGE_NAME}.raw" "$CLOUD_INIT"

# Compress
echo "Compressing..."
gzip -f "$OUTPUT_DIR/${IMAGE_NAME}.raw"

echo "=== $IMAGE_NAME build complete: $OUTPUT_DIR/${IMAGE_NAME}.raw.gz ==="
