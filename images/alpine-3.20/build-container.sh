#!/usr/bin/env bash
set -euo pipefail
# Pull the official Docker image and save as OCI tar
# Use skopeo if available, otherwise docker save
mkdir -p output

if command -v skopeo &>/dev/null; then
    skopeo copy docker://alpine:3.20 oci-archive:output/alpine-3.20-oci.tar
elif command -v docker &>/dev/null; then
    docker pull alpine:3.20
    docker save alpine:3.20 -o output/alpine-3.20-oci.tar
else
    echo "ERROR: skopeo or docker required"
    exit 1
fi

gzip output/alpine-3.20-oci.tar
echo "Container image ready: output/alpine-3.20-oci.tar.gz"
