#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_SCRIPT="${PROJECT_ROOT}/runtime/build.sh"

# shellcheck source=/dev/null
source "${BUILD_SCRIPT}"

unset UBUNTU_REPO
if [ "$(resolve_ubuntu_repo amd64)" != "http://archive.ubuntu.com/ubuntu" ]; then
    echo "Expected amd64 builds to default to archive.ubuntu.com" >&2
    exit 1
fi

if [ "$(resolve_ubuntu_repo arm64)" != "http://ports.ubuntu.com/ubuntu-ports" ]; then
    echo "Expected arm64 builds to default to ports.ubuntu.com" >&2
    exit 1
fi

UBUNTU_REPO="http://mirror.example.com/ubuntu"
if [ "$(resolve_ubuntu_repo amd64)" != "http://mirror.example.com/ubuntu" ]; then
    echo "Expected UBUNTU_REPO env var to override amd64 default" >&2
    exit 1
fi

if [ "$(resolve_ubuntu_repo arm64)" != "http://mirror.example.com/ubuntu" ]; then
    echo "Expected UBUNTU_REPO env var to override arm64 default" >&2
    exit 1
fi

echo "PASS: runtime/build.sh honors UBUNTU_REPO overrides"
