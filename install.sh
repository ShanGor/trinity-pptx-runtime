#!/bin/bash
#
# Trinity PPTX Runtime - Installation Script
# Downloads and installs the latest release
#

set -euo pipefail

# Configuration
REPO="trinity-pptx-runtime"
GITHUB_REPO="ShanGor/${REPO}"
INSTALL_DIR="${HOME}/.local/share/trinity-pptx-runtime"
BIN_DIR="${HOME}/.local/bin"
VERSION="${VERSION:-latest}"

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

# Download and install
download_and_install() {
    local arch=$(detect_arch)
    local os=$(detect_os)
    local download_url=$(get_download_url "$VERSION" "$arch" "$os")
    local temp_dir=$(mktemp -d)
    local tarball="${temp_dir}/trinity-pptx-runtime.tar.gz"
    
    log_info "Detected platform: ${os}-${arch}"
    log_info "Version: ${VERSION}"
    log_info "Download URL: ${download_url}"
    
    # Download
    log_info "Downloading..."
    if ! curl -fsSL -o "$tarball" "$download_url"; then
        log_error "Failed to download from ${download_url}"
        log_info "Please check that the release exists and you have internet connectivity."
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Verify download
    if [ ! -f "$tarball" ] || [ ! -s "$tarball" ]; then
        log_error "Downloaded file is empty or missing"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    log_success "Download complete"
    
    # Create install directory
    log_info "Creating installation directory: ${INSTALL_DIR}"
    mkdir -p "$INSTALL_DIR"
    
    # Extract
    log_info "Extracting..."
    tar xzf "$tarball" -C "$INSTALL_DIR"
    rm -rf "$temp_dir"
    
    log_success "Extraction complete"
    
    # Create symlink in bin directory
    log_info "Creating symlink in ${BIN_DIR}..."
    mkdir -p "$BIN_DIR"
    
    if [ -L "${BIN_DIR}/trinity-pptx" ]; then
        rm "${BIN_DIR}/trinity-pptx"
    fi
    
    ln -s "${INSTALL_DIR}/trinity-pptx" "${BIN_DIR}/trinity-pptx"
    
    log_success "Installation complete!"
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
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --version <ver>      Install specific version (default: latest)"
                echo "  --install-dir <dir>  Installation directory (default: ~/.local/share/trinity-pptx-runtime)"
                echo "  --bin-dir <dir>      Binary symlink directory (default: ~/.local/bin)"
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
    
    # Download and install
    download_and_install
    
    # Verify
    verify_installation
    
    # Update shell config
    update_shell_config
    
    # Print usage
    print_usage
}

main "$@"
