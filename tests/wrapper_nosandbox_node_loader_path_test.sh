#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WRAPPER="${PROJECT_ROOT}/wrapper/trinity-office"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

runtime_dir="${tmpdir}/runtime"
mkdir -p \
    "${runtime_dir}/bin" \
    "${runtime_dir}/lib/x86_64-linux-gnu" \
    "${runtime_dir}/usr/lib/x86_64-linux-gnu"

cat > "${runtime_dir}/bin/node" << 'INNER'
#!/bin/sh
echo "${LD_LIBRARY_PATH:-}"
INNER
chmod +x "${runtime_dir}/bin/node"

if command -v unshare &> /dev/null && command -v chroot &> /dev/null; then
    echo "SKIP: unshare/chroot available, cannot test ld-linux fallback for LD_LIBRARY_PATH"
    exit 0
fi

output="$(
    TRINITY_NO_SANDBOX=1 \
    TRINITY_OFFICE_RUNTIME="${runtime_dir}" \
    "${WRAPPER}" exec node -e "process.exit(0)"
)"

if [[ "$output" != *"${runtime_dir}/lib"* ]]; then
    echo "Expected LD_LIBRARY_PATH to include ${runtime_dir}/lib for bundled node" >&2
    echo "Actual: ${output}" >&2
    exit 1
fi

if [[ "$output" != *"${runtime_dir}/usr/lib/x86_64-linux-gnu"* ]]; then
    echo "Expected LD_LIBRARY_PATH to include ${runtime_dir}/usr/lib/x86_64-linux-gnu for bundled node" >&2
    echo "Actual: ${output}" >&2
    exit 1
fi

echo "PASS: wrapper includes runtime loader paths for node without sandbox"
