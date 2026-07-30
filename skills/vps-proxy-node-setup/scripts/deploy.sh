#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

PORT_REALITY="${PORT_REALITY:-443}"
PORT_HY2="${PORT_HY2:-8443}"
PORT_HOP_START="${PORT_HOP_START:-2500}"
PORT_HOP_END="${PORT_HOP_END:-3600}"
SNI_REALITY="${SNI_REALITY:-www.apple.com}"
HY2_SERVER_NAME="${HY2_SERVER_NAME:-hy2.local}"
RELEASE_MANIFEST="${RELEASE_MANIFEST:-${SCRIPT_DIR}/../references/version-manifest.json}"
SING_BOX_BIN="/usr/local/bin/sing-box"
SING_BOX_CONFIG="/etc/sing-box/config.json"
SING_BOX_SERVICE="vps-node-sing-box.service"
FIREWALL_SERVICE="vps-node-firewall.service"
SUB_SERVICE="vps-node-subscription.service"
SUB_DIR="/var/lib/vps-node-setup/public"
SUB_FILE="${SUB_DIR}/subscription.txt"
SUB_SCRIPT="/usr/local/lib/vps-node-setup/subscription_server.py"
FIREWALL_SCRIPT="/usr/local/sbin/vps-node-setup-firewall"
SECRETS_FILE="/etc/vps-node-setup/credentials.env"
SUB_TOKEN_FILE="/etc/vps-node-setup/subscription-token"

validate_settings() {
  local value
  for value in "${PORT_REALITY}" "${PORT_HY2}" "${PORT_HOP_START}" "${PORT_HOP_END}"; do
    [[ "${value}" =~ ^[0-9]+$ ]] &&
      (( 10#${value} >= 1 && 10#${value} <= 65535 )) ||
      die "invalid port setting: ${value}"
  done
  (( PORT_HOP_START <= PORT_HOP_END )) || die "invalid Hy2 port-hop range"
  [[ "${SNI_REALITY}" =~ ^[A-Za-z0-9.-]+$ ]] || die "invalid Reality SNI"
  [[ "${HY2_SERVER_NAME}" =~ ^[A-Za-z0-9.-]+$ ]] || die "invalid Hy2 server name"
}

check_platform() {
  [[ -r /etc/os-release ]] || die "cannot read /etc/os-release"
  . /etc/os-release
  case "${ID}:${VERSION_ID}" in
    ubuntu:22.04|ubuntu:24.04|debian:12) ;;
    ubuntu:20.04)
      command -v pro >/dev/null 2>&1 &&
        pro status 2>/dev/null | grep -qi 'esm' ||
        die "Ubuntu 20.04 requires active Ubuntu Pro/ESM"
      ;;
    debian:11)
      [[ "$(date -u +%F)" < "2026-09-01" ]] ||
        die "Debian 11 LTS has ended; upgrade before deployment"
      ;;
    *) die "unsupported operating system: ${ID} ${VERSION_ID}" ;;
  esac
  case "$(uname -m)" in
    x86_64|aarch64) ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

check_new_host() {
  local conflict
  command -v systemctl >/dev/null 2>&1 || return 0
  for conflict in sing-box xray hysteria hysteria-server x-ui 3x-ui v2ray; do
    if systemctl list-unit-files --type=service 2>/dev/null |
      awk '{print $1}' | grep -qx "${conflict}.service"; then
      die "existing service detected: ${conflict}; first release will not take over an existing host"
    fi
  done
  for conflict in /etc/xray /etc/hysteria; do
    [[ -e "${conflict}" ]] && die "existing node configuration detected: ${conflict}"
  done
  if [[ -e /etc/sing-box ]] && ! stage_is_done sing_box; then
    die "existing node configuration detected: /etc/sing-box"
  fi
}

check_initialization() {
  if command -v cloud-init >/dev/null 2>&1; then
    local cloud_status
    cloud_status="$(cloud-init status 2>/dev/null || true)"
    [[ "${cloud_status}" != *"running"* ]] ||
      die "cloud-init is still running; retry after the operating system finishes initialization"
    [[ "${cloud_status}" != *"error"* ]] ||
      die "cloud-init reports an error; inspect the VPS console before deployment"
  fi
}

