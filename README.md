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

### Installation

```bash
# Download and run the installer
curl -fsSL https://raw.githubusercontent.com/your-org/trinity-pptx-runtime/main/install.sh | bash

# Or download manually
curl -LO https://github.com/your-org/trinity-pptx-runtime/releases/latest/download/trinity-pptx-runtime-linux-x64.tar.gz
tar xzf trinity-pptx-runtime-linux-x64.tar.gz -C ~/.local/share/trinity-pptx-runtime
export PATH="$HOME/.local/share/trinity-pptx-runtime:$PATH"
```

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
- `debootstrap` or Docker
- `curl`, `tar`, `gcc`

### Build

```bash
# Clone the repository
git clone https://github.com/your-org/trinity-pptx-runtime.git
cd trinity-pptx-runtime

# Build the runtime
cd runtime
./build.sh

# Output: trinity-pptx-runtime-linux-x64.tar.gz
```

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

- GitHub Issues: https://github.com/your-org/trinity-pptx-runtime/issues
- Trinity Documentation: https://github.com/your-org/trinity/docs
