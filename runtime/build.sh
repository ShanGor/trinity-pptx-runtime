#!/bin/bash
set -euo pipefail

# Build script for Trinity PPTX Runtime
# Creates a minimal rootfs with LibreOffice, Python, Node.js, and Poppler

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_ROOT/dist"
BUILD_DIR="$PROJECT_ROOT/build"

echo "=== Trinity PPTX Runtime Builder ==="
echo "Build directory: $BUILD_DIR"
echo "Output directory: $DIST_DIR"

# Clean previous builds
rm -rf "$DIST_DIR" "$BUILD_DIR"
mkdir -p "$DIST_DIR" "$BUILD_DIR"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH_NAME="x64"
    DEB_ARCH="amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    ARCH_NAME="arm64"
    DEB_ARCH="arm64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

echo "Building for architecture: $ARCH ($DEB_ARCH)"

# Create minimal Ubuntu rootfs
echo "Creating minimal rootfs..."
ROOTFS="$BUILD_DIR/rootfs"
mkdir -p "$ROOTFS"

# Use debootstrap if available, otherwise download minimal rootfs
if command -v debootstrap &> /dev/null; then
    echo "Using debootstrap..."
    debootstrap --variant=minbase --include=ca-certificates,libreoffice-common,poppler-utils \
        jammy "$ROOTFS" http://archive.ubuntu.com/ubuntu/
else
    echo "Downloading minimal Ubuntu rootfs..."
    curl -L "https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-${DEB_ARCH}.tar.gz" | \
        tar xz -C "$ROOTFS"
fi

# Install required packages in chroot
echo "Installing packages..."
chroot "$ROOTFS" apt-get update
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
    libreoffice-common \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    poppler-utils \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    ca-certificates \
    fonts-liberation \
    fonts-dejavu-core \
    fonts-freefont-ttf

# Clean up apt cache
chroot "$ROOTFS" apt-get clean
chroot "$ROOTFS" rm -rf /var/lib/apt/lists/*

# Install Python packages
echo "Installing Python packages..."
chroot "$ROOTFS" pip3 install --no-cache-dir markitdown[pptx] Pillow

# Install Node.js packages globally
echo "Installing Node.js packages..."
chroot "$ROOTFS" npm install -g pptxgenjs

# Remove unnecessary files to reduce size
echo "Optimizing rootfs size..."
rm -rf "$ROOTFS/usr/share/doc"/*
rm -rf "$ROOTFS/usr/share/man"/*
rm -rf "$ROOTFS/usr/share/info"/*
rm -rf "$ROOTFS/var/cache"/*
rm -rf "$ROOTFS/var/log"/*
rm -rf "$ROOTFS/tmp"/*
find "$ROOTFS/usr/lib/python3" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "$ROOTFS/usr/lib/python3" -name "*.pyc" -delete 2>/dev/null || true

# Copy to dist with proper structure
echo "Creating distribution package..."
mkdir -p "$DIST_DIR/bin" "$DIST_DIR/lib" "$DIST_DIR/share"

# Copy binaries
cp -r "$ROOTFS/usr/bin"/* "$DIST_DIR/bin/" 2>/dev/null || true
cp -r "$ROOTFS/usr/lib"/* "$DIST_DIR/lib/" 2>/dev/null || true
cp -r "$ROOTFS/usr/lib64"/* "$DIST_DIR/lib/" 2>/dev/null || true
cp -r "$ROOTFS/usr/share/libreoffice" "$DIST_DIR/share/" 2>/dev/null || true
cp -r "$ROOTFS/usr/share/fonts" "$DIST_DIR/share/" 2>/dev/null || true

# Copy wrapper script
cp "$PROJECT_ROOT/wrapper/trinity-pptx" "$DIST_DIR/"
chmod +x "$DIST_DIR/trinity-pptx"

# Create version file
echo "1.0.0" > "$DIST_DIR/VERSION"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$DIST_DIR/VERSION"

# Create tarball
echo "Creating tarball..."
cd "$PROJECT_ROOT"
tar czf "trinity-pptx-runtime-linux-${ARCH_NAME}.tar.gz" -C "$DIST_DIR" .

echo ""
echo "=== Build Complete ==="
echo "Output: trinity-pptx-runtime-linux-${ARCH_NAME}.tar.gz"
echo "Size: $(du -h "trinity-pptx-runtime-linux-${ARCH_NAME}.tar.gz" | cut -f1)"
