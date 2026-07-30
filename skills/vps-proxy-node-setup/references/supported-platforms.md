# Supported platforms

## Formally supported

- Debian 12
- `amd64` or `arm64`
- A new single VPS with root access or passwordless sudo
- At least 768 MiB RAM+swap combined and 512 MiB free space on `/`

## Theoretical compatibility (user self-test required)

- Ubuntu Server 22.04 LTS and 24.04 LTS: not first-release supported platforms. The user must complete their own deployment and rollback tests before relying on them.
- Ubuntu 20.04: theoretical compatibility only when Ubuntu Pro/ESM is active. The user must complete their own tests; otherwise stop and recommend an upgrade before deployment.
- Debian 11: temporary compatibility only until 2026-08-31 (its LTS end date). From 2026-09-01 onward the skill must stop before mutation.

## Not supported in the first release

- Existing sing-box, xray, hysteria, or control-panel installations
- Alpine, CentOS, Rocky, Fedora, OpenWrt, Windows, and macOS servers
- Unsupported CPU architectures
- Hosts where a cloud firewall, provider NAT, or local policy prevents the required ports
- Hosts whose OS initialization (`cloud-init`) is still running or has failed

## Required inbound rules

- `443/tcp` for VLESS Reality
- `8443/udp` for Hysteria2
- `2500:3600/udp` for Hysteria2 port hopping (forwarded by a skill-owned DNAT rule to the Hy2 main port)
- One generated high TCP port for the token-protected HTTP subscription

The generated subscription uses plain HTTP unless the user supplies a separately managed HTTPS reverse proxy and domain. The URL is bearer-token protected and must be treated like a password.
