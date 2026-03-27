#!/bin/bash
set -euo pipefail

# Build script for Trinity PPTX Runtime
# Creates a minimal rootfs with LibreOffice, Python, Node.js, and Poppler

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEFAULT_DIST_DIR="$PROJECT_ROOT/dist"
DEFAULT_BUILD_DIR="$PROJECT_ROOT/build"
DIST_DIR="$DEFAULT_DIST_DIR"
BUILD_DIR="$DEFAULT_BUILD_DIR"
ROOTFS="$BUILD_DIR/rootfs"

copy_tree_contents() {
    local src="$1"
    local dst="$2"

    if [ -d "$src" ]; then
        mkdir -p "$dst"
        cp -a "$src"/. "$dst"/
    fi
}

copy_path_into_dir() {
    local src="$1"
    local dst_dir="$2"

    if [ -e "$src" ] || [ -L "$src" ]; then
        mkdir -p "$dst_dir"
        cp -a "$src" "$dst_dir"/
    fi
}

path_mount_options() {
    local path="$1"
    local probe="$path"
    local mount_point=""

    while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
        probe="$(dirname "$probe")"
    done

    if command -v findmnt >/dev/null 2>&1; then
        findmnt -T "$probe" -no OPTIONS 2>/dev/null || true
        return 0
    fi

    mount_point="$(df -P "$probe" 2>/dev/null | awk 'NR==2 {print $6}')"
    if [ -n "$mount_point" ]; then
        awk -v mount_point="$mount_point" '$2 == mount_point {print $4; exit}' /proc/mounts
    fi
}

