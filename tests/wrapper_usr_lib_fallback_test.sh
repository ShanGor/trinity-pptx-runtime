#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WRAPPER="${PROJECT_ROOT}/wrapper/trinity-pptx"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

runtime_dir="${tmpdir}/runtime"
mkdir -p \
    "${runtime_dir}/bin" \
    "${runtime_dir}/usr/lib/x86_64-linux-gnu" \
    "${runtime_dir}/lib/libreoffice/program"

cat > "${runtime_dir}/bin/soffice" << 'INNER'
#!/bin/sh
echo "${LD_LIBRARY_PATH:-}"
INNER
chmod +x "${runtime_dir}/bin/soffice"

output="$(
    TRINITY_NO_SANDBOX=1 \
    TRINITY_PPTX_RUNTIME="${runtime_dir}" \
    "${WRAPPER}" exec soffice --headless --version
)"

if [[ "$output" != *"${runtime_dir}/usr/lib"* ]]; then
    echo "Expected LD_LIBRARY_PATH to include ${runtime_dir}/usr/lib" >&2
    echo "Actual: ${output}" >&2
    exit 1
fi

if [[ "$output" != *"${runtime_dir}/usr/lib/x86_64-linux-gnu"* ]]; then
    echo "Expected LD_LIBRARY_PATH to include ${runtime_dir}/usr/lib/x86_64-linux-gnu" >&2
    echo "Actual: ${output}" >&2
    exit 1
fi

echo "PASS: wrapper includes usr/lib fallback paths for soffice"
