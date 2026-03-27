#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_SCRIPT="${PROJECT_ROOT}/runtime/build.sh"

# shellcheck source=/dev/null
source "${BUILD_SCRIPT}"

calls_file="$(mktemp)"
trap 'rm -f "$calls_file"' EXIT

mkdir() {
    printf 'mkdir %s\n' "$*" >>"$calls_file"
}

mount() {
    printf 'mount %s\n' "$*" >>"$calls_file"
}

umount() {
    printf 'umount %s\n' "$*" >>"$calls_file"
}

chroot() {
    printf 'chroot %s\n' "$*" >>"$calls_file"
}

rootfs="/tmp/trinity-runtime-root"
PIP_INDEX_URL="https://mirror.example.com/simple"

prepare_chroot_environment "$rootfs"
run_in_chroot "$rootfs" apt-get update
cleanup_chroot_environment "$rootfs"

for expected in \
    "mkdir -p ${rootfs}/proc ${rootfs}/sys ${rootfs}/dev" \
    "umount -R ${rootfs}/dev" \
    "umount -R ${rootfs}/sys" \
    "umount ${rootfs}/proc" \
    "mount -t proc proc ${rootfs}/proc" \
    "mount --rbind /sys ${rootfs}/sys" \
    "mount --make-rslave ${rootfs}/sys" \
    "mount --rbind /dev ${rootfs}/dev" \
    "mount --make-rslave ${rootfs}/dev" \
    "chroot ${rootfs} /usr/bin/env" \
    "HOME=/root" \
    "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "LANG=C.UTF-8" \
    "LC_ALL=C.UTF-8" \
    "DEBIAN_FRONTEND=noninteractive" \
    "PIP_DISABLE_PIP_VERSION_CHECK=1" \
    "PIP_INDEX_URL=${PIP_INDEX_URL}" \
    "apt-get update"
do
    if ! grep -F "$expected" "$calls_file" >/dev/null; then
        echo "Expected helper call not observed: $expected" >&2
        cat "$calls_file" >&2
        exit 1
    fi
done

echo "PASS: runtime/build.sh prepares a usable chroot environment"