build_dir_supports_rootfs() {
    local options

    options="$(path_mount_options "$1")"
    case ",${options}," in
        *,nodev,*|*,noexec,*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

choose_build_dir() {
    local preferred_dir="$1"

    if build_dir_supports_rootfs "$preferred_dir"; then
        echo "$preferred_dir"
        return 0
    fi

    mktemp -d "${TMPDIR:-/tmp}/trinity-pptx-runtime-build.XXXXXX"
}

resolve_ubuntu_repo() {
    local deb_arch="$1"

    if [ -n "${UBUNTU_REPO:-}" ]; then
        echo "$UBUNTU_REPO"
        return 0
    fi

    if [ "$deb_arch" = "arm64" ]; then
        echo "http://ports.ubuntu.com/ubuntu-ports"
    else
        echo "http://archive.ubuntu.com/ubuntu"
    fi
}

run_in_chroot() {
    local rootfs="$1"
    local passthrough_var=""
    local -a env_vars=(
        HOME=/root
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        LANG=C.UTF-8
        LC_ALL=C.UTF-8
        DEBIAN_FRONTEND=noninteractive
        PIP_DISABLE_PIP_VERSION_CHECK=1
    )

    shift

    for passthrough_var in \
        HTTP_PROXY \
        HTTPS_PROXY \
        NO_PROXY \
        NPM_CONFIG_REGISTRY \
        PIP_EXTRA_INDEX_URL \
        PIP_FIND_LINKS \
        PIP_INDEX_URL \
        PIP_NO_INDEX \
        PIP_TRUSTED_HOST \
        http_proxy \
        https_proxy \
        no_proxy \
        npm_config_registry
    do
        if [ -n "${!passthrough_var:-}" ]; then
            env_vars+=("${passthrough_var}=${!passthrough_var}")
        fi
    done

    chroot "$rootfs" /usr/bin/env "${env_vars[@]}" "$@"
}

cleanup_chroot_environment() {
    local rootfs="$1"

    umount -R "$rootfs/dev" >/dev/null 2>&1 || true
    umount -R "$rootfs/sys" >/dev/null 2>&1 || true
    umount "$rootfs/proc" >/dev/null 2>&1 || true
}

prepare_chroot_environment() {
    local rootfs="$1"

    mkdir -p "$rootfs/proc" "$rootfs/sys" "$rootfs/dev"
    cleanup_chroot_environment "$rootfs"

    mount -t proc proc "$rootfs/proc"
    mount --rbind /sys "$rootfs/sys"
    mount --make-rslave "$rootfs/sys"
    mount --rbind /dev "$rootfs/dev"
    mount --make-rslave "$rootfs/dev"
}

repair_libreoffice_bundle_paths() {
    local dist_root="$1"
    local program_dir="$dist_root/lib/libreoffice/program"
    local fundamental_rc="$program_dir/fundamentalrc"
    local soffice_rc="$program_dir/sofficerc"
    local bootstrap_rc="$program_dir/bootstraprc"

    if [ -f "$fundamental_rc" ]; then
        sed -i \
            -e 's|^BRAND_BASE_DIR=file:///usr/lib/libreoffice$|BRAND_BASE_DIR=${ORIGIN}/..|' \
            -e 's|^BRAND_BASE_DIR=file://\${ORIGIN}|BRAND_BASE_DIR=${ORIGIN}|' \
            -e 's|file:///etc/libreoffice/registry|file://${ORIGIN}/../../../etc/libreoffice/registry|g' \
            -e 's|file:///usr/share/java/hsqldb1.8.0.jar|file://${ORIGIN}/../../../share/java/hsqldb1.8.0.jar|g' \
            "$fundamental_rc"
    fi

    if [ -f "$soffice_rc" ]; then
        sed -i \
            -e 's|file:///etc/libreoffice/sofficerc|file://${ORIGIN}/../../../etc/libreoffice/sofficerc|g' \
            "$soffice_rc"
    fi

    if [ -f "$bootstrap_rc" ]; then
        sed -i \
            -e 's|^InstallMode=.*|InstallMode=install|' \
            -e 's|^UserInstallation=.*|UserInstallation=$SYSUSERCONFIG/libreoffice/4|' \
            "$bootstrap_rc"
    fi
}

repair_libreoffice_program_compat_symlinks() {
    local dist_root="$1"
    local program_dir="$dist_root/lib/libreoffice/program"
    local arch_dir
    local dst
    local src
    local entry
    local -a symlink_entries=(
        "unorc"
        "lounorc"
        "types.rdb"
        "services.rdb"
        "libgcc3_uno.so"
    )
    local -a copy_entries=(
        "bootstraprc"
        "redirectrc"
        "fundamentalrc"
        "sofficerc"
        "setuprc"
        "versionrc"
    )

    if [ ! -d "$program_dir" ]; then
        return 0
    fi

    while IFS= read -r arch_dir; do
        for entry in "${symlink_entries[@]}"; do
            src="${program_dir}/${entry}"
            dst="${arch_dir}/${entry}"
            if [ ! -e "$src" ]; then
                continue
            fi
            if [ -L "$dst" ] && [ ! -e "$dst" ]; then
                rm -f "$dst"
            fi
            if [ -e "$dst" ] || [ -L "$dst" ]; then
                continue
            fi
            ln -s "../libreoffice/program/${entry}" "$dst"
        done

        for subdir in services types; do
            if [ -d "${program_dir}/${subdir}" ]; then
                dst="${arch_dir}/${subdir}"
                if [ -L "$dst" ] && [ ! -e "$dst" ]; then
                    rm -f "$dst"
                fi
                if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
                    ln -s "../libreoffice/program/${subdir}" "$dst"
                fi
            fi
        done

        for entry in "${copy_entries[@]}"; do
            src="${program_dir}/${entry}"
            dst="${arch_dir}/${entry}"
            if [ ! -f "$src" ]; then
                continue
            fi
            if [ -L "$dst" ] || [ -f "$dst" ]; then
                rm -f "$dst"
            fi
            cp "$src" "$dst"
            case "$entry" in
                fundamentalrc)
                    sed -i \
                        -e 's|^BRAND_BASE_DIR=.*|BRAND_BASE_DIR=${ORIGIN}/../libreoffice|' \
                        -e 's|^BRAND_INI_DIR=.*|BRAND_INI_DIR=${ORIGIN}/../libreoffice/program|' \
                        -e 's|file://${ORIGIN}/../../../etc/libreoffice/registry|file://${ORIGIN}/../../etc/libreoffice/registry|g' \
                        -e 's|file://${ORIGIN}/../../../share/java/hsqldb1.8.0.jar|file://${ORIGIN}/../../share/java/hsqldb1.8.0.jar|g' \
                        "$dst"
                    ;;
                sofficerc)
                    sed -i \
                        -e 's|file://${ORIGIN}/../../../etc/libreoffice/sofficerc|file://${ORIGIN}/../../etc/libreoffice/sofficerc|g' \
                        "$dst"
                    ;;
            esac
        done
    done < <(find "$dist_root/lib" -mindepth 1 -maxdepth 1 -type d -name '*-linux-gnu' | sort)
}

