#!/bin/bash
#
# Trinity PPTX Runtime - Installation Script
# Downloads and installs a release by default; local install is explicit-only
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="trinity-pptx-runtime"
GITHUB_REPO="ShanGor/${REPO}"
INSTALL_DIR="${HOME}/.local/share/trinity-pptx-runtime"
BIN_DIR="${HOME}/.local/bin"
VERSION="${VERSION:-latest}"
SOURCE_MODE="release"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect architecture
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "x64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# Detect OS
detect_os() {
    local os=$(uname -s)
    case "$os" in
        Linux)
            echo "linux"
            ;;
        *)
            log_error "Unsupported operating system: $os"
            exit 1
            ;;
    esac
}

# Check dependencies
check_deps() {
    local deps=("curl" "tar")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing[*]}"
        log_info "Please install them and try again."
        exit 1
    fi
    
    # Check for bubblewrap (optional but recommended)
    if ! command -v bwrap &> /dev/null; then
        log_warning "bubblewrap (bwrap) not found. Sandbox will be disabled."
        log_info "For better security, install bubblewrap:"
        log_info "  Ubuntu/Debian: sudo apt install bubblewrap"
        log_info "  Fedora: sudo dnf install bubblewrap"
        log_info "  Arch: sudo pacman -S bubblewrap"
    fi
}

# Get download URL
get_download_url() {
    local version="$1"
    local arch="$2"
    local os="$3"
    
    if [ "$version" = "latest" ]; then
        echo "https://github.com/${GITHUB_REPO}/releases/latest/download/trinity-pptx-runtime-${os}-${arch}.tar.gz"
    else
        echo "https://github.com/${GITHUB_REPO}/releases/download/v${version}/trinity-pptx-runtime-${os}-${arch}.tar.gz"
    fi
}

prepare_install_dir() {
    log_info "Creating installation directory: ${INSTALL_DIR}"
    rm -rf "${INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}"
}

