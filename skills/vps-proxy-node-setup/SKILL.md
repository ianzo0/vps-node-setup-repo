---
name: vps-proxy-node-setup
description: Deploy, verify, resume, or remove a self-managed VPS proxy node using VLESS Reality Vision and Hysteria2. Use when a user asks an Agent to set up, build, continue, check, repair, or remove a new VPS node and wants vless://, hysteria2://, and a subscription URL without manually running server commands. Formally supports new Debian 12 hosts on amd64 or arm64; Ubuntu is theoretical compatibility and requires user self-testing.
---

# 新手 VPS 节点部署助手

Deploy only after the user has asked to deploy, build, set up, or continue a VPS node. Treat requests to inspect, check, or audit as read-only. Roll back only when the user explicitly asks to remove the deployment.

## Operating contract

- Use one SSH session target at a time. Never put host credentials, node secrets, or subscription URLs in the repository, shell history, or persistent agent notes. Show the three generated links only in the final response when the user requested deployment.
- Treat a deployment request as authorization to run the complete workflow. Do not ask a second confirmation.
- Require a new VPS. If sing-box, Xray, Hysteria, a control panel, occupied node ports, or an unowned firewall/NAT setup is detected, stop before mutation. Do not take over an existing node.
- Follow `references/supported-platforms.md` before connecting. Stop before mutation on an unsupported host.
- Run every remote script from a temporary, root-owned directory. Copy the resulting state to `/var/lib/vps-node-setup/`; do not download or execute a third-party convenience script.
- Never enable SSH hardening that could remove the user’s only login path. The security stage must not change SSH port, root-login policy, or password-login policy.
- Use `scripts/deploy.sh` for a new deployment, `scripts/deploy.sh resume` after interruption, `scripts/deploy.sh status` for read-only inspection, and `scripts/deploy.sh rollback` only when the user asks to remove this skill’s deployment.

## Workflow

### 1. Establish access and preflight

Collect only the SSH host, optional port, user, and existing authentication method. Prefer an existing SSH config alias or key. Keep passwords out of command-line arguments.

Before deployment, state that cloud-provider inbound protection is an external prerequisite: it must allow TCP 443, UDP 8443 and UDP 2500-3600. The subscription TCP port is generated during deployment and must be opened afterward. A local UFW success does not prove those ports are reachable externally; Reality passing proves only TCP 443, not Hysteria2 UDP. Do not interrupt a requested one-click deployment to request a second confirmation.

Run `scripts/deploy.sh preflight` remotely. It verifies platform, architecture, root, OS initialization, public address, RAM+swap, free disk, BBR availability, required ports, package manager, and conflicting software. It saves a report without generating credentials or changing firewall/network/service configuration.

### 2. Deploy without interaction

Run `scripts/deploy.sh apply` remotely. The script owns these stages in order:

1. Create an immutable deployment batch and backup manifest.
2. Install and verify only the required base tools.
3. Apply minimal security controls while preserving SSH access.
4. Apply the conservative `safe` network profile.
5. Install the pinned, checksum-verified sing-box release.
6. Generate Reality and Hysteria2 credentials, server configuration, and a root-only state file.
7. Create an owned UDP DNAT chain and service that forwards the Hysteria2 hop range to its main port. Never flush or reuse a shared `PREROUTING` chain.
8. Create the three delivery links: VLESS, Hysteria2, and token-protected HTTP subscription.
9. Run service, configuration, listener, DNAT, and two-link subscription checks. A full external client handshake still depends on the provider firewall/security group and is reported separately when it cannot be tested from the VPS itself. Do not diagnose a Hysteria2 failure as a server misconfiguration until external UDP reachability has been checked.

If the user reports that Reality works but Hysteria2 does not, first tell them to check the cloud-provider inbound firewall for UDP 8443 and UDP 2500-3600, then test a direct `8443/udp` Hysteria2 link before changing the server configuration.

Do not apply MTU changes, fq quantum overrides, MSS clamp, IPv4 preference changes, or aggressive TCP knobs in the default profile. Those belong only to a future measured profile. The default subscription URL is token-protected HTTP on a high port; without a domain and TLS certificate it is not HTTPS, so treat it as a secret and prefer replacing it with a reverse proxy HTTPS endpoint later.

### 3. Report results safely

Read the generated result file. Show the three links once in the final user-facing result. Do not include private keys, raw server JSON, or the full state file. State that cloud-provider security groups must allow TCP 443, UDP 8443, UDP 2500-3600, and the generated subscription TCP port.

### 4. Resume, status, and rollback

- `resume`: Read `/var/lib/vps-node-setup/state.json`, continue at the first incomplete stage, then re-run deployment health checks (services, listeners, DNAT, subscription and fail2ban) before reporting success.
- `status`: Read only. Do not repair or restart services.
- `rollback`: Remove only allowlisted paths and rules named in the deployment manifest, then restore recorded config and UFW state. Leave installed OS packages in place. Never delete a shared file or force guessed kernel defaults.

## Resources

- `scripts/deploy.sh`: Remote state-machine entry point.
- `scripts/lib.sh`: Shared validation, backup, and state helpers.
- `templates/sing-box.json.template`: Server configuration template.
- `references/supported-platforms.md`: Platform support and compatibility policy.
- `references/version-manifest.json`: Pinned release metadata. Update it only through a reviewed repository release.
