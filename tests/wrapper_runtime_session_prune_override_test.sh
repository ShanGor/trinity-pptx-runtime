#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WRAPPER="${PROJECT_ROOT}/wrapper/trinity-office"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

runtime_dir="${tmpdir}/runtime"
runtime_parent="${tmpdir}/runtime-state/trinity-office"
stale_session="${runtime_parent}/session.stale"
fresh_session="${runtime_parent}/session.fresh"

mkdir -p \
    "${runtime_dir}/bin" \
    "${runtime_dir}/lib" \
    "${stale_session}" \
    "${fresh_session}"

cat > "${runtime_dir}/bin/python3" << 'INNER'
#!/bin/sh
exec /usr/bin/python3 "$@"
INNER
chmod +x "${runtime_dir}/bin/python3"

touch -d '3 minutes ago' "${stale_session}"
touch -d '30 seconds ago' "${fresh_session}"

XDG_RUNTIME_DIR="${tmpdir}/runtime-state" \
TRINITY_RUNTIME_SESSION_STALE_MINUTES=1 \
TRINITY_NO_SANDBOX=1 \
TRINITY_OFFICE_RUNTIME="${runtime_dir}" \
"${WRAPPER}" exec python3 -c 'print("ok")' >/dev/null

if [ -d "${stale_session}" ]; then
    echo "Expected override stale runtime session to be pruned" >&2
    find "${runtime_parent}" -maxdepth 1 -mindepth 1 -type d | sort >&2
    exit 1
fi

if [ ! -d "${fresh_session}" ]; then
    echo "Expected override fresh runtime session to be preserved" >&2
    find "${runtime_parent}" -maxdepth 1 -mindepth 1 -type d | sort >&2
    exit 1
fi

echo "PASS: runtime session pruning honors TRINITY_RUNTIME_SESSION_STALE_MINUTES"
