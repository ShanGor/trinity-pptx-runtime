#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_SCRIPT="${PROJECT_ROOT}/runtime/build.sh"

# shellcheck source=/dev/null
source "${BUILD_SCRIPT}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

DIST_DIR="${tmpdir}/dist"
capture_file="${tmpdir}/capture.txt"
mkdir -p "$DIST_DIR"

cat > "${DIST_DIR}/trinity-pptx" << 'INNER'
#!/bin/sh
printf '%s\n' "$*" > "${CAPTURE_FILE}"

if [ "${1:-}" != "exec" ] || [ "${2:-}" != "python3" ] || [ "${3:-}" != "-c" ]; then
    exit 1
fi

case "${4:-}" in
    *markitdown_no_magika*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
INNER
chmod +x "${DIST_DIR}/trinity-pptx"

export CAPTURE_FILE="${capture_file}"
verify_markitdown_runtime

if ! grep -F "markitdown_no_magika" "${capture_file}" >/dev/null; then
    echo "Expected verify_markitdown_runtime to probe the markitdown_no_magika module" >&2
    cat "${capture_file}" >&2
    exit 1
fi

echo "PASS: runtime/build.sh verifies the bundled MarkItDown module name"