check_resources() {
  local mem_mb swap_mb available_mb disk_mb
  mem_mb="$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 ))"
  swap_mb="$(( $(awk '/SwapTotal/ {print $2}' /proc/meminfo) / 1024 ))"
  available_mb="$((mem_mb + swap_mb))"
  disk_mb="$(df -Pm / | awk 'NR==2 {print $4}')"
  (( available_mb >= 768 )) ||
    die "insufficient memory: require at least 768 MiB RAM+swap combined"
  (( disk_mb >= 512 )) ||
    die "insufficient disk space: require at least 512 MiB free on /"
}

check_port_conflicts() {
  need_cmd ss
  if ss -H -ltn | awk -v p="${PORT_REALITY}" '
    {n=split($4,a,":"); if (a[n]==p) found=1} END {exit !found}'; then
    die "TCP port ${PORT_REALITY} is already in use"
  fi
  if ss -H -lun | awk -v p="${PORT_HY2}" '
    {n=split($4,a,":"); if (a[n]==p) found=1} END {exit !found}'; then
    die "UDP port ${PORT_HY2} is already in use"
  fi
  if ss -H -lun | awk -v lo="${PORT_HOP_START}" -v hi="${PORT_HOP_END}" '
    {n=split($4,a,":"); p=a[n]+0; if (p>=lo && p<=hi) found=1}
    END {exit !found}'; then
    die "a UDP port in ${PORT_HOP_START}:${PORT_HOP_END} is already in use"
  fi
}

check_firewall_conflicts() {
  if ufw status 2>/dev/null | grep -q '^Status: active'; then
    local ufw_rules
    ufw_rules="$(ufw status numbered 2>/dev/null | grep -c '^\[' || true)"
    (( ufw_rules == 0 )) ||
      die "existing UFW rules detected; first release will not modify an active firewall"
  fi
  if iptables -t nat -S PREROUTING 2>/dev/null | grep -q '^-A '; then
    die "existing NAT PREROUTING rules detected; first release will not modify a shared NAT setup"
  fi
}

preflight() {
  need_root
  need_cmd awk
  validate_settings
  check_platform
  check_initialization
  check_resources
  ensure_state_dir
  check_new_host
  if ! stage_is_done security && command -v ss >/dev/null 2>&1; then
    check_port_conflicts
  fi
  if ! stage_is_done security &&
    command -v ufw >/dev/null 2>&1 &&
    command -v iptables >/dev/null 2>&1; then
    check_firewall_conflicts
  fi
  local mem_mb swap_mb disk_mb bbr ipv4
  mem_mb="$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 ))"
  swap_mb="$(( $(awk '/SwapTotal/ {print $2}' /proc/meminfo) / 1024 ))"
  disk_mb="$(df -Pm / | awk 'NR==2 {print $4}')"
  bbr="$(command -v sysctl >/dev/null 2>&1 && sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  ipv4="$(public_ipv4)"
  if [[ -z "${ipv4}" ]] && command -v ip >/dev/null 2>&1; then
    ipv4="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  fi
  {
    printf 'time_utc=%s\n' "$(date -u +%FT%TZ)"
    printf 'platform=%s\n' "$(os_summary)"
    printf 'memory_mb=%s\n' "${mem_mb}"
    printf 'swap_mb=%s\n' "${swap_mb}"
    printf 'disk_free_mb=%s\n' "${disk_mb}"
    printf 'public_ipv4=%s\n' "${ipv4:-unavailable}"
    printf 'bbr_available=%s\n' "${bbr:-unknown}"
    printf 'default_route=%s\n' "$(command -v ip >/dev/null 2>&1 && ip route show default | head -n1 || echo unavailable)"
    printf 'ssh_port=%s\n' "$(command -v ss >/dev/null 2>&1 && ss -H -ltnp 2>/dev/null | sed -n 's/.*:\([0-9][0-9]*\).*sshd.*/\1/p' | head -n1 || echo unavailable)"
    printf 'required_ports=tcp:%s,udp:%s,udp:%s-%s\n' \
      "${PORT_REALITY}" "${PORT_HY2}" "${PORT_HOP_START}" "${PORT_HOP_END}"
    printf 'conflicts=none\n'
  } > "${REPORT_FILE}"
  chmod 0600 "${REPORT_FILE}"
  if command -v jq >/dev/null 2>&1; then
    mark_stage preflight done
  else
    printf 'missing_command=jq (will be installed during apply)\n' >> "${REPORT_FILE}"
  fi
  cat "${REPORT_FILE}"
}

