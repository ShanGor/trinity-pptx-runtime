#!/bin/bash
set -euo pipefail

# Build script for Trinity PPTX Runtime
# Creates a minimal rootfs with LibreOffice, Python, Node.js, and Poppler

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_ROOT/dist"
BUILD_DIR="$PROJECT_ROOT/build"
ROOTFS="$BUILD_DIR/rootfs"

copy_tree_contents() {
    local src="$1"
    local dst="$2"

    if [ -d "$src" ]; then
        mkdir -p "$dst"
        cp -a "$src"/. "$dst"/
    fi
}

repair_libreoffice_bundle_paths() {
    local dist_root="$1"
    local program_dir="$dist_root/lib/libreoffice/program"
    local fundamental_rc="$program_dir/fundamentalrc"
    local soffice_rc="$program_dir/sofficerc"

    if [ -f "$fundamental_rc" ]; then
        sed -i \
            -e 's|^BRAND_BASE_DIR=file:///usr/lib/libreoffice$|BRAND_BASE_DIR=file://${ORIGIN}/..|' \
            -e 's|file:///etc/libreoffice/registry|file://${ORIGIN}/../../../etc/libreoffice/registry|g' \
            -e 's|file:///usr/share/java/hsqldb1.8.0.jar|file://${ORIGIN}/../../../share/java/hsqldb1.8.0.jar|g' \
            "$fundamental_rc"
    fi

    if [ -f "$soffice_rc" ]; then
        sed -i \
            -e 's|file:///etc/libreoffice/sofficerc|file://${ORIGIN}/../../../etc/libreoffice/sofficerc|g' \
            "$soffice_rc"
    fi
}

verify_runtime_bundle() {
    echo "Verifying bundled runtime..."

    if [ ! -x "$DIST_DIR/bin/python3" ]; then
        echo "Missing bundled python3 binary"
        exit 1
    fi

    if [ ! -x "$DIST_DIR/bin/node" ]; then
        echo "Missing bundled node binary"
        exit 1
    fi

    if [ ! -x "$DIST_DIR/bin/soffice" ]; then
        echo "Missing bundled soffice binary"
        exit 1
    fi

    TRINITY_NO_SANDBOX=1 "$DIST_DIR/trinity-pptx" exec \
        python3 -c "import markitdown, PIL; print(markitdown.__file__)" >/dev/null

    TRINITY_NO_SANDBOX=1 "$DIST_DIR/trinity-pptx" exec \
        node -e "require('pptxgenjs')"

    if command -v bwrap >/dev/null 2>&1; then
        "$DIST_DIR/trinity-pptx" exec soffice --headless --version >/dev/null
    fi
}

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

# Set Ubuntu repository URL based on architecture
if [ "$DEB_ARCH" = "arm64" ]; then
    UBUNTU_REPO="http://ports.ubuntu.com/ubuntu-ports"
else
    UBUNTU_REPO="http://archive.ubuntu.com/ubuntu"
fi
echo "Using repository: $UBUNTU_REPO"

# Create minimal Ubuntu rootfs
echo "Creating minimal rootfs..."
mkdir -p "$ROOTFS"

# Use debootstrap if available, otherwise download minimal rootfs
if command -v debootstrap &> /dev/null; then
    echo "Using debootstrap..."
    debootstrap --variant=minbase --include=ca-certificates \
        jammy "$ROOTFS" "$UBUNTU_REPO"
else
    echo "Downloading minimal Ubuntu rootfs..."
    curl -L "https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-${DEB_ARCH}.tar.gz" | \
        tar xz -C "$ROOTFS"
fi

# Configure apt sources with universe repository
echo "Configuring apt sources..."
cat > "$ROOTFS/etc/apt/sources.list" << EOF
deb $UBUNTU_REPO jammy main universe
deb $UBUNTU_REPO jammy-updates main universe
deb $UBUNTU_REPO jammy-security main universe
EOF

# Install required packages in chroot
echo "Installing packages..."
chroot "$ROOTFS" apt-get update

# Install basic packages first
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg

# Add Node.js repository
chroot "$ROOTFS" bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"

# Install all packages
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
    libreoffice-common \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    libegl1 \
    libgbm1 \
    libgl1 \
    libgl1-mesa-dri \
    libglx-mesa0 \
    libopengl0 \
    poppler-utils \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    fonts-liberation \
    fonts-dejavu-core \
    fonts-freefont-ttf

# Clean up apt cache
chroot "$ROOTFS" apt-get clean
chroot "$ROOTFS" rm -rf /var/lib/apt/lists/*

# Install Python packages into the bundled runtime path.
# Using --target ensures the package lands inside the runtime bundle. We also
# keep packaging logic tolerant of dependencies that still install into
# /usr/local on future distro or toolchain changes.
echo "Installing Python packages..."
chroot "$ROOTFS" mkdir -p /usr/lib/python3/dist-packages
chroot "$ROOTFS" pip3 install --no-cache-dir \
    --target /usr/lib/python3/dist-packages \
    markitdown[pptx] \
    Pillow

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
copy_tree_contents "$ROOTFS/usr/bin" "$DIST_DIR/bin"
copy_tree_contents "$ROOTFS/usr/local/bin" "$DIST_DIR/bin"
copy_tree_contents "$ROOTFS/usr/lib" "$DIST_DIR/lib"
copy_tree_contents "$ROOTFS/usr/local/lib" "$DIST_DIR/lib"
copy_tree_contents "$ROOTFS/usr/lib64" "$DIST_DIR/lib"

# Copy share directories (LibreOffice needs these)
copy_tree_contents "$ROOTFS/usr/share/libreoffice" "$DIST_DIR/share/libreoffice"
copy_tree_contents "$ROOTFS/usr/share/fonts" "$DIST_DIR/share/fonts"
copy_tree_contents "$ROOTFS/usr/share/java" "$DIST_DIR/share/java"
copy_tree_contents "$ROOTFS/usr/share/perl" "$DIST_DIR/share/perl"
copy_tree_contents "$ROOTFS/usr/share/pixmaps" "$DIST_DIR/share/pixmaps"
copy_tree_contents "$ROOTFS/usr/share/xml" "$DIST_DIR/share/xml"

# Copy etc for LibreOffice configuration
mkdir -p "$DIST_DIR/etc"
copy_tree_contents "$ROOTFS/etc/libreoffice" "$DIST_DIR/etc/libreoffice"

# Copy wrapper script
cp "$PROJECT_ROOT/wrapper/trinity-pptx" "$DIST_DIR/"
chmod +x "$DIST_DIR/trinity-pptx"

repair_libreoffice_bundle_paths "$DIST_DIR"

# Create version file
echo "1.0.0" > "$DIST_DIR/VERSION"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$DIST_DIR/VERSION"

verify_runtime_bundle

# Create tarball
echo "Creating tarball..."
cd "$PROJECT_ROOT"
tar czf "trinity-pptx-runtime-linux-${ARCH_NAME}.tar.gz" -C "$DIST_DIR" .

echo ""
echo "=== Build Complete ==="
echo "Output: trinity-pptx-runtime-linux-${ARCH_NAME}.tar.gz"
echo "Size: $(du -h "trinity-pptx-runtime-linux-${ARCH_NAME}.tar.gz" | cut -f1)"
