#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd -- "${ROOT}/../.." && pwd)"

bash -n "${ROOT}/scripts/lib.sh" "${ROOT}/scripts/deploy.sh" \
  "${ROOT}/templates/vps-node-firewall.sh"
python3 -m json.tool "${ROOT}/references/version-manifest.json" >/dev/null
python3 -m json.tool "${ROOT}/templates/sing-box.json.template" >/dev/null
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/vps-node-setup-pycache" \
  python3 -m py_compile "${ROOT}/templates/subscription-server.py"

jq -e '.sing_box.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' \
  "${ROOT}/references/version-manifest.json" >/dev/null
jq -e '.sing_box.artifacts.amd64.sha256 | test("^[0-9a-f]{64}$")' \
  "${ROOT}/references/version-manifest.json" >/dev/null
jq -e '.sing_box.artifacts.arm64.sha256 | test("^[0-9a-f]{64}$")' \
  "${ROOT}/references/version-manifest.json" >/dev/null

grep -q -- '--token-file' "${ROOT}/scripts/deploy.sh"
! grep -qE 'ExecStart=.*--token[[:space:]]' "${ROOT}/scripts/deploy.sh"
grep -q 'curl -fsS --connect-timeout 5 --config -' "${ROOT}/scripts/deploy.sh"
grep -q 'invalid RUN_ID' "${ROOT}/scripts/lib.sh"
grep -q '"level": "warn"' "${ROOT}/templates/sing-box.json.template"
grep -q "grep -q '^vless://'" "${ROOT}/scripts/deploy.sh"
grep -q "grep -q '^hysteria2://'" "${ROOT}/scripts/deploy.sh"
grep -q 'snapshot_fail2ban_state' "${ROOT}/scripts/deploy.sh"
grep -q 'restore_fail2ban_state' "${ROOT}/scripts/deploy.sh"
grep -q 'fail2ban.before' "${ROOT}/scripts/deploy.sh"
grep -q 'python3-systemd' "${ROOT}/scripts/deploy.sh"
grep -q 'backend = systemd' "${ROOT}/scripts/deploy.sh"
grep -q 'fail2ban did not start' "${ROOT}/scripts/deploy.sh"
grep -q 'archive_rolled_back_state' "${ROOT}/scripts/deploy.sh"
grep -q 'external_client_test_required' "${ROOT}/scripts/deploy.sh"
grep -q 'provider_firewall_required' "${ROOT}/scripts/deploy.sh"
grep -q 'create_owned_dir' "${ROOT}/scripts/deploy.sh"
grep -q 'CREATED_DIR' "${ROOT}/scripts/deploy.sh"
grep -q '^resume()' "${ROOT}/scripts/deploy.sh"
grep -q 'resume=verified' "${ROOT}/scripts/deploy.sh"
grep -qx 'RWRvdJt+t7f7UwEUivaioOMuosD2mHFKbLTIvZtngAY3xyEoyAUzQTdD' \
  "${REPO_ROOT}/MINISIGN-PUBLIC-KEY.txt"
grep -q 'minisign -Sm public/vps-node-setup.tar.gz' \
  "${REPO_ROOT}/.github/workflows/publish-download.yml"

"${ROOT}/tests/test_state.sh"
"${ROOT}/tests/test_safety.sh"

echo "static tests passed"
