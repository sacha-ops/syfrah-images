# syfrah-images

Pre-built VM images and kernel for the Syfrah compute layer.

## What this repo does

This repo contains build scripts and CI pipelines that produce ready-to-boot VM images for [Cloud Hypervisor](https://github.com/cloud-hypervisor/cloud-hypervisor). Each image starts from an official cloud image published by the OS vendor, gets converted to raw format, customized for Syfrah (cloud-init NoCloud datasource, cleanup), compressed, and published as a GitHub Release.

A shared kernel (vmlinux) is also downloaded from Cloud Hypervisor releases and published alongside the images.

## Available images

| Image | Source | Format |
|-------|--------|--------|
| ubuntu-24.04 | Canonical cloud images | qcow2 -> raw |
| ubuntu-24.10 | Canonical cloud images | qcow2 -> raw |
| alpine-3.20 | Alpine Linux cloud images | qcow2 -> raw |
| debian-12 | Debian cloud images | raw |

## How images are built

1. Download the official cloud image (pinned URL + SHA256 in `metadata.json`)
2. Verify source SHA256 (supply chain security)
3. Convert to raw format if needed (`qemu-img convert`)
4. Apply Syfrah customizations (`scripts/customize-image.sh`):
   - Configure cloud-init NoCloud datasource
   - Truncate logs
   - Clear machine-id for regeneration at boot
   - Remove SSH host keys (regenerated at boot)
5. Compress with gzip
6. Publish as GitHub Release with `catalog.json`

## How to add a new image

1. Create a new directory under `images/` (e.g., `images/fedora-41/`)
2. Add `metadata.json` with source URL, SHA256, and OS metadata
3. Add `build.sh` that downloads, verifies, converts, and customizes the image
4. Update the matrix in `.github/workflows/build-images.yml`
5. Open a PR

## How releases work

- **Trigger**: Manual (`workflow_dispatch`) or monthly schedule (1st of every month)
- **Pipeline**: Build all images + kernel -> generate `catalog.json` -> create GitHub Release
- **Tag format**: `images-vN` (auto-incrementing)
- **Latest**: `https://github.com/sacha-ops/syfrah-images/releases/latest/download/catalog.json`

## How Syfrah CLI consumes images

The Syfrah CLI fetches `catalog.json` from the latest release to discover available images:

```bash
syfrah compute image list          # Lists available images from catalog
syfrah compute image pull ubuntu-24.10  # Downloads and caches an image
```

See [handbook/image-management.md](https://github.com/sacha-ops/syfrah/blob/main/handbook/image-management.md) in the main repo for the full design.

## Local development

```bash
# Build all images (requires qemu-utils, guestfish, jq, curl)
sudo bash scripts/build-all.sh

# Build a single image
bash images/ubuntu-24.04/build.sh

# Generate catalog from built artifacts
bash scripts/generate-catalog.sh output dev
```

## License

Apache 2.0