manifest_is_ready() {
  [[ -s "${RELEASE_MANIFEST}" ]] || die "release manifest is missing"
  jq -e '.sing_box.version | type=="string" and test("^REVIEWED_RELEASE_REQUIRED$")==false' \
    "${RELEASE_MANIFEST}" >/dev/null || die "release manifest is not reviewed"
  jq -e '.sing_box.artifacts | length >= 2' "${RELEASE_MANIFEST}" >/dev/null ||
    die "release manifest has no architecture artifacts"
}

install_packages() {
  is_debian_like || die "apt-based host required"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl jq openssl \
    iproute2 iptables ufw fail2ban python3 python3-systemd tar procps
  local required
  for required in curl jq openssl ip ss sysctl iptables ufw fail2ban-client python3 tar; do
    need_cmd "${required}"
  done
  python3 --version >/dev/null
  jq --version >/dev/null
  openssl version >/dev/null
  iptables --version >/dev/null
  mark_stage packages_verified done
}

snapshot_fail2ban_state() {
  # Capture this before apt installs fail2ban. Minimal Debian images normally
  # lack the unit; rollback must restore that inactive state, not restart it.
  local unit_present=0 enabled=absent active=inactive
  [[ -e "${STATE_DIR}/fail2ban.before" ]] && return 0
  if systemctl cat fail2ban.service >/dev/null 2>&1; then
    unit_present=1
    enabled="$(systemctl is-enabled fail2ban.service 2>/dev/null || true)"
    active="$(systemctl is-active fail2ban.service 2>/dev/null || true)"
    [[ -n "${enabled}" ]] || enabled=unknown
    [[ -n "${active}" ]] || active=inactive
  fi
  {
    printf 'unit_present=%s\n' "${unit_present}"
    printf 'enabled=%s\n' "${enabled}"
    printf 'active=%s\n' "${active}"
  } > "${STATE_DIR}/fail2ban.before"
  chmod 0600 "${STATE_DIR}/fail2ban.before"
}

restore_fail2ban_state() {
  local unit_present enabled active
  [[ -s "${STATE_DIR}/fail2ban.before" ]] || return 0
  unit_present="$(sed -n 's/^unit_present=//p' "${STATE_DIR}/fail2ban.before" | head -n1)"
  enabled="$(sed -n 's/^enabled=//p' "${STATE_DIR}/fail2ban.before" | head -n1)"
  active="$(sed -n 's/^active=//p' "${STATE_DIR}/fail2ban.before" | head -n1)"
  # Packages intentionally remain installed. If the unit did not exist before
  # deployment, disable and stop the package-installed service on rollback.
  if [[ "${unit_present}" != 1 ]]; then
    systemctl disable --now fail2ban.service >/dev/null 2>&1 || true
    return 0
  fi
  case "${enabled}" in
    enabled|enabled-runtime|linked|linked-runtime) systemctl enable fail2ban.service >/dev/null 2>&1 || true ;;
    disabled) systemctl disable fail2ban.service >/dev/null 2>&1 || true ;;
    masked) systemctl mask fail2ban.service >/dev/null 2>&1 || true ;;
  esac
  if [[ "${active}" == active ]]; then
    systemctl restart fail2ban.service >/dev/null 2>&1 || true
  else
    systemctl stop fail2ban.service >/dev/null 2>&1 || true
  fi
}

ufw_add_owned() {
  local rule="$1" action spec expected
  read -r action spec <<< "${rule}"
  expected="ALLOW"
  [[ "${action}" == "limit" ]] && expected="LIMIT"
  if ! ufw status | awk -v spec="${spec}" -v expected="${expected}" \
    '$1 == spec && $2 ~ expected {found=1} END {exit !found}'; then
    ufw "${action}" "${spec}"
    printf 'UFW\t%s\n' "${rule}" >> "${MANIFEST_FILE}"
  fi
}

create_owned_dir() {
  local mode="$1" path="$2"
  if [[ -e "${path}" ]]; then
    [[ -d "${path}" ]] || die "expected directory but found another path type: ${path}"
    return 0
  fi
  install -d -m "${mode}" "${path}"
  printf 'CREATED_DIR\t%s\n' "${path}" >> "${MANIFEST_FILE}"
}

