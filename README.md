# Trinity PPTX Runtime

A sandboxed runtime environment for processing PPTX files, designed to work with the Trinity AI Agent platform.

## Overview

This runtime packages all necessary tools for PPTX processing into a single, self-contained bundle:

- **LibreOffice** (soffice) - Convert PPTX to PDF and other formats
- **Python 3** + **markitdown** - Extract text and metadata from PPTX
- **Node.js** + **pptxgenjs** - Create PPTX files programmatically
- **Poppler** (pdftoppm) - Convert PDF pages to images

All tools run inside a [bubblewrap](https://github.com/containers/bubblewrap) sandbox for security.

## Quick Start

### Build Package at local
```bash
export UBUNTU_REPO=http://mirrors.aliyun.com/ubuntu
export PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
bash runtime/build.sh
```

### Installation

```bash
# Download and run the installer
curl -fsSL https://raw.githubusercontent.com/ShanGor/trinity-pptx-runtime/main/install.sh | bash

# Or with a pre-downloaded tarball (useful when GitHub download is slow)
curl -LO https://github.com/ShanGor/trinity-pptx-runtime/releases/latest/download/trinity-pptx-runtime-linux-x64.tar.gz
./install.sh --tarball trinity-pptx-runtime-linux-x64.tar.gz
```

#### Installer Options

| Option | Description |
|--------|-------------|
| `--version <ver>` | Install specific version (default: latest) |
| `--install-dir <dir>` | Installation directory (default: ~/.local/share/trinity-pptx-runtime) |
| `--bin-dir <dir>` | Binary symlink directory (default: ~/.local/bin) |
| `--tarball <path>` | Install from local tarball instead of downloading |
| `--local` | Install from an already-built local artifact |
| `--release` | Install from GitHub release (default) |

`install.sh` downloads the GitHub release by default. If you have already built a local runtime artifact from a source checkout, use `--local` to install that artifact explicitly instead.
When `install.sh` is run from a source checkout, it installs the checked-out `wrapper/trinity-pptx` over the downloaded bundle so wrapper fixes apply immediately. Standalone installs still repair older downloaded wrappers before runtime verification, including the extra sandbox mounts and bundled-library search paths needed by LibreOffice.
The wrapper now searches runtime loader paths under both `lib` and `usr/lib` multi-arch roots, so legacy bundles that place LibreOffice dependencies under `usr/lib/*-linux-gnu` (for example `libgpgmepp.so.6`) can still start `soffice` successfully.
The installer and build now also repair LibreOffice program compatibility entries inside `lib/*-linux-gnu`, because some bundled UNO/bootstrap assets are resolved from those multi-arch roots during `soffice` startup.
The installer also rewrites LibreOffice bootstrap metadata inside the bundle to use bundle-relative program/config paths while keeping `UserInstallation` on the writable per-user profile path instead of inside the read-only runtime mount.
The build and installer also rewrite LibreOffice share-tree symlinks that normally point at `/etc` or `/var`, so the portable bundle no longer depends on host paths such as `/etc/libreoffice/registry` or `/var/spool/libreoffice/uno_packages/cache`.
If an older release bundle still lacks bundled software-rendering files such as `libGL.so.1` and `swrast_dri.so`, the installer now reports that explicitly so you can rebuild and publish a refreshed release artifact instead of chasing a generic `soffice` failure.

### Usage

```bash
# Convert PPTX to PDF
trinity-pptx convert presentation.pptx output.pdf

# Extract text content
trinity-pptx extract presentation.pptx

# Generate thumbnail preview
trinity-pptx thumbnail presentation.pptx preview.jpg

# Create PPTX from JavaScript
trinity-pptx create my-script.js output.pptx

# Execute arbitrary command in sandbox
trinity-pptx exec python3 -m markitdown presentation.pptx
```

## Commands

### `convert <input.pptx> [output.pdf]`

Convert a PPTX file to PDF format.

```bash
trinity-pptx convert slides.pptx
trinity-pptx convert slides.pptx output.pdf
```

### `extract <input.pptx>`

Extract text content from a PPTX file using markitdown.

```bash
trinity-pptx extract presentation.pptx
trinity-pptx extract presentation.pptx > content.md
```

### `thumbnail <input.pptx> [output.jpg]`

Generate a thumbnail image from the first slide.

```bash
trinity-pptx thumbnail deck.pptx
trinity-pptx thumbnail deck.pptx preview.jpg
```

### `create <script.js> [output.pptx]`

Create a PPTX file from a JavaScript file using pptxgenjs.

Example script (`my-presentation.js`):
```javascript
const pptx = new PptxGenJS();
const slide = pptx.addSlide();
slide.addText("Hello World!", { x: 1, y: 1, fontSize: 44 });
pptx.writeFile({ fileName: process.argv[3] || "output.pptx" });
```

```bash
trinity-pptx create my-presentation.js
```

### `exec <command> [args...]`

Execute an arbitrary command inside the sandboxed environment.

```bash
trinity-pptx exec python3 --version
trinity-pptx exec node --version
trinity-pptx exec soffice --headless --convert-to pdf input.docx
```

## Options

- `--no-sandbox` - Disable bubblewrap sandbox (not recommended)
- `--work-dir <dir>` - Set working directory for input/output files
- `--verbose` - Enable verbose output
- `-h, --help` - Show help message
- `-v, --version` - Show version information

## Environment Variables

- `TRINITY_PPTX_RUNTIME` - Path to runtime directory (overrides auto-detect)
- `TRINITY_NO_SANDBOX` - Set to `"1"` to disable sandbox
- `TRINITY_BWRAP_OPTS` - Additional bubblewrap options

## Building from Source

### Prerequisites

- Linux system (Ubuntu 22.04+ recommended)
- `debootstrap` (for native build) or Docker
- `curl`, `tar`, `xz-utils`
- Root access (for debootstrap/chroot)

### Build Options

#### Option 1: Local Build (Native)

Requires root access for `debootstrap` and `chroot`:

```bash
# Clone the repository
git clone https://github.com/ShanGor/trinity-pptx-runtime.git
cd trinity-pptx-runtime

# Install build dependencies
sudo apt-get update
sudo apt-get install -y debootstrap curl binutils xz-utils

# Build the runtime
cd runtime
sudo ./build.sh

# Output: trinity-pptx-runtime-linux-x64.tar.gz
```

**What the build script does:**
1. Creates a minimal Ubuntu rootfs using `debootstrap`
2. Installs required packages (LibreOffice, Python, Node.js, Poppler, fonts)
3. Installs Python packages (markitdown[pptx], Pillow) into the bundled runtime
4. Installs Node.js packages (pptxgenjs)
5. Packages both `/usr` and `/usr/local` runtime assets needed by the tools
6. Verifies the packaged artifact can import `markitdown` and `pptxgenjs`, and when `bwrap` is usable also verifies sandboxed `soffice --headless --version`
7. Optimizes by removing unnecessary files (docs, man pages, caches)

#### Option 2: GitHub Actions (Recommended)

Automatically builds for both x64 and arm64 architectures:

**Trigger via git tag:**
```bash
git tag v1.0.0
git push origin v1.0.0
```

**Or trigger manually:**
1. Go to GitHub repository → Actions → "Release PPTX Runtime"
2. Click "Run workflow"
3. Enter version number (e.g., `1.0.0`)
4. Click "Run workflow"

The workflow will:
- Build for `linux/x64` (Ubuntu latest)
- Build for `linux/arm64` (Ubuntu ARM runner)
- Create a GitHub Release with both packages
- Generate checksums
- Update the `latest` tag

#### Option 3: Docker Build (No Root Required)

If you don't have root access or want an isolated build:

```bash
# Clone the repository
git clone https://github.com/ShanGor/trinity-pptx-runtime.git
cd trinity-pptx-runtime

# Build using Docker
docker run --rm -v $(pwd):/workspace -w /workspace ubuntu:22.04 \
  bash -c "
    apt-get update && \
    apt-get install -y debootstrap curl binutils xz-utils && \
    cd runtime && \
    ./build.sh
  "

# Output: trinity-pptx-runtime-linux-x64.tar.gz
```

### Build Output

All methods produce the same output structure:

```
trinity-pptx-runtime-linux-x64.tar.gz (or -arm64.tar.gz)
├── bin/                    # Binaries (soffice, python3, node, pdftoppm, etc.)
├── lib/                    # Shared libraries
├── share/                  # Data files (fonts, LibreOffice config)
├── trinity-pptx           # Main entry script
└── VERSION                # Version information
```

**Estimated size:** ~300-500 MB (includes full LibreOffice suite)

## Architecture

```
trinity-pptx-runtime/
├── bin/                    # Binaries (soffice, python3, node, etc.)
├── lib/                    # Shared libraries
├── share/                  # Data files (fonts, LibreOffice config)
├── trinity-pptx           # Main entry script
└── VERSION                # Version information
```

The runtime uses [bubblewrap](https://github.com/containers/bubblewrap) to create a minimal sandbox:

- Read-only access to the runtime files
- No access to host system (except specified work directory)
- Temporary filesystem for /tmp and /home
- Network access enabled (for potential future use)

## Security

The sandbox provides defense in depth:

1. **Filesystem isolation** - Only the runtime and specified work directory are accessible
2. **No privileged access** - Runs as unprivileged user
3. **Minimal attack surface** - Only necessary tools included
4. **Network isolation ready** - Can be disabled with `--unshare-net`

For maximum security, ensure bubblewrap is installed and the kernel has user namespaces enabled.

## Integration with Trinity

Trinity can automatically detect and use this runtime:

1. **Auto-detect local development**: Check `../trinity-pptx-runtime/`
2. **Check user installation**: `~/.local/share/trinity-pptx-runtime/`
3. **Download on demand**: Fetch from GitHub Releases if not found

Example detection logic:

```python
def find_pptx_runtime():
    # Priority order
    paths = [
        os.environ.get("TRINITY_PPTX_RUNTIME"),
        "../trinity-pptx-runtime",  # Local dev
        os.path.expanduser("~/.local/share/trinity-pptx-runtime"),
        "/opt/trinity-pptx-runtime",
    ]
    
    for path in paths:
        if path and os.path.exists(f"{path}/trinity-pptx"):
            return path
    
    return None
```

## License

[MIT License](LICENSE)

## Contributing

Contributions are welcome! Please open an issue or pull request on GitHub.

## Support

- GitHub Issues: https://github.com/ShanGor/trinity-pptx-runtime/issues
- Trinity Documentation: https://github.com/your-org/trinity/docs
