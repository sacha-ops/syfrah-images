#!/usr/bin/env bash
# generate-catalog.sh — Generates catalog.json from built artifacts and metadata.
# Usage: bash scripts/generate-catalog.sh [output_dir] [release_tag]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT_DIR="${1:-$REPO_ROOT/output}"
RELEASE_TAG="${2:-dev}"
BASE_URL="https://github.com/sacha-ops/syfrah-images/releases/download/${RELEASE_TAG}"

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "ERROR: Output directory not found: $OUTPUT_DIR"
    exit 1
fi

echo "Generating catalog.json (tag=$RELEASE_TAG)..."

# Start building the catalog JSON
IMAGES_JSON="[]"

for meta_file in "$REPO_ROOT"/images/*/metadata.json; do
    IMAGE_DIR=$(dirname "$meta_file")
    IMAGE_NAME=$(basename "$IMAGE_DIR")
    RAW_GZ="$OUTPUT_DIR/${IMAGE_NAME}.raw.gz"

    if [ ! -f "$RAW_GZ" ]; then
        echo "  Skipping $IMAGE_NAME (no artifact found)"
        continue
    fi

    echo "  Processing $IMAGE_NAME..."

    # Compute SHA256 of decompressed raw image
    SHA256=$(gunzip -c "$RAW_GZ" | sha256sum | awk '{print $1}')
    SIZE_BYTES=$(stat -c%s "$RAW_GZ" 2>/dev/null || stat -f%z "$RAW_GZ")
    SIZE_MB=$(( SIZE_BYTES / 1024 / 1024 ))

    # Check for container (OCI) variant
    OCI_GZ="$OUTPUT_DIR/${IMAGE_NAME}-oci.tar.gz"
    CONTAINER_FILE="null"
    CONTAINER_SHA256="null"
    if [ -f "$OCI_GZ" ]; then
        CONTAINER_FILE="${IMAGE_NAME}-oci.tar.gz"
        CONTAINER_SHA256=$(sha256sum "$OCI_GZ" | awk '{print $1}')
        echo "    Container variant found: $CONTAINER_FILE"
    fi

    # Read metadata fields
    ARCH=$(jq -r '.arch' "$meta_file")
    OS_FAMILY=$(jq -r '.os_family' "$meta_file")
    VARIANT=$(jq -r '.variant' "$meta_file")
    BOOT_MODE=$(jq -r '.boot_mode' "$meta_file")
    CLOUD_INIT=$(jq -r '.cloud_init' "$meta_file")
    DEFAULT_USER=$(jq -r '.default_username' "$meta_file")
    ROOTFS_FS=$(jq -r '.rootfs_fs' "$meta_file")
    MIN_DISK=$(jq -r '.min_disk_mb' "$meta_file")

    # Add to images array (container_file/container_sha256 are null when no OCI variant)
    if [ "$CONTAINER_FILE" = "null" ]; then
        IMAGES_JSON=$(echo "$IMAGES_JSON" | jq \
            --arg name "$IMAGE_NAME" \
            --arg arch "$ARCH" \
            --arg os_family "$OS_FAMILY" \
            --arg variant "$VARIANT" \
            --arg boot_mode "$BOOT_MODE" \
            --arg sha256 "$SHA256" \
            --argjson size_mb "$SIZE_MB" \
            --argjson min_disk_mb "$MIN_DISK" \
            --argjson cloud_init "$CLOUD_INIT" \
            --arg default_username "$DEFAULT_USER" \
            --arg rootfs_fs "$ROOTFS_FS" \
            --arg file "${IMAGE_NAME}.raw.gz" \
            '. + [{
                name: $name,
                arch: $arch,
                os_family: $os_family,
                variant: $variant,
                format: "raw",
                compression: "gzip",
                boot_mode: $boot_mode,
                sha256: $sha256,
                size_mb: $size_mb,
                min_disk_mb: $min_disk_mb,
                cloud_init: $cloud_init,
                default_username: $default_username,
                rootfs_fs: $rootfs_fs,
                source_kind: "official",
                file: $file,
                container_file: null,
                container_sha256: null
            }]')
    else
        IMAGES_JSON=$(echo "$IMAGES_JSON" | jq \
            --arg name "$IMAGE_NAME" \
            --arg arch "$ARCH" \
            --arg os_family "$OS_FAMILY" \
            --arg variant "$VARIANT" \
            --arg boot_mode "$BOOT_MODE" \
            --arg sha256 "$SHA256" \
            --argjson size_mb "$SIZE_MB" \
            --argjson min_disk_mb "$MIN_DISK" \
            --argjson cloud_init "$CLOUD_INIT" \
            --arg default_username "$DEFAULT_USER" \
            --arg rootfs_fs "$ROOTFS_FS" \
            --arg file "${IMAGE_NAME}.raw.gz" \
            --arg container_file "$CONTAINER_FILE" \
            --arg container_sha256 "$CONTAINER_SHA256" \
            '. + [{
                name: $name,
                arch: $arch,
                os_family: $os_family,
                variant: $variant,
                format: "raw",
                compression: "gzip",
                boot_mode: $boot_mode,
                sha256: $sha256,
                size_mb: $size_mb,
                min_disk_mb: $min_disk_mb,
                cloud_init: $cloud_init,
                default_username: $default_username,
                rootfs_fs: $rootfs_fs,
                source_kind: "official",
                file: $file,
                container_file: $container_file,
                container_sha256: $container_sha256
            }]')
    fi
done

# Build kernel entry if artifact exists
KERNEL_JSON="null"
if [ -f "$OUTPUT_DIR/vmlinux.gz" ]; then
    echo "  Processing kernel..."
    KERNEL_META="$REPO_ROOT/kernel/metadata.json"
    KERNEL_SHA256=$(gunzip -c "$OUTPUT_DIR/vmlinux.gz" | sha256sum | awk '{print $1}')
    KERNEL_VERSION=$(jq -r '.version' "$KERNEL_META")
    KERNEL_ARCH=$(jq -r '.arch' "$KERNEL_META")

    KERNEL_JSON=$(jq -n \
        --arg version "$KERNEL_VERSION" \
        --arg arch "$KERNEL_ARCH" \
        --arg sha256 "$KERNEL_SHA256" \
        '{
            name: "vmlinux",
            version: $version,
            arch: $arch,
            format: "firmware",
            compression: "gzip",
            sha256: $sha256,
            file: "vmlinux.gz"
        }')
fi

# Assemble final catalog
jq -n \
    --argjson images "$IMAGES_JSON" \
    --argjson kernel "$KERNEL_JSON" \
    --arg base_url "$BASE_URL" \
    '{
        version: 1,
        base_url: $base_url,
        images: $images,
        kernel: $kernel
    }' > "$OUTPUT_DIR/catalog.json"

IMAGE_COUNT=$(echo "$IMAGES_JSON" | jq 'length')
echo "Catalog generated: $OUTPUT_DIR/catalog.json ($IMAGE_COUNT images)"