apply_security() {
  backup_path /etc/sysctl.d/90-vps-node-setup-security.conf
  backup_path /etc/fail2ban/jail.d/vps-node-setup.local
  record_created /etc/sysctl.d/90-vps-node-setup-security.conf
  record_created /etc/fail2ban/jail.d/vps-node-setup.local
  local tmp ssh_port ssh_client_ip ignore_line
  if [[ ! -e "${STATE_DIR}/ufw.before" ]]; then
    ufw status verbose > "${STATE_DIR}/ufw.before" 2>/dev/null || true
    record_created "${STATE_DIR}/ufw.before"
  fi
  tmp="$(mktemp)"
  cat > "${tmp}" <<'EOF'
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
fs.suid_dumpable = 0
EOF
  atomic_install 0644 root:root "${tmp}" /etc/sysctl.d/90-vps-node-setup-security.conf
  rm -f "${tmp}"
  sysctl -p /etc/sysctl.d/90-vps-node-setup-security.conf >/dev/null
  ssh_port="$(ss -H -ltnp 2>/dev/null | sed -n 's/.*:\([0-9][0-9]*\).*sshd.*/\1/p' | head -n1)"
  [[ "${ssh_port}" =~ ^[0-9]+$ ]] || ssh_port=22
  ssh_client_ip="${SSH_CONNECTION:-}"
  ssh_client_ip="${ssh_client_ip%% *}"
  ignore_line="127.0.0.1/8 ::1"
  if [[ "${ssh_client_ip}" =~ ^[0-9A-Fa-f:.]+$ ]]; then
    ignore_line="${ignore_line} ${ssh_client_ip}"
  fi
  cat > /etc/fail2ban/jail.d/vps-node-setup.local <<EOF
[sshd]
enabled = true
port = ${ssh_port}
backend = systemd
ignoreip = ${ignore_line}
maxretry = 8
findtime = 10m
bantime = 10m
EOF
  chmod 0644 /etc/fail2ban/jail.d/vps-node-setup.local
  systemctl enable --now fail2ban
  systemctl is-active --quiet fail2ban ||
    die "fail2ban did not start; refusing to continue with an inactive SSH-ban jail"
  ufw default deny incoming
  ufw default allow outgoing
  ufw_add_owned "limit ${ssh_port}/tcp"
  ufw_add_owned "allow ${PORT_REALITY}/tcp"
  ufw_add_owned "allow ${PORT_HY2}/udp"
  ufw_add_owned "allow ${PORT_HOP_START}:${PORT_HOP_END}/udp"
  echo "y" | ufw enable
  mark_stage security done
}

apply_network() {
  backup_path /etc/sysctl.d/90-vps-node-setup-network.conf
  record_created /etc/sysctl.d/90-vps-node-setup-network.conf
  local mem_kb buf tmp
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  buf=$(( mem_kb * 5 / 100 * 1024 ))
  (( buf > 67108864 )) && buf=67108864
  (( buf < 4194304 )) && buf=4194304
  tmp="$(mktemp)"
  cat > "${tmp}" <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = ${buf}
net.core.wmem_max = ${buf}
net.ipv4.tcp_rmem = 4096 87380 ${buf}
net.ipv4.tcp_wmem = 4096 65536 ${buf}
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
net.core.somaxconn = 16384
net.ipv4.tcp_max_syn_backlog = 8192
EOF
  atomic_install 0644 root:root "${tmp}" /etc/sysctl.d/90-vps-node-setup-network.conf
  rm -f "${tmp}"
  sysctl -p /etc/sysctl.d/90-vps-node-setup-network.conf >/dev/null
  [[ "$(sysctl -n net.ipv4.tcp_congestion_control)" == bbr ]] ||
    die "BBR could not be activated"
  mark_stage network done
}