repair_libreoffice_share_symlinks() {
    local dist_root="$1"
    local share_dir="$dist_root/lib/libreoffice/share"

    if [ ! -d "$share_dir" ]; then
        return 0
    fi

    mkdir -p \
        "$dist_root/var/lib/libreoffice/share/prereg/bundled" \
        "$dist_root/var/spool/libreoffice/uno_packages/cache"

    rm -f "$share_dir/registry"
    ln -s "../../../etc/libreoffice/registry" "$share_dir/registry"

    mkdir -p "$share_dir/psprint" "$share_dir/prereg" "$share_dir/uno_packages"
    rm -f "$share_dir/psprint/psprint.conf" "$share_dir/prereg/bundled" "$share_dir/uno_packages/cache"
    ln -s "../../../../etc/libreoffice/psprint.conf" "$share_dir/psprint/psprint.conf"
    ln -s "../../../../var/lib/libreoffice/share/prereg/bundled" "$share_dir/prereg/bundled"
    ln -s "../../../../var/spool/libreoffice/uno_packages/cache" "$share_dir/uno_packages/cache"
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

    if [ ! -x "$DIST_DIR/lib/libreoffice/program/javaldx" ]; then
        echo "Missing bundled LibreOffice javaldx helper"
        exit 1
    fi

    if [ ! -f "$DIST_DIR/share/java/hsqldb1.8.0.jar" ]; then
        echo "Missing bundled LibreOffice Java dependency: share/java/hsqldb1.8.0.jar"
        exit 1
    fi

    TRINITY_NO_SANDBOX=1 "$DIST_DIR/trinity-pptx" exec \
        python3 -c "import markitdown, PIL; print(markitdown.__file__)" >/dev/null

    TRINITY_NO_SANDBOX=1 "$DIST_DIR/trinity-pptx" exec \
        node -e "require('pptxgenjs')"

    if [ -d "$DIST_DIR/rootfs/usr/bin" ] && [ -d "$DIST_DIR/rootfs/usr/lib/libreoffice" ]; then
        prepare_chroot_environment "$DIST_DIR/rootfs"
        if ! run_in_chroot "$DIST_DIR/rootfs" /usr/bin/env \
            -u DISPLAY \
            -u WAYLAND_DISPLAY \
            -u XDG_RUNTIME_DIR \
            -u DBUS_SESSION_BUS_ADDRESS \
            /usr/bin/soffice --headless --version >/dev/null
        then
            cleanup_chroot_environment "$DIST_DIR/rootfs"
            echo "Bundled rootfs soffice failed to start"
            exit 1
        fi
        cleanup_chroot_environment "$DIST_DIR/rootfs"
    else
        env -u DISPLAY -u WAYLAND_DISPLAY -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS \
            TRINITY_NO_SANDBOX=1 "$DIST_DIR/trinity-pptx" exec \
            soffice --headless --version >/dev/null
    fi

    if bwrap_is_usable; then
        env -u DISPLAY -u WAYLAND_DISPLAY -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS \
            "$DIST_DIR/trinity-pptx" exec soffice --headless --version >/dev/null
    elif command -v bwrap >/dev/null 2>&1; then
        echo "Skipping sandboxed soffice verification because bubblewrap is installed but unusable in this environment"
    fi
}

bwrap_is_usable() {
    command -v bwrap >/dev/null 2>&1 || return 1
    bwrap --ro-bind / / --dev /dev --proc /proc /bin/true >/dev/null 2>&1
}

