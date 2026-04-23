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
    "${runtime_dir}/rootfs/usr/local/lib/node_modules" \
    "${runtime_dir}/share/nodejs"

cat > "${runtime_dir}/bin/node" << 'INNER'
#!/bin/sh
echo "${NODE_PATH:-}"
INNER
chmod +x "${runtime_dir}/bin/node"

if command -v unshare &> /dev/null && command -v chroot &> /dev/null; then
    echo "SKIP: unshare/chroot available, cannot test ld-linux fallback for NODE_PATH"
    exit 0
fi

output="$(
    TRINITY_NO_SANDBOX=1 \
    TRINITY_OFFICE_RUNTIME="${runtime_dir}" \
    "${WRAPPER}" exec node -e "process.exit(0)"
)"

if [[ "$output" != *"${runtime_dir}/rootfs/usr/local/lib/node_modules"* ]]; then
    echo "Expected NODE_PATH to include ${runtime_dir}/rootfs/usr/local/lib/node_modules" >&2
    echo "Actual: ${output}" >&2
    exit 1
fi

if [[ "$output" != *"${runtime_dir}/share/nodejs"* ]]; then
    echo "Expected NODE_PATH to include ${runtime_dir}/share/nodejs" >&2
    echo "Actual: ${output}" >&2
    exit 1
fi

echo "PASS: wrapper includes global npm and distro node module paths without sandbox"
