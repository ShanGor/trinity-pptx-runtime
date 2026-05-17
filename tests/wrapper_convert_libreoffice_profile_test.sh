#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WRAPPER="${PROJECT_ROOT}/wrapper/trinity-office"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

runtime_dir="${tmpdir}/runtime"
work_dir="${tmpdir}/work"
mkdir -p \
    "${runtime_dir}/bin" \
    "${runtime_dir}/lib/libreoffice/program" \
    "${work_dir}"

cat > "${runtime_dir}/bin/soffice" << 'INNER'
#!/bin/bash
set -euo pipefail

outdir=""
input=""
args_file="${TRINITY_TEST_SOFFICE_ARGS:?}"
printf '%s\n' "$@" > "$args_file"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --outdir)
            outdir="$2"
            shift 2
            ;;
        *)
            input="$1"
            shift
            ;;
    esac
done

if [ -z "$outdir" ] || [ -z "$input" ]; then
    echo "missing outdir or input" >&2
    exit 1
fi

name="$(basename "$input")"
stem="${name%.*}"
printf '%s\n' '%PDF-1.4' > "${outdir}/${stem}.pdf"
INNER
chmod +x "${runtime_dir}/bin/soffice"

printf 'fake pptx' > "${work_dir}/demo.pptx"

args_file="${tmpdir}/soffice-args.txt"
(
    cd "${work_dir}"
    TRINITY_NO_SANDBOX=1 \
    TRINITY_OFFICE_RUNTIME="${runtime_dir}" \
    TRINITY_TEST_SOFFICE_ARGS="${args_file}" \
    "${WRAPPER}" convert demo.pptx output.pdf
)

for expected in \
    "--headless" \
    "--invisible" \
    "--nodefault" \
    "--nofirststartwizard" \
    "--nolockcheck" \
    "--norestore"
do
    if ! grep -Fx -- "$expected" "$args_file" >/dev/null; then
        echo "Expected LibreOffice convert arg: $expected" >&2
        cat "$args_file" >&2
        exit 1
    fi
done

if ! grep -E '^[-]env:UserInstallation=file://.*/trinity-office/session\.[A-Za-z0-9]+/home/libreoffice-profile$' "$args_file" >/dev/null; then
    echo "Expected LibreOffice convert to use a unique runtime session UserInstallation path" >&2
    cat "$args_file" >&2
    exit 1
fi

if [ ! -f "${work_dir}/output.pdf" ]; then
    echo "Expected convert to create output.pdf" >&2
    exit 1
fi

echo "PASS: convert uses an isolated LibreOffice profile and noninteractive flags"