main() {
    local preferred_build_dir="${TRINITY_BUILD_DIR:-$DEFAULT_BUILD_DIR}"

    DIST_DIR="${TRINITY_DIST_DIR:-$DEFAULT_DIST_DIR}"
    BUILD_DIR="$(choose_build_dir "$preferred_build_dir")"
    ROOTFS="$BUILD_DIR/rootfs"

    echo "=== Trinity PPTX Runtime Builder ==="
    echo "Build directory: $BUILD_DIR"
    echo "Output directory: $DIST_DIR"
    if [ "$BUILD_DIR" != "$preferred_build_dir" ]; then
        echo "Using a temporary build directory because ${preferred_build_dir} is mounted with nodev/noexec"
    fi

    # Clean previous builds
    cleanup_chroot_environment "$ROOTFS"
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

    # Allow callers to override the Ubuntu mirror while preserving
    # architecture-specific defaults for normal builds.
    UBUNTU_REPO="$(resolve_ubuntu_repo "$DEB_ARCH")"
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

    # Package post-install hooks need a normal chroot view of /proc and /dev.
    prepare_chroot_environment "$ROOTFS"
    trap 'cleanup_chroot_environment "$ROOTFS"' EXIT

    # Install required packages in chroot
    echo "Installing packages..."
    run_in_chroot "$ROOTFS" apt-get update

    # Install basic packages first
    run_in_chroot "$ROOTFS" apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg

    # Add Node.js repository
    run_in_chroot "$ROOTFS" bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"

    # Install all packages.
    # libreoffice-sdbc-hsqldb stays explicit because libreoffice-base-drivers
    # only recommends it, and this build intentionally uses
    # --no-install-recommends to keep the bundle size down.
    run_in_chroot "$ROOTFS" apt-get install -y --no-install-recommends \
        libreoffice-nogui \
        libreoffice-java-common \
        libreoffice-sdbc-hsqldb \
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
    run_in_chroot "$ROOTFS" apt-get clean
    run_in_chroot "$ROOTFS" rm -rf /var/lib/apt/lists/*

    # Install Python packages into the bundled runtime path.
    # Using --target ensures the package lands inside the runtime bundle. We also
    # keep packaging logic tolerant of dependencies that still install into
    # /usr/local on future distro or toolchain changes.
    echo "Installing Python packages..."
    run_in_chroot "$ROOTFS" mkdir -p /usr/lib/python3/dist-packages
    run_in_chroot "$ROOTFS" pip3 install --no-cache-dir \
        --retries "${PIP_RETRIES:-10}" \
        --timeout "${PIP_TIMEOUT:-300}" \
        --target /usr/lib/python3/dist-packages \
        markitdown[pptx] \
        Pillow

    # Install Node.js packages globally
    echo "Installing Node.js packages..."
    run_in_chroot "$ROOTFS" npm install -g pptxgenjs

    cleanup_chroot_environment "$ROOTFS"
    trap - EXIT

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

    # Copy to dist with a preserved rootfs for LibreOffice and top-level
    # compatibility symlinks for the existing wrapper/runtime contract.
    echo "Creating distribution package..."
    mkdir -p "$DIST_DIR/rootfs" "$DIST_DIR/rootfs/var/lib" "$DIST_DIR/rootfs/var/spool"

    copy_path_into_dir "$ROOTFS/bin" "$DIST_DIR/rootfs"
    copy_path_into_dir "$ROOTFS/lib" "$DIST_DIR/rootfs"
    copy_path_into_dir "$ROOTFS/lib64" "$DIST_DIR/rootfs"
    copy_path_into_dir "$ROOTFS/usr" "$DIST_DIR/rootfs"
    copy_path_into_dir "$ROOTFS/etc" "$DIST_DIR/rootfs"
    copy_path_into_dir "$ROOTFS/var/lib/libreoffice" "$DIST_DIR/rootfs/var/lib"
    copy_path_into_dir "$ROOTFS/var/spool/libreoffice" "$DIST_DIR/rootfs/var/spool"

    ln -s "rootfs/usr/bin" "$DIST_DIR/bin"
    ln -s "rootfs/usr/lib" "$DIST_DIR/lib"
    ln -s "rootfs/usr/share" "$DIST_DIR/share"
    ln -s "rootfs/etc" "$DIST_DIR/etc"
    ln -s "rootfs/var" "$DIST_DIR/var"

    # Copy wrapper script
    cp "$PROJECT_ROOT/wrapper/trinity-pptx" "$DIST_DIR/"
    chmod +x "$DIST_DIR/trinity-pptx"

    # Create version file
    echo "1.0.0" > "$DIST_DIR/VERSION"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$DIST_DIR/VERSION"

    verify_runtime_bundle

    # Create tarball
    echo "Creating tarball..."
    cd "$PROJECT_ROOT"
    tar --hard-dereference -czf "trinity-pptx-runtime-linux-${ARCH_NAME}.tar.gz" -C "$DIST_DIR" .

    echo ""
    echo "=== Build Complete ==="
    echo "Output: trinity-pptx-runtime-linux-${ARCH_NAME}.tar.gz"
    echo "Size: $(du -h "trinity-pptx-runtime-linux-${ARCH_NAME}.tar.gz" | cut -f1)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
