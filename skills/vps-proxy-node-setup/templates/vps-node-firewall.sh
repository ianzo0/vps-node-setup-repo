#!/usr/bin/env bash
set -Eeuo pipefail

CHAIN="VPS_NODE_SETUP_HY2"
START="__HOP_START__"
END="__HOP_END__"
TARGET="__HY2_PORT__"

apply_rules() {
  iptables -t nat -N "${CHAIN}" 2>/dev/null || true
  iptables -t nat -F "${CHAIN}"
  iptables -t nat -A "${CHAIN}" -p udp --dport "${START}:${END}" -j DNAT --to-destination ":${TARGET}"
  iptables -t nat -C PREROUTING -p udp --dport "${START}:${END}" -j "${CHAIN}" 2>/dev/null ||
    iptables -t nat -A PREROUTING -p udp --dport "${START}:${END}" -j "${CHAIN}"
}

remove_rules() {
  iptables -t nat -D PREROUTING -p udp --dport "${START}:${END}" -j "${CHAIN}" 2>/dev/null || true
  iptables -t nat -F "${CHAIN}" 2>/dev/null || true
  iptables -t nat -X "${CHAIN}" 2>/dev/null || true
}

case "${1:-apply}" in
  apply) apply_rules ;;
  remove) remove_rules ;;
  *) printf 'usage: %s {apply|remove}\n' "$0" >&2; exit 2 ;;
esac