install_sing_box() {
  local arch url sha archive tmpdir extracted
  arch="$(uname -m)"
  case "${arch}" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) die "unsupported architecture: ${arch}" ;;
  esac
  url="$(jq -r --arg a "${arch}" '.sing_box.artifacts[$a].url' "${RELEASE_MANIFEST}")"
  sha="$(jq -r --arg a "${arch}" '.sing_box.artifacts[$a].sha256' "${RELEASE_MANIFEST}")"
  archive="$(jq -r --arg a "${arch}" '.sing_box.artifacts[$a].archive' "${RELEASE_MANIFEST}")"
  [[ "${url}" == https://github.com/SagerNet/sing-box/releases/download/* ]] || die "untrusted release URL"
  backup_path "${SING_BOX_BIN}"
  record_created "${SING_BOX_BIN}"
  tmpdir="$(mktemp -d)"
  curl -fL --retry 3 --proto '=https' --tlsv1.2 "${url}" -o "${tmpdir}/${archive}"
  printf '%s  %s\n' "${sha}" "${tmpdir}/${archive}" | sha256sum -c -
  tar -xzf "${tmpdir}/${archive}" -C "${tmpdir}"
  extracted="$(find "${tmpdir}" -type f -name sing-box -perm -u+x | head -n1)"
  [[ -n "${extracted}" ]] || die "sing-box binary missing from archive"
  atomic_install 0755 root:root "${extracted}" "${SING_BOX_BIN}"
  rm -rf "${tmpdir}"
  "${SING_BOX_BIN}" version | grep -qF "$(jq -r '.sing_box.version' "${RELEASE_MANIFEST}")" ||
    die "installed sing-box version mismatch"
  mark_stage sing_box done
}

generate_node() {
  local uuid keypair private public shortid password cfgdir
  local public_ip sub_port token
  cfgdir="/etc/vps-node-setup"
  create_owned_dir 0700 "${cfgdir}"
  create_owned_dir 0700 /etc/sing-box
  create_owned_dir 0700 "${SUB_DIR}"
  record_created "${SING_BOX_CONFIG}"
  record_created "${cfgdir}/hy2-key.pem"
  record_created "${cfgdir}/hy2-cert.pem"
  record_created "${SECRETS_FILE}"
  record_created "${SUB_TOKEN_FILE}"
  record_created "${SUB_FILE}"
  record_created "${STATE_DIR}/runtime.env"
  keypair="$("${SING_BOX_BIN}" generate reality-keypair)"
  private="$(awk -F': ' '/PrivateKey/ {print $2; exit}' <<<"${keypair}")"
  public="$(awk -F': ' '/PublicKey/ {print $2; exit}' <<<"${keypair}")"
  uuid="$("${SING_BOX_BIN}" generate uuid)"
  shortid="$(openssl rand -hex 4)"
  password="$(openssl rand -hex 32)"
  [[ -n "${private}" && -n "${public}" && -n "${uuid}" ]] || die "credential generation failed"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -days 3650 -keyout "${cfgdir}/hy2-key.pem" -out "${cfgdir}/hy2-cert.pem" \
    -subj "/CN=${HY2_SERVER_NAME}" >/dev/null 2>&1
  chmod 0600 "${cfgdir}/hy2-key.pem" "${cfgdir}/hy2-cert.pem"
  jq --arg uuid "${uuid}" --arg sni "${SNI_REALITY}" --arg private "${private}" \
    --arg shortid "${shortid}" --arg password "${password}" \
    '.inbounds[0].users[0].uuid=$uuid |
     .inbounds[0].tls.server_name=$sni |
     .inbounds[0].tls.reality.handshake.server=$sni |
     .inbounds[0].tls.reality.private_key=$private |
     .inbounds[0].tls.reality.short_id[0]=$shortid |
     .inbounds[1].users[0].password=$password' \
    "${SCRIPT_DIR}/../templates/sing-box.json.template" > "${SING_BOX_CONFIG}"
  chmod 0600 "${SING_BOX_CONFIG}"
  cat > "${SECRETS_FILE}" <<EOF
VLESS_UUID=${uuid}
REALITY_PUBLIC_KEY=${public}
REALITY_SHORT_ID=${shortid}
HY2_PASSWORD=${password}
EOF
  chmod 0600 "${SECRETS_FILE}"
  public_ip="$(public_ipv4)"
  is_ipv4 "${public_ip}" ||
    public_ip="$(ip -4 route get 1.1.1.1 | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  is_ipv4 "${public_ip}" || die "could not determine a valid public IPv4"
  sub_port="$((20000 + ($(od -An -N2 -tu2 /dev/urandom) % 20000)))"
  while ss -H -ltn | awk '{print $4}' | grep -qE ":${sub_port}$"; do
    sub_port="$((20000 + ($(od -An -N2 -tu2 /dev/urandom) % 20000)))"
  done
  token="$(openssl rand -hex 32)"
  printf '%s\n' "${token}" > "${SUB_TOKEN_FILE}"
  chmod 0600 "${SUB_TOKEN_FILE}"
  {
    printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#VPS-Reality\n' \
      "${uuid}" "${public_ip}" "${PORT_REALITY}" "${SNI_REALITY}" "${public}" "${shortid}"
    printf 'hysteria2://%s@%s:%s?insecure=1&sni=%s#VPS-Hy2\n' \
      "${password}" "${public_ip}" "${PORT_HOP_START}" "${HY2_SERVER_NAME}"
  } > "${SUB_FILE}"
  base64 -w0 "${SUB_FILE}" > "${SUB_FILE}.b64"
  mv -f "${SUB_FILE}.b64" "${SUB_FILE}"
  chmod 0600 "${SUB_FILE}"
  cat > "${STATE_DIR}/runtime.env" <<EOF
PUBLIC_IP=${public_ip}
SUB_PORT=${sub_port}
EOF
  chmod 0600 "${STATE_DIR}/runtime.env"
  mark_stage credentials done
}

install_services() {
  backup_path "/etc/systemd/system/${SING_BOX_SERVICE}"
  backup_path "/etc/systemd/system/${FIREWALL_SERVICE}"
  backup_path "/etc/systemd/system/${SUB_SERVICE}"
  backup_path "${FIREWALL_SCRIPT}"
  backup_path "${SUB_SCRIPT}"
  record_created "${FIREWALL_SCRIPT}"
  record_created "${SUB_SCRIPT}"
  record_created "/etc/systemd/system/${SING_BOX_SERVICE}"
  record_created "/etc/systemd/system/${FIREWALL_SERVICE}"
  record_created "/etc/systemd/system/${SUB_SERVICE}"
  install -d -m 0755 "$(dirname "${FIREWALL_SCRIPT}")"
  create_owned_dir 0755 "$(dirname "${SUB_SCRIPT}")"
  sed -e "s/__HOP_START__/${PORT_HOP_START}/" -e "s/__HOP_END__/${PORT_HOP_END}/" \
    -e "s/__HY2_PORT__/${PORT_HY2}/" "${SCRIPT_DIR}/../templates/vps-node-firewall.sh" > "${FIREWALL_SCRIPT}"
  chmod 0755 "${FIREWALL_SCRIPT}"
  install -m 0755 "${SCRIPT_DIR}/../templates/subscription-server.py" "${SUB_SCRIPT}"
  # shellcheck disable=SC1091
  . "${STATE_DIR}/runtime.env"
  cat > "/etc/systemd/system/${SING_BOX_SERVICE}" <<EOF
[Unit]
Description=VPS Node sing-box
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=${SING_BOX_BIN} run -c ${SING_BOX_CONFIG}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true
ProtectHome=true
[Install]
WantedBy=multi-user.target
EOF
  cat > "/etc/systemd/system/${FIREWALL_SERVICE}" <<EOF
[Unit]
Description=VPS Node owned Hy2 port hopping
Before=${SING_BOX_SERVICE}
After=network-pre.target ufw.service
Wants=ufw.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${FIREWALL_SCRIPT} apply
ExecStop=${FIREWALL_SCRIPT} remove
[Install]
WantedBy=multi-user.target
EOF
  cat > "/etc/systemd/system/${SUB_SERVICE}" <<EOF
[Unit]
Description=VPS Node token subscription
After=network-online.target
[Service]
ExecStart=/usr/bin/python3 ${SUB_SCRIPT} --token-file ${SUB_TOKEN_FILE} --file ${SUB_FILE} --port ${SUB_PORT}
Restart=on-failure
NoNewPrivileges=true
ProtectHome=true
ProtectSystem=strict
PrivateTmp=true
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  "${SING_BOX_BIN}" check -c "${SING_BOX_CONFIG}"
  systemctl enable --now "${FIREWALL_SERVICE}" "${SING_BOX_SERVICE}" "${SUB_SERVICE}"
  ufw_add_owned "allow ${SUB_PORT}/tcp"
  mark_stage services done
}

post_check() {
  # shellcheck disable=SC1091
  . "${STATE_DIR}/runtime.env"
  local token decoded
  token="$(<"${SUB_TOKEN_FILE}")"
  systemctl is-active --quiet "${SING_BOX_SERVICE}" || die "sing-box service is not active"
  systemctl is-active --quiet "${FIREWALL_SERVICE}" || die "firewall service is not active"
  systemctl is-active --quiet "${SUB_SERVICE}" || die "subscription service is not active"
  ss -H -ltn | grep -qE ":${PORT_REALITY}\b" || die "Reality TCP listener is missing"
  ss -H -lun | grep -qE ":${PORT_HY2}\b" || die "Hy2 UDP listener is missing"
  iptables -t nat -C PREROUTING -p udp --dport "${PORT_HOP_START}:${PORT_HOP_END}" \
    -j VPS_NODE_SETUP_HY2 2>/dev/null || die "Hy2 port-hopping jump is missing"
  iptables -t nat -C VPS_NODE_SETUP_HY2 -p udp \
    --dport "${PORT_HOP_START}:${PORT_HOP_END}" \
    -j DNAT --to-destination ":${PORT_HY2}" 2>/dev/null ||
    die "Hy2 port-hopping DNAT rule is missing"
  decoded="$(curl -fsS --connect-timeout 5 \
    "http://127.0.0.1:${SUB_PORT}/${token}" | base64 -d)" ||
    die "subscription check failed"
  grep -q '^vless://' <<< "${decoded}" || die "VLESS link is missing from subscription"
  grep -q '^hysteria2://' <<< "${decoded}" || die "Hysteria2 link is missing from subscription"
  mark_stage postcheck done
  printf 'postcheck=passed\n'
  printf 'external_client_test_required=provider firewall must allow tcp:%s,udp:%s,udp:%s-%s and the generated subscription tcp port\n' \
    "${PORT_REALITY}" "${PORT_HY2}" "${PORT_HOP_START}" "${PORT_HOP_END}"
}

write_result() {
  # shellcheck disable=SC1091
  . "${STATE_DIR}/runtime.env"
  local vless hy2 sub decoded token
  token="$(<"${SUB_TOKEN_FILE}")"
  decoded="$(base64 -d "${SUB_FILE}")"
  vless="$(sed -n '1p' <<< "${decoded}")"
  hy2="$(sed -n '2p' <<< "${decoded}")"
  sub="http://${PUBLIC_IP}:${SUB_PORT}/${token}"
  record_created "${STATE_DIR}/result.txt"
  {
    printf 'vless=%s\n' "${vless}"
    printf 'hysteria2=%s\n' "${hy2}"
    printf 'subscription=%s\n' "${sub}"
    printf 'provider_firewall_required=tcp:%s,udp:%s,udp:%s-%s,tcp:%s\n' \
      "${PORT_REALITY}" "${PORT_HY2}" "${PORT_HOP_START}" "${PORT_HOP_END}" "${SUB_PORT}"
    printf 'external_client_test_required=verify Reality, Hy2 direct UDP and Hy2 port-hopping from outside the VPS\n'
  } > "${STATE_DIR}/result.txt"
  chmod 0600 "${STATE_DIR}/result.txt"
}

archive_rolled_back_state() {
  # A completed rollback leaves its manifest as an audit trail. Before a new
  # deployment on the same host, archive that trail so old "done" stages and
  # snapshots cannot be mistaken for state belonging to the new deployment.
  local archive path
  stage_is_done rollback || return 0
  archive="${STATE_DIR}/history/${RUN_ID}"
  install -d -m 0700 "${archive}"
  for path in backups public state.json manifest.txt preflight.txt ufw.before \
    fail2ban.before runtime.env result.txt; do
    [[ -e "${STATE_DIR}/${path}" ]] && mv "${STATE_DIR}/${path}" "${archive}/${path}"
  done
  install -d -m 0700 "${BACKUP_DIR}/${RUN_ID}"
}

apply() {
  need_root
  archive_rolled_back_state
  preflight >/dev/null
  snapshot_fail2ban_state
  if ! stage_is_done packages; then install_packages; mark_stage packages done; fi
  manifest_is_ready
  if ! stage_is_done security; then
    check_port_conflicts
    check_firewall_conflicts
    mark_stage preflight done
  fi
  if ! stage_is_done security; then apply_security; fi
  if ! stage_is_done network; then apply_network; fi
  if ! stage_is_done sing_box; then install_sing_box; fi
  if ! stage_is_done credentials; then generate_node; fi
  if ! stage_is_done services; then install_services; fi
  if ! stage_is_done postcheck; then post_check; fi
  write_result
  mark_stage complete done
  printf 'deployment=complete\nresult_file=%s\n' "${STATE_DIR}/result.txt"
}

resume() {
  apply
  # `apply` skips completed stages by design. A resume must nevertheless prove
  # that the completed node is still healthy before reporting success.
  post_check
  systemctl is-active --quiet fail2ban || die "fail2ban is not active after resume"
  fail2ban-client ping >/dev/null || die "fail2ban did not respond after resume"
  printf 'resume=verified\n'
}

status() {
  need_root
  if [[ ! -f "${STATE_FILE}" ]]; then
    echo "no deployment state found"
  elif command -v jq >/dev/null 2>&1; then
    jq . "${STATE_FILE}"
  else
    cat "${STATE_FILE}"
  fi
}

is_owned_path() {
  case "$1" in
    /etc/sysctl.d/90-vps-node-setup-security.conf|\
    /etc/sysctl.d/90-vps-node-setup-network.conf|\
    /etc/fail2ban/jail.d/vps-node-setup.local|\
    /usr/local/bin/sing-box|\
    /etc/sing-box/config.json|\
    /etc/vps-node-setup/hy2-key.pem|\
    /etc/vps-node-setup/hy2-cert.pem|\
    /etc/vps-node-setup/credentials.env|\
    /etc/vps-node-setup/subscription-token|\
    /usr/local/sbin/vps-node-setup-firewall|\
    /usr/local/lib/vps-node-setup/subscription_server.py|\
    /etc/systemd/system/vps-node-sing-box.service|\
    /etc/systemd/system/vps-node-firewall.service|\
    /etc/systemd/system/vps-node-subscription.service|\
    /var/lib/vps-node-setup/ufw.before|\
    /var/lib/vps-node-setup/fail2ban.before|\
    /var/lib/vps-node-setup/runtime.env|\
    /var/lib/vps-node-setup/public/subscription.txt|\
    /var/lib/vps-node-setup/result.txt) return 0 ;;
    *) return 1 ;;
  esac
}

