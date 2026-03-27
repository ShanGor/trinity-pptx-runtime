#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALL_SCRIPT="${PROJECT_ROOT}/install.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

runtime_dir="${tmpdir}/runtime"
program_dir="${runtime_dir}/rootfs/usr/lib/libreoffice/program"
mkdir -p \
    "${runtime_dir}/rootfs/usr/bin" \
    "${runtime_dir}/rootfs/etc/libreoffice" \
    "${program_dir}"

cat > "${runtime_dir}/rootfs/usr/bin/soffice" << 'INNER'
#!/bin/sh
exit 0
INNER
chmod +x "${runtime_dir}/rootfs/usr/bin/soffice"

cat > "${program_dir}/fundamentalrc" << 'INNER'
[Bootstrap]
BRAND_BASE_DIR=file:///usr/lib/libreoffice
CONFIGURATION_LAYERS=xcsxcu:file:///etc/libreoffice/registry
URE_MORE_JAVA_CLASSPATH_URLS=file:///usr/share/java/hsqldb1.8.0.jar
INNER

cat > "${program_dir}/sofficerc" << 'INNER'
FHS_CONFIG_FILE=file:///etc/libreoffice/sofficerc
INNER

# shellcheck source=/dev/null
source "${INSTALL_SCRIPT}"
finalize_libreoffice_runtime_layout "${runtime_dir}"

if ! grep -F 'file:///etc/libreoffice/registry' "${program_dir}/fundamentalrc" >/dev/null; then
    echo "Expected preserved rootfs bundle to keep the original /etc LibreOffice registry path" >&2
    exit 1
fi

if grep -F 'file://${ORIGIN}/../../../etc/libreoffice/registry' "${program_dir}/fundamentalrc" >/dev/null; then
    echo "Did not expect preserved rootfs bundle to be rewritten to flat-bundle registry paths" >&2
    exit 1
fi

if ! grep -F 'file:///etc/libreoffice/sofficerc' "${program_dir}/sofficerc" >/dev/null; then
    echo "Expected preserved rootfs bundle to keep the original /etc LibreOffice sofficerc path" >&2
    exit 1
fi

echo "PASS: install.sh preserves rootfs-based LibreOffice bundle metadata"