repair_libreoffice_bundle_paths() {
    local install_root="$1"
    local program_dir="${install_root}/lib/libreoffice/program"
    local fundamental_rc="${program_dir}/fundamentalrc"
    local soffice_rc="${program_dir}/sofficerc"

    if [ ! -d "$program_dir" ]; then
        return 0
    fi

    if [ -f "$fundamental_rc" ]; then
        log_info "Repairing LibreOffice bundle metadata for portable runtime paths..."
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

repair_libreoffice_program_compat_symlinks() {
    local install_root="$1"
    local program_dir="${install_root}/lib/libreoffice/program"
    local arch_dir=""
    local src=""
    local base=""
    local dst=""
    local repaired="0"

    if [ ! -d "$program_dir" ]; then
        return 0
    fi

    while IFS= read -r arch_dir; do
        for src in "$program_dir"/*; do
            if [ ! -e "$src" ]; then
                continue
            fi

            base="$(basename "$src")"
            dst="${arch_dir}/${base}"

            if [ -L "$dst" ] && [ ! -e "$dst" ]; then
                rm -f "$dst"
            fi

            if [ -e "$dst" ] || [ -L "$dst" ]; then
                continue
            fi

            ln -s "../libreoffice/program/${base}" "$dst"
            repaired="1"
        done
    done < <(find "${install_root}/lib" -mindepth 1 -maxdepth 1 -type d -name '*-linux-gnu' | sort)

    if [ "$repaired" = "1" ]; then
        log_info "Repairing LibreOffice multi-arch compatibility symlinks..."
    fi
}

repair_wrapper_script() {
    local wrapper_path="$1"
    local add_bin="0"
    local add_usr_bin="0"
    local temp_file=""

    if [ ! -f "$wrapper_path" ]; then
        return 0
    fi

    if ! grep -F -- '--ro-bind /bin /bin' "$wrapper_path" >/dev/null 2>&1; then
        add_bin="1"
    fi
    if ! grep -F -- '--ro-bind /usr/bin /usr/bin' "$wrapper_path" >/dev/null 2>&1; then
        add_usr_bin="1"
    fi

    if [ "$add_bin" = "0" ] && [ "$add_usr_bin" = "0" ]; then
        :
    fi

    if [ "$add_bin" = "1" ] || [ "$add_usr_bin" = "1" ]; then
        log_info "Applying wrapper compatibility repair for older sandbox mounts..."
        temp_file="$(mktemp)"
        awk -v add_bin="$add_bin" -v add_usr_bin="$add_usr_bin" '
            /# Mount system directories for dependencies/ && !patched {
                print
                if (add_bin == "1") {
                    print "    cmd=\"${cmd} --ro-bind /bin /bin\""
                }
                if (add_usr_bin == "1") {
                    print "    cmd=\"${cmd} --ro-bind /usr/bin /usr/bin\""
                }
                patched = 1
                next
            }
            { print }
        ' "$wrapper_path" > "$temp_file"
        mv "$temp_file" "$wrapper_path"
    fi

    # Standalone installs (for example curl | bash) do not have a local wrapper
    # checkout to copy from, so patch the older release wrapper in place with the
    # extra library search paths needed by the bundled LibreOffice runtime.
    sed -i \
        -e 's|--setenv LD_LIBRARY_PATH /runtime/lib:/lib:/lib64|--setenv LD_LIBRARY_PATH /runtime/lib:/runtime/lib/x86_64-linux-gnu:/runtime/lib/aarch64-linux-gnu:/runtime/lib/libreoffice/program:/lib:/lib64|g' \
        -e 's|LD_LIBRARY_PATH="\$RUNTIME_DIR/lib:/lib:/lib64"|LD_LIBRARY_PATH="\$RUNTIME_DIR/lib:\$RUNTIME_DIR/lib/x86_64-linux-gnu:\$RUNTIME_DIR/lib/aarch64-linux-gnu:\$RUNTIME_DIR/lib/libreoffice/program:/lib:/lib64"|g' \
        -e 's|vnd.sun.star.pathname:/runtime/share/libreoffice/program/fundamentalrc|vnd.sun.star.pathname:/runtime/lib/libreoffice/program/fundamentalrc|g' \
        -e 's|vnd.sun.star.pathname:\${RUNTIME_DIR}/share/libreoffice/program/fundamentalrc|vnd.sun.star.pathname:\${RUNTIME_DIR}/lib/libreoffice/program/fundamentalrc|g' \
        "$wrapper_path"
    chmod +x "$wrapper_path"
}

install_runtime_wrapper() {
    local wrapper_path="$1"
    local current_wrapper="${SCRIPT_DIR}/wrapper/trinity-pptx"

    if [ -f "$current_wrapper" ]; then
        log_info "Installing current wrapper script from checkout..."
        cp "$current_wrapper" "$wrapper_path"
        chmod +x "$wrapper_path"
        return
    fi

    repair_wrapper_script "$wrapper_path"
}

create_bin_symlink() {
    log_info "Creating symlink in ${BIN_DIR}..."
    mkdir -p "$BIN_DIR"
    ln -sfn "${INSTALL_DIR}/trinity-pptx" "${BIN_DIR}/trinity-pptx"
}

extract_tarball_into_install_dir() {
    local tarball="$1"

    prepare_install_dir
    log_info "Extracting..."
    tar xzf "$tarball" -C "$INSTALL_DIR"
    install_runtime_wrapper "${INSTALL_DIR}/trinity-pptx"
    repair_libreoffice_bundle_paths "${INSTALL_DIR}"
    repair_libreoffice_program_compat_symlinks "${INSTALL_DIR}"
    log_success "Extraction complete"
}

copy_dist_into_install_dir() {
    local dist_dir="$1"

    prepare_install_dir
    log_info "Copying local runtime bundle..."
    cp -a "${dist_dir}/." "${INSTALL_DIR}/"
    install_runtime_wrapper "${INSTALL_DIR}/trinity-pptx"
    repair_libreoffice_bundle_paths "${INSTALL_DIR}"
    repair_libreoffice_program_compat_symlinks "${INSTALL_DIR}"
    log_success "Local runtime copy complete"
}

find_local_tarball() {
    local arch="$1"
    local os="$2"
    local tarball="${SCRIPT_DIR}/trinity-pptx-runtime-${os}-${arch}.tar.gz"
    if [ -f "$tarball" ]; then
        echo "$tarball"
    fi
}

find_local_install_artifact() {
    local arch="$1"
    local os="$2"
    local tarball
    tarball="$(find_local_tarball "$arch" "$os")"
    if [ -n "$tarball" ]; then
        echo "$tarball"
        return
    fi

    if [ -x "${SCRIPT_DIR}/dist/trinity-pptx" ]; then
        echo "${SCRIPT_DIR}/dist"
        return
    fi
}

install_from_local_source() {
    local arch="$1"
    local os="$2"
    local artifact

    artifact="$(find_local_install_artifact "$arch" "$os")"
    if [ -z "$artifact" ]; then
        log_error "No local runtime artifact is available."
        log_info "Build the runtime first, for example: (cd runtime && ./build.sh)"
        exit 1
    fi

    log_info "Detected platform: ${os}-${arch}"
    if [ -d "$artifact" ]; then
        log_info "Installing from local dist directory: ${artifact}"
        copy_dist_into_install_dir "$artifact"
    else
        log_info "Installing from local tarball: ${artifact}"
        extract_tarball_into_install_dir "$artifact"
    fi
    create_bin_symlink
    log_success "Installation complete!"
}

install_from_release() {
    local arch="$1"
    local os="$2"
    local download_url
    local temp_dir
    local tarball

    download_url=$(get_download_url "$VERSION" "$arch" "$os")
    temp_dir=$(mktemp -d)
    tarball="${temp_dir}/trinity-pptx-runtime.tar.gz"

    log_info "Detected platform: ${os}-${arch}"
    log_info "Version: ${VERSION}"
    log_info "Download URL: ${download_url}"

    log_info "Downloading..."
    if ! curl -fsSL -o "$tarball" "$download_url"; then
        log_error "Failed to download from ${download_url}"
        log_info "Please check that the release exists and you have internet connectivity."
        rm -rf "$temp_dir"
        exit 1
    fi

    if [ ! -f "$tarball" ] || [ ! -s "$tarball" ]; then
        log_error "Downloaded file is empty or missing"
        rm -rf "$temp_dir"
        exit 1
    fi

    log_success "Download complete"
    extract_tarball_into_install_dir "$tarball"
    rm -rf "$temp_dir"
    create_bin_symlink
    log_success "Installation complete!"
}

install_runtime() {
    local arch
    local os

    arch=$(detect_arch)
    os=$(detect_os)

    case "$SOURCE_MODE" in
        local)
            install_from_local_source "$arch" "$os"
            ;;
        release)
            install_from_release "$arch" "$os"
            ;;
        *)
            log_error "Unknown source mode: ${SOURCE_MODE}"
            exit 1
            ;;
    esac
}

# Update shell configuration
update_shell_config() {
    local shell_rc=""
    
    # Detect shell
    if [ -n "${ZSH_VERSION:-}" ] || [ "${SHELL##*/}" = "zsh" ]; then
        shell_rc="${HOME}/.zshrc"
    elif [ -n "${BASH_VERSION:-}" ] || [ "${SHELL##*/}" = "bash" ]; then
        shell_rc="${HOME}/.bashrc"
    else
        shell_rc="${HOME}/.profile"
    fi
    
    # Check if already in PATH
    if [[ ":$PATH:" == *":${BIN_DIR}:"* ]]; then
        log_info "${BIN_DIR} is already in PATH"
        return
    fi
    
    # Add to shell config
    log_info "Adding ${BIN_DIR} to PATH in ${shell_rc}..."
    echo "" >> "$shell_rc"
    echo "# Trinity PPTX Runtime" >> "$shell_rc"
    echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> "$shell_rc"
    
    log_warning "Please run: source ${shell_rc}"
    log_warning "Or restart your terminal to update PATH"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    local python_verify_output=""
    local soffice_verify_output=""
    
    if [ ! -x "${INSTALL_DIR}/trinity-pptx" ]; then
        log_error "Installation verification failed: trinity-pptx not found"
        exit 1
    fi
    
    # Try to run version command
    if "${INSTALL_DIR}/trinity-pptx" --version &> /dev/null; then
        local version=$("${INSTALL_DIR}/trinity-pptx" --version)
        log_success "Installation verified: version ${version}"
    else
        log_warning "Could not verify version, but files are in place"
    fi

    if python_verify_output=$("${INSTALL_DIR}/trinity-pptx" exec python3 -c "import markitdown, PIL" 2>&1); then
        log_success "Python extract dependencies verified"
    else
        log_error "Runtime verification failed: bundled Python dependencies are missing"
        if [ -n "$python_verify_output" ]; then
            echo "$python_verify_output" >&2
        fi
        exit 1
    fi

    if command -v bwrap &> /dev/null; then
        if soffice_verify_output=$("${INSTALL_DIR}/trinity-pptx" exec soffice --headless --version 2>&1); then
            log_success "Sandboxed LibreOffice verified"
        else
            log_error "Runtime verification failed: sandboxed soffice is not executable"
            if printf '%s' "$soffice_verify_output" | grep -F 'DeploymentException' >/dev/null 2>&1; then
                log_error "LibreOffice bootstrap could not resolve packaged UNO/program assets. Rebuild or reinstall with the updated compatibility-symlink repair."
            fi
            if ! find "${INSTALL_DIR}/lib" -maxdepth 4 \( -name 'libGL.so*' -o -path '*/dri/swrast_dri.so' \) -print -quit | grep -q .; then
                log_error "The installed runtime bundle is missing bundled OpenGL/software-rendering files (for example libGL.so.1 and swrast_dri.so). Publish or install a refreshed runtime release after rebuilding with the updated runtime/build.sh."
            fi
            if [ -n "$soffice_verify_output" ]; then
                echo "$soffice_verify_output" >&2
            fi
            exit 1
        fi
    fi
}

