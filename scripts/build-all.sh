#!/usr/bin/env bash
# build-all.sh — Orchestrator that builds all images and the kernel.
# Usage: sudo bash scripts/build-all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output}"
mkdir -p "$OUTPUT_DIR"

echo "============================================="
echo "  Syfrah Images — Full Build"
echo "  Output: $OUTPUT_DIR"
echo "============================================="
echo ""

# Validate structure
echo "Validating repository structure..."
ERRORS=0
for image_dir in "$REPO_ROOT"/images/*/; do
    image_name=$(basename "$image_dir")
    if [ ! -f "$image_dir/metadata.json" ]; then
        echo "  ERROR: Missing metadata.json for $image_name"
        ERRORS=$((ERRORS + 1))
    fi
    if [ ! -f "$image_dir/build.sh" ]; then
        echo "  ERROR: Missing build.sh for $image_name"
        ERRORS=$((ERRORS + 1))
    fi
done
if [ ! -f "$REPO_ROOT/kernel/metadata.json" ] || [ ! -f "$REPO_ROOT/kernel/build.sh" ]; then
    echo "  ERROR: Missing kernel metadata.json or build.sh"
    ERRORS=$((ERRORS + 1))
fi
if [ "$ERRORS" -gt 0 ]; then
    echo "Structure validation failed with $ERRORS error(s)."
    exit 1
fi
echo "  Structure OK."
echo ""

# Build images
FAILED=()
for image_dir in "$REPO_ROOT"/images/*/; do
    image_name=$(basename "$image_dir")
    echo "--- Building $image_name ---"
    if bash "$image_dir/build.sh"; then
        echo "--- $image_name OK ---"
    else
        echo "--- $image_name FAILED ---"
        FAILED+=("$image_name")
    fi
    echo ""
done

# Build kernel
echo "--- Building kernel ---"
if bash "$REPO_ROOT/kernel/build.sh"; then
    echo "--- kernel OK ---"
else
    echo "--- kernel FAILED ---"
    FAILED+=("kernel")
fi
echo ""

# Summary
echo "============================================="
if [ ${#FAILED[@]} -eq 0 ]; then
    echo "  All builds succeeded."
else
    echo "  FAILED: ${FAILED[*]}"
    exit 1
fi
echo ""
echo "Artifacts in $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR/"
echo "============================================="
