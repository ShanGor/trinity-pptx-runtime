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
Thumbnail Fallback
EOF
    exit 0
fi

exec /usr/bin/python3 "$@"
INNER
chmod +x "${runtime_dir}/bin/python3"

cat > "${runtime_dir}/bin/pdftoppm" << 'INNER'
#!/bin/sh
set -eu

input=""
output_prefix=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -jpeg|-singlefile)
            shift
            ;;
        -r|-f|-l)
            shift 2
            ;;
        *)
            if [ -z "$input" ]; then
                input="$1"
            else
                output_prefix="$1"
            fi
            shift
            ;;
    esac
done

if [ ! -f "$input" ]; then
    echo "Expected pdftoppm input PDF to exist" >&2
    exit 1
fi

printf '%s\n' 'fake jpeg' > "${output_prefix}.jpg"
INNER
chmod +x "${runtime_dir}/bin/pdftoppm"

printf 'fake pptx' > "${work_dir}/demo.pptx"

(
    cd "${work_dir}"
    TRINITY_NO_SANDBOX=1 \
    TRINITY_PPTX_RUNTIME="${runtime_dir}" \
    "${WRAPPER}" thumbnail demo.pptx preview.jpg
)

if [ ! -f "${work_dir}/preview.jpg" ]; then
    echo "Expected thumbnail fallback to create preview.jpg" >&2
    ls -la "${work_dir}" >&2
    exit 1
fi

if [ -f "${work_dir}/demo.pdf" ]; then
    echo "Expected thumbnail fallback to remove the intermediate PDF" >&2
    ls -la "${work_dir}" >&2
    exit 1
fi

echo "PASS: thumbnail falls back to extracted-text PDF when soffice fails"
