#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STATE_DIR="${STATE_DIR:-/var/lib/vps-node-setup}"
BACKUP_DIR="${STATE_DIR}/backups"
STATE_FILE="${STATE_DIR}/state.json"
MANIFEST_FILE="${STATE_DIR}/manifest.txt"
REPORT_FILE="${STATE_DIR}/preflight.txt"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need_root() {
  [[ "${EUID}" -eq 0 ]] || die "run this script as root"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

ensure_state_dir() {
  install -d -m 0700 "${STATE_DIR}" "${BACKUP_DIR}/${RUN_ID}"
  touch "${MANIFEST_FILE}"
  chmod 0600 "${MANIFEST_FILE}"
  if [[ ! -e "${STATE_FILE}" ]]; then
    printf '{"schema":1,"skill":"vps-proxy-node-setup","run_id":"%s","stages":{}}\n' \
      "${RUN_ID}" > "${STATE_FILE}"
    chmod 0600 "${STATE_FILE}"
  fi
}

mark_stage() {
  local stage="$1" status="$2"
  need_cmd jq
  local tmp
  tmp="$(mktemp "${STATE_DIR}/state.XXXXXX")"
  jq --arg s "${stage}" --arg v "${status}" \
    '.stages[$s]=$v | .updated_at=(now|todateiso8601)' \
    "${STATE_FILE}" > "${tmp}"
  chmod 0600 "${tmp}"
  mv -f "${tmp}" "${STATE_FILE}"
}

stage_is_done() {
  local stage="$1"
  [[ -f "${STATE_FILE}" ]] && jq -e --arg s "${stage}" \
    '.stages[$s]=="done"' "${STATE_FILE}" >/dev/null 2>&1
}

backup_path() {
  local path="$1"
  [[ -e "${path}" ]] || return 0
  if awk -F '\t' -v p="${path}" '$1=="BACKUP" && $2==p {found=1} END {exit !found}' \
    "${MANIFEST_FILE}" 2>/dev/null; then
    return 0
  fi
  local safe
  safe="$(printf '%s' "${path}" | sed 's#^/##; s#[^A-Za-z0-9_.-]#_#g')"
  cp -a "${path}" "${BACKUP_DIR}/${RUN_ID}/${safe}"
  printf 'BACKUP\t%s\t%s\n' "${path}" "${BACKUP_DIR}/${RUN_ID}/${safe}" >> "${MANIFEST_FILE}"
}

record_created() {
  if awk -F '\t' -v p="$1" '$1=="CREATED" && $2==p {found=1} END {exit !found}' \
    "${MANIFEST_FILE}" 2>/dev/null; then
    return 0
  fi
  printf 'CREATED\t%s\n' "$1" >> "${MANIFEST_FILE}"
}

atomic_install() {
  local mode="$1" owner="$2" source="$3" target="$4"
  local dir
  dir="$(dirname "${target}")"
  install -d -m 0755 "${dir}"
  install -m "${mode}" -o "${owner%%:*}" -g "${owner##*:}" \
    "${source}" "${target}"
}

public_ipv4() {
  curl -4fsS --connect-timeout 5 https://api.ipify.org 2>/dev/null || true
}

is_ipv4() {
  local ip="$1" octet
  local -a octets
  [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r -a octets <<< "${ip}"
  for octet in "${octets[@]}"; do
    (( 10#${octet} <= 255 )) || return 1
  done
}

is_debian_like() {
  [[ -r /etc/os-release ]] || return 1
  . /etc/os-release
  [[ "${ID}" == "debian" || "${ID_LIKE:-}" == *debian* ]]
}

os_summary() {
  . /etc/os-release
  printf '%s %s %s\n' "${ID}" "${VERSION_ID}" "$(uname -m)"
}
