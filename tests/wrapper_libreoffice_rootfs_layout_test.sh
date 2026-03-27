#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WRAPPER="${PROJECT_ROOT}/wrapper/trinity-pptx"

if ! command -v bwrap >/dev/null 2>&1; then
    echo "SKIP: bwrap not available"
    exit 0
fi

if ! bwrap --ro-bind / / --dev /dev --proc /proc /bin/true >/dev/null 2>&1; then
    echo "SKIP: bwrap not available"
    exit 0
fi

copy_binary_with_deps() {
    local binary="$1"
    local rootfs="$2"
    local dep=""

    mkdir -p "${rootfs}$(dirname "$binary")"
    cp "$binary" "${rootfs}${binary}"

    while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        mkdir -p "${rootfs}$(dirname "$dep")"
        cp "$dep" "${rootfs}${dep}"
    done < <(ldd "$binary" | awk '{for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i}')
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

runtime_dir="${tmpdir}/runtime"
mkdir -p \
    "${runtime_dir}/rootfs/usr/bin" \
    "${runtime_dir}/rootfs/usr/lib/libreoffice" \
    "${runtime_dir}/rootfs/usr/share" \
    "${runtime_dir}/rootfs/etc/libreoffice" \
    "${runtime_dir}/rootfs/var/lib/libreoffice" \
    "${runtime_dir}/rootfs/var/spool/libreoffice"

copy_binary_with_deps /bin/sh "${runtime_dir}/rootfs"

cat > "${runtime_dir}/rootfs/usr/bin/soffice" << 'INNER'
#!/bin/sh
printf '%s\n' "$0"
if [ -d /usr/lib ] && [ -d /usr/share ] && [ -d /etc/libreoffice ] && [ -d /var/lib/libreoffice ]; then
    echo "FHS_OK"
fi
INNER
chmod +x "${runtime_dir}/rootfs/usr/bin/soffice"

ln -s rootfs/usr/bin "${runtime_dir}/bin"
ln -s rootfs/usr/lib "${runtime_dir}/lib"

output="$(
    TRINITY_PPTX_RUNTIME="${runtime_dir}" \
    "${WRAPPER}" exec soffice --headless --version
)"

if [[ "$output" != *"/usr/bin/soffice"* ]]; then
    echo "Expected wrapper to execute LibreOffice from the bundled /usr/bin path" >&2
    echo "Actual: ${output}" >&2
    exit 1
fi

if [[ "$output" != *"FHS_OK"* ]]; then
    echo "Expected wrapper to expose bundled /usr, /etc, and /var LibreOffice paths" >&2
    echo "Actual: ${output}" >&2
    exit 1
fi

echo "PASS: wrapper runs soffice inside the bundled rootfs layout"
