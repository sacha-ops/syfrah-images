#!/usr/bin/env bash
# customize-image.sh — Shared customization logic for Syfrah VM images.
# Must be run as root (needs loop mount).
#
# Usage: sudo bash customize-image.sh <image.raw> [cloud_init=true|false]
set -euo pipefail

IMAGE_RAW="$1"
CLOUD_INIT="${2:-true}"

if [ ! -f "$IMAGE_RAW" ]; then
    echo "ERROR: Image file not found: $IMAGE_RAW"
    exit 1
fi

echo "Customizing $IMAGE_RAW (cloud_init=$CLOUD_INIT)..."

# Set up loop device with partition scanning
LOOP_DEV=$(losetup --find --show --partscan "$IMAGE_RAW")
echo "  Loop device: $LOOP_DEV"

# Find the root partition. Try common layouts:
#   - ${LOOP_DEV}p1  (single partition or first partition is root)
#   - ${LOOP_DEV}p2  (first partition is EFI/boot, second is root)
ROOT_PART=""
for candidate in "${LOOP_DEV}p1" "${LOOP_DEV}p2" "${LOOP_DEV}p3"; do
    if [ -b "$candidate" ]; then
        FS_TYPE=$(blkid -o value -s TYPE "$candidate" 2>/dev/null || true)
        if [ "$FS_TYPE" = "ext4" ] || [ "$FS_TYPE" = "xfs" ] || [ "$FS_TYPE" = "btrfs" ]; then
            ROOT_PART="$candidate"
            break
        fi
    fi
done

if [ -z "$ROOT_PART" ]; then
    echo "WARNING: Could not find a root partition with ext4/xfs/btrfs."
    echo "  Trying ${LOOP_DEV}p1 anyway..."
    ROOT_PART="${LOOP_DEV}p1"
fi

MOUNT_DIR=$(mktemp -d)
echo "  Mounting $ROOT_PART -> $MOUNT_DIR"
mount "$ROOT_PART" "$MOUNT_DIR"

# Cloud-init configuration
if [ "$CLOUD_INIT" = "true" ]; then
    if [ -d "$MOUNT_DIR/usr/bin" ] || [ -d "$MOUNT_DIR/usr/sbin" ]; then
        # Check if cloud-init is installed
        if [ -f "$MOUNT_DIR/usr/bin/cloud-init" ] || [ -f "$MOUNT_DIR/usr/sbin/cloud-init" ]; then
            echo "  Configuring cloud-init NoCloud datasource..."
            mkdir -p "$MOUNT_DIR/etc/cloud/cloud.cfg.d"
            cat > "$MOUNT_DIR/etc/cloud/cloud.cfg.d/99_syfrah.cfg" <<CLOUD
# Syfrah: prioritize NoCloud datasource for direct-kernel boot
datasource_list: [NoCloud, None]
CLOUD
        else
            echo "  WARNING: cloud-init not found in image, skipping cloud-init config"
        fi
    fi
fi

# Cleanup for fresh boot
echo "  Truncating logs..."
find "$MOUNT_DIR/var/log" -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true
find "$MOUNT_DIR/var/log" -type f -name "*.log.*" -exec rm -f {} \; 2>/dev/null || true

echo "  Clearing machine-id..."
rm -f "$MOUNT_DIR/etc/machine-id"
touch "$MOUNT_DIR/etc/machine-id"

echo "  Removing SSH host keys..."
rm -f "$MOUNT_DIR/etc/ssh/ssh_host_"* 2>/dev/null || true

# Sync and unmount
echo "  Syncing..."
sync
umount "$MOUNT_DIR"
losetup -d "$LOOP_DEV"
rmdir "$MOUNT_DIR"

echo "  Customization complete."
