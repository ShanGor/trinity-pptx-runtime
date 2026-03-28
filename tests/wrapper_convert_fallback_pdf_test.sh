#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WRAPPER="${PROJECT_ROOT}/wrapper/trinity-pptx"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

runtime_dir="${tmpdir}/runtime"
work_dir="${tmpdir}/work"
mkdir -p \
    "${runtime_dir}/bin" \
    "${runtime_dir}/lib/libreoffice/program" \
    "${work_dir}"

cat > "${runtime_dir}/bin/soffice" << 'INNER'
#!/bin/sh
exit 1
INNER
chmod +x "${runtime_dir}/bin/soffice"

cat > "${runtime_dir}/bin/python3" << 'INNER'
#!/bin/sh
if [ "${1:-}" = "-c" ]; then
    cat <<'EOF'
<!-- Slide number: 1 -->
Fallback Title

- Bullet one
- Bullet two
EOF
    exit 0
fi

exec /usr/bin/python3 "$@"
INNER
chmod +x "${runtime_dir}/bin/python3"

printf 'fake pptx' > "${work_dir}/demo.pptx"

(
    cd "${work_dir}"
    TRINITY_NO_SANDBOX=1 \
    TRINITY_PPTX_RUNTIME="${runtime_dir}" \
    "${WRAPPER}" convert demo.pptx output.pdf
)

if [ ! -f "${work_dir}/output.pdf" ]; then
    echo "Expected convert fallback to create output.pdf" >&2
    ls -la "${work_dir}" >&2
    exit 1
fi

if ! head -c 8 "${work_dir}/output.pdf" | grep -F '%PDF-1.4' >/dev/null; then
    echo "Expected fallback output to be a PDF file" >&2
    exit 1
fi

if ! strings "${work_dir}/output.pdf" | grep -F 'Fallback Title' >/dev/null; then
    echo "Expected fallback PDF to include extracted slide text" >&2
    exit 1
fi

echo "PASS: convert falls back to extracted-text PDF when soffice fails"
