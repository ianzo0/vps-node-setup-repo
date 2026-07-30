#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vps-node-state.XXXXXX")"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

STATE_DIR="${TEST_ROOT}/state"
RUN_ID="test-run"
. "${ROOT}/scripts/lib.sh"

file_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

ensure_state_dir
[[ "$(file_mode "${STATE_FILE}")" == 600 ]]
[[ "$(file_mode "${MANIFEST_FILE}")" == 600 ]]

source_file="${TEST_ROOT}/owned.conf"
printf 'before\n' > "${source_file}"
backup_path "${source_file}"
backup_path "${source_file}"
record_created "${source_file}"
record_created "${source_file}"

[[ "$(awk -F '\t' '$1=="BACKUP" {count++} END {print count+0}' "${MANIFEST_FILE}")" == 1 ]]
[[ "$(awk -F '\t' '$1=="CREATED" {count++} END {print count+0}' "${MANIFEST_FILE}")" == 1 ]]

mark_stage test done
stage_is_done test

if STATE_DIR="${TEST_ROOT}/invalid-state" RUN_ID='../invalid' \
  bash -c '. "$1/scripts/lib.sh"' -- "${ROOT}" 2>/dev/null; then
  echo "invalid RUN_ID was accepted" >&2
  exit 1
fi

echo "state helper tests passed"