is_owned_dir() {
  case "$1" in
    /etc/sing-box|/etc/vps-node-setup|/usr/local/lib/vps-node-setup|\
    /var/lib/vps-node-setup/public) return 0 ;;
    *) return 1 ;;
  esac
}

rollback() {
  need_root
  [[ -f "${MANIFEST_FILE}" ]] || die "no deployment manifest found"
  systemctl disable --now "${SING_BOX_SERVICE}" "${FIREWALL_SERVICE}" "${SUB_SERVICE}" 2>/dev/null || true
  if [[ -s "${STATE_DIR}/ufw.before" ]]; then
    if grep -q '^Status: inactive' "${STATE_DIR}/ufw.before"; then
      ufw disable >/dev/null 2>&1 || true
    else
      incoming="$(sed -n 's/.*Default: \([^,]*\) (incoming).*/\1/p' "${STATE_DIR}/ufw.before" | head -n1)"
      outgoing="$(sed -n 's/.*Default: [^,]* (incoming), \([^,]*\) (outgoing).*/\1/p' "${STATE_DIR}/ufw.before" | head -n1)"
      [[ -n "${incoming}" ]] && ufw default "${incoming}" incoming >/dev/null 2>&1 || true
      [[ -n "${outgoing}" ]] && ufw default "${outgoing}" outgoing >/dev/null 2>&1 || true
    fi
  fi
  while IFS=$'\t' read -r kind path extra; do
    case "${kind}" in
      CREATED)
        is_owned_path "${path}" || die "refusing to delete unowned path from manifest: ${path}"
        rm -f -- "${path}"
        ;;
      UFW)
        read -r _action _spec <<< "${path}"
        ufw delete "${_action}" "${_spec}" >/dev/null 2>&1 || true
        ;;
    esac
  done < "${MANIFEST_FILE}"
  while IFS=$'\t' read -r kind path extra; do
    if [[ "${kind}" == BACKUP && -e "${extra}" ]]; then
      is_owned_path "${path}" || die "refusing to restore unowned path from manifest: ${path}"
      [[ "${extra}" == "${BACKUP_DIR}/"* && "${extra}" != *".."* ]] ||
        die "refusing unsafe backup path from manifest: ${extra}"
      cp -a "${extra}" "${path}"
    fi
  done < "${MANIFEST_FILE}"
  while IFS=$'\t' read -r kind path extra; do
    if [[ "${kind}" == CREATED_DIR ]]; then
      is_owned_dir "${path}" || die "refusing to remove unowned directory from manifest: ${path}"
      rmdir -- "${path}" 2>/dev/null || true
    fi
  done < "${MANIFEST_FILE}"
  systemctl daemon-reload
  sysctl --system >/dev/null 2>&1 || true
  restore_fail2ban_state
  mark_stage rollback done
  echo "owned node files and rules removed; recorded config/firewall state restored; installed packages retained"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-preflight}" in
    preflight) preflight ;;
    apply) apply ;;
    resume) resume ;;
    status) status ;;
    rollback) rollback ;;
    *) die "usage: deploy.sh {preflight|apply|resume|status|rollback}" ;;
  esac
fi
