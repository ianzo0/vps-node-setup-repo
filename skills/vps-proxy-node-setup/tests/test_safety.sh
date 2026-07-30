#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vps-node-safety.XXXXXX")"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

STATE_DIR="${TEST_ROOT}/state"
RUN_ID="test-run"
. "${ROOT}/scripts/deploy.sh"

ensure_state_dir
mark_stage rollback done
printf 'old manifest\n' > "${MANIFEST_FILE}"
printf 'old preflight\n' > "${REPORT_FILE}"
archive_rolled_back_state
[[ ! -e "${STATE_FILE}" ]]
[[ -f "${STATE_DIR}/history/${RUN_ID}/state.json" ]]
[[ -f "${STATE_DIR}/history/${RUN_ID}/manifest.txt" ]]
[[ -d "${BACKUP_DIR}/${RUN_ID}" ]]

validate_settings
is_owned_path /etc/sing-box/config.json
is_owned_path /var/lib/vps-node-setup/public/subscription.txt
is_owned_path /var/lib/vps-node-setup/fail2ban.before
! is_owned_path /etc/passwd
! is_owned_path /var/lib/vps-node-setup/../../etc/passwd
is_owned_dir /etc/sing-box
is_owned_dir /etc/vps-node-setup
! is_owned_dir /etc

is_ipv4 127.0.0.1
is_ipv4 255.255.255.255
! is_ipv4 256.1.1.1
! is_ipv4 '1.2.3.4 injected'

if (PORT_REALITY=0; validate_settings >/dev/null 2>&1); then
  echo "invalid port was accepted" >&2
  exit 1
fi

echo "safety tests passed"