# Print usage instructions
print_usage() {
    echo ""
    echo "========================================"
    echo "Trinity PPTX Runtime installed!"
    echo "========================================"
    echo ""
    echo "Usage:"
    echo "  trinity-pptx convert <input.pptx> [output.pdf]  - Convert PPTX to PDF"
    echo "  trinity-pptx extract <input.pptx>               - Extract text from PPTX"
    echo "  trinity-pptx thumbnail <input.pptx> [output]    - Generate thumbnail"
    echo "  trinity-pptx create <script.js> [output.pptx]   - Create PPTX from JS"
    echo "  trinity-pptx --help                             - Show full help"
    echo ""
    echo "Examples:"
    echo "  trinity-pptx convert presentation.pptx"
    echo "  trinity-pptx extract slides.pptx > content.txt"
    echo ""
    echo "For more information:"
    echo "  https://github.com/${GITHUB_REPO}"
    echo ""
}

# Main function
main() {
    echo "========================================"
    echo "Trinity PPTX Runtime Installer"
    echo "========================================"
    echo ""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                VERSION="$2"
                shift 2
                ;;
            --install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --bin-dir)
                BIN_DIR="$2"
                shift 2
                ;;
            --local)
                SOURCE_MODE="local"
                shift
                ;;
            --release)
                SOURCE_MODE="release"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --version <ver>      Install specific version (default: latest)"
                echo "  --install-dir <dir>  Installation directory (default: ~/.local/share/trinity-pptx-runtime)"
                echo "  --bin-dir <dir>      Binary symlink directory (default: ~/.local/bin)"
                echo "  --local              Install from an already-built local artifact"
                echo "  --release            Install from GitHub release (default)"
                echo "  --help               Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check dependencies
    check_deps
    
    # Install
    install_runtime
    
    # Verify
    verify_installation
    
    # Update shell config
    update_shell_config
    
    # Print usage
    print_usage
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
