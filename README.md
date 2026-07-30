# 新手 VPS 节点部署助手

英文标识：`vps-proxy-node-setup`

这是一个面向 Codex Agent 的自主管理 Skill：给它一个全新的 Debian/Ubuntu VPS 的 SSH 入口后，Agent 可以完成环境检查、安全加固、保守网络调优、固定版本 sing-box 安装、VLESS Reality 与 Hysteria2 配置、端口跳跃、订阅生成和部署后检查。

## 支持范围

- Debian 12（正式支持）
- Ubuntu Server 22.04/24.04（理论支持，需自行测试；不属于首版正式支持平台）
- `amd64`、`arm64`
- 新 VPS、root 或免密 sudo
- RAM 与 swap 合计至少 768MiB，根分区至少剩余 512MiB
- Ubuntu 20.04 仅作理论兼容评估，且须有有效 Ubuntu Pro/ESM；需自行测试
- Debian 11 仅兼容到 2026-08-31；2026-09-01 起脚本会在变更前停止

首版不会接管已经存在的 sing-box、Xray、Hysteria 或面板安装，也不会修改 SSH 端口、root 登录策略或密码登录策略。

## 部署前：云防火墙是必需条件

本机 UFW 规则只能控制 VPS 已收到的流量，不能穿透云厂商的安全组、入站防护或网络防火墙。部署前必须在 VPS 提供商后台放行：

- `443/tcp`（VLESS Reality）
- `8443/udp`（Hysteria2 主端口）
- `2500–3600/udp`（Hysteria2 端口跳跃）
- 部署结果中生成的订阅 TCP 端口

Reality 可用只证明 TCP 443 路径正常，不代表 UDP Hy2 或端口跳跃已放行。如果 Reality 可用而 Hy2 不可用，先测试直连 `8443/udp`；若 VPS 的 UFW/NAT 计数器没有命中，问题通常在云厂商入站防护或客户端网络，不能由 Skill 在 VPS 内修复。

> 排错提示：**Reality 能通、Hy2 不通时，先检查云厂商入站防护是否放行 `8443/udp` 与 `2500–3600/udp`，再调整任何服务器配置。**

这是部署前置条件，不会打断一键部署流程。订阅端口在部署时随机生成，结果会提示其端口；随后再到云厂商后台放行该 TCP 端口。最终仍必须从 VPS 外的真实客户端验证 Reality、Hy2 直连和 Hy2 端口跳跃。

## Agent 使用方式

把 `skills/vps-proxy-node-setup` 安装到 Agent 的 skills 目录，然后直接提出部署请求。用户不需要登录服务器手动粘贴命令；Agent 只需要收集 SSH 主机、端口、用户和现有认证方式。

部署完成后会返回三个结果：

1. VLESS Reality 链接
2. Hysteria2 链接
3. 令牌保护的 HTTP 订阅地址

订阅地址默认是高位端口的 HTTP，不是 HTTPS；它应当按密码保护。部署结果会再次列出云防火墙与外部客户端测试要求。

## 本地验证

```sh
skills/vps-proxy-node-setup/tests/test_static.sh
```

该测试只做离线检查，不连接 VPS、不生成真实凭据，也不会修改系统。

可将 `AGENT-TEST-PROMPT.md` 中的提示词直接交给另一个 Agent 进行独立测试。
