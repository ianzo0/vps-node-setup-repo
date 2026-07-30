#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vps-node-state.XXXXXX")"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

STATE_DIR="${TEST_ROOT}/state"
RUN_ID="test-run"
. "${ROOT}/scripts/lib.sh"

ensure_state_dir
[[ "$(stat -f '%Lp' "${STATE_FILE}" 2>/dev/null || stat -c '%a' "${STATE_FILE}")" == 600 ]]
[[ "$(stat -f '%Lp' "${MANIFEST_FILE}" 2>/dev/null || stat -c '%a' "${MANIFEST_FILE}")" == 600 ]]

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

echo "state helper tests passed"
