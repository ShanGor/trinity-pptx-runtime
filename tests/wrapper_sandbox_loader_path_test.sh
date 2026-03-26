#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WRAPPER="${PROJECT_ROOT}/wrapper/trinity-pptx"

if ! command -v bwrap >/dev/null 2>&1; then
    echo "SKIP: bwrap not available"
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

runtime_dir="${tmpdir}/runtime"
mkdir -p \
    "${runtime_dir}/bin" \
    "${runtime_dir}/lib/x86_64-linux-gnu" \
    "${runtime_dir}/usr/lib/x86_64-linux-gnu" \
    "${runtime_dir}/lib/libreoffice/program"

cat > "${runtime_dir}/bin/soffice" << 'INNER'
#!/bin/sh
echo "${LD_LIBRARY_PATH:-}"
INNER
chmod +x "${runtime_dir}/bin/soffice"

output="$((
    TRINITY_PPTX_RUNTIME="${runtime_dir}" \
    "${WRAPPER}" exec soffice --headless --version
) 2>&1)"

if [[ "$output" != *"/runtime/lib/x86_64-linux-gnu"* ]]; then
    echo "Expected sandbox LD_LIBRARY_PATH to include /runtime/lib/x86_64-linux-gnu" >&2
    echo "Actual: ${output}" >&2
    exit 1
fi

if [[ "$output" != *"/runtime/usr/lib"* ]]; then
    echo "Expected sandbox LD_LIBRARY_PATH to include /runtime/usr/lib" >&2
    echo "Actual: ${output}" >&2
    exit 1
fi

if [[ "$output" != *"/runtime/usr/lib/x86_64-linux-gnu"* ]]; then
    echo "Expected sandbox LD_LIBRARY_PATH to include /runtime/usr/lib/x86_64-linux-gnu" >&2
    echo "Actual: ${output}" >&2
    exit 1
fi

if [[ "$output" != *"/runtime/lib/libreoffice/program"* ]]; then
    echo "Expected sandbox LD_LIBRARY_PATH to include /runtime/lib/libreoffice/program" >&2
    echo "Actual: ${output}" >&2
    exit 1
fi

echo "PASS: sandboxed wrapper preserves runtime loader paths"
