<div align="center">

# VPS Node Setup

### 把一台全新的 VPS，交给 Agent。

给出 SSH 入口，Agent 会完成检查、部署、验证，并交付可直接导入的节点链接。

`Debian 12` &nbsp;·&nbsp; `VLESS Reality` &nbsp;·&nbsp; `Hysteria2` &nbsp;·&nbsp; `amd64 / arm64`

</div>

<br>

> [!NOTE]
> **正式验证通过：Debian 12。** Ubuntu 22.04/24.04 从脚本逻辑上理论兼容，但尚未完成同等级实机回归；如需使用，请自行测试。

## 一次部署，交付三个结果

| VLESS Reality | Hysteria2 | 订阅地址 |
| :--- | :--- | :--- |
| TCP 443 节点链接 | UDP 节点链接与端口跳跃 | 令牌保护的 HTTP 订阅 |

部署过程会依次完成环境预检、基础安全加固、保守网络优化、固定版本 sing-box 安装、节点配置、订阅生成和部署后检查。

它只面向**全新 VPS**：如果发现已有 sing-box、Xray、Hysteria、面板、端口冲突或不属于它的防火墙/NAT 配置，就会在写入前停止，不接管正在使用的节点。

---

## 开始前，只确认一件事

云厂商后台的入站防护是部署的前置条件。VPS 内的 UFW 放行，不等于外部流量能进入服务器。

请在云防火墙、安全组或入站防护中放行：

- `443/tcp` · VLESS Reality
- `8443/udp` · Hysteria2 主端口
- `2500–3600/udp` · Hysteria2 端口跳跃
- 部署完成后显示的订阅 TCP 端口

> [!TIP]
> **Reality 能通、Hysteria2 不通？** 先检查 `8443/udp` 和 `2500–3600/udp` 是否已在云厂商后台放行，再改服务器配置。Reality 可用只说明 TCP 443 正常，不能证明 UDP 路径可达。

---

## 交给任意 Agent

任何支持加载 Skill 的 Agent 都可以使用。将 [`skills/vps-proxy-node-setup`](skills/vps-proxy-node-setup) 安装或加载到 Agent 的 skills 目录，然后提供一台全新 VPS 的 SSH 主机、端口、用户和现有认证方式即可；无需手动在服务器粘贴部署命令。

### 复制部署提示词

```text
请安装并使用这个仓库中 `skills/vps-proxy-node-setup` 目录的 Skill：
https://github.com/ianzo0/vps-node-setup-repo

然后在以下全新 VPS 上完成节点部署，不要执行 rollback。

SSH 登录信息：
- IP：
- 端口：
- 用户：root
- 密码：
```

### GitHub 访问受限时

GitHub 是默认来源。若无法打开或下载仓库，可使用已校验的备用下载包：

- [下载 Skill 压缩包](https://vps-node-download.pages.dev/vps-node-setup.zip)
- [校验和（SHA-256）](https://vps-node-download.pages.dev/vps-node-setup.zip.sha256)

极简 VPS 可能没有 `unzip`。可下载并校验下面的安装脚本；它会校验压缩包，并自动使用 `unzip` 或 Python 解压（不会执行部署）：

```bash
curl -fsSLO https://vps-node-download.pages.dev/install-vps-node-setup.sh
curl -fsSLO https://vps-node-download.pages.dev/install-vps-node-setup.sh.sha256
sha256sum -c install-vps-node-setup.sh.sha256
bash install-vps-node-setup.sh
```

随后将生成的 `vps-node-setup` 文件夹安装或加载为 Skill，再使用上面的部署提示词。运行脚本时请使用 `bash scripts/deploy.sh <command>`，不依赖解压程序是否保留可执行权限。备用包与 GitHub 当前版本对应；每次公开更新都会同步刷新。

### 复制独立验证提示词

将 `vps-proxy-node-setup` 安装或加载为 Skill，再把下面第一段和一台全新测试 VPS 的 SSH 信息交给另一位 Agent。节点链接已另行保存、且允许删除测试节点后，再单独发送第二段。

**完整部署测试**

```text
请安装并使用这个仓库中 `skills/vps-proxy-node-setup` 目录的 Skill：
https://github.com/ianzo0/vps-node-setup-repo

然后在以下全新 VPS 上完成节点部署，不要执行 rollback。

SSH 登录信息：
- IP：
- 端口：
- 用户：root
- 密码：
```

**回滚测试**

```text
请使用刚才安装的 Skill，对刚才这台测试 VPS 执行 rollback。完成后只汇报回滚验证结果。
```

### WorkBuddy 已验证

在 WorkBuddy 中加载此 Skill 后，选择 **Auto** 模型即可。该方式已完成独立部署、`resume` 和 rollback 验证；外部客户端仍须分别测试 Reality 与 Hysteria2。

---

## 支持范围与边界

| 已正式验证 | 理论支持，需自行测试 | 不会做的事 |
| :--- | :--- | :--- |
| Debian 12（`amd64`、`arm64`） | Ubuntu Server 22.04/24.04 | 接管已有节点或面板 |
| 全新 VPS、root 或免密 sudo | Ubuntu 20.04（须有有效 Ubuntu Pro/ESM） | 修改 SSH 端口、root 登录或密码登录策略 |
| RAM 与 swap 合计至少 768MiB；根分区至少余 512MiB | Debian 11 仅兼容至 2026-08-31 | 删除非本 Skill 创建的文件、服务或规则 |

默认订阅为令牌保护的高位 HTTP 端口，不是 HTTPS。请把它当作密码保管；如需公开订阅，建议自行配置域名与 HTTPS 反向代理。

---

## 已完成的实机验证

- Debian 12 全新 VPS：预检、部署、部署后检查、`resume`、状态检查和 rollback 均已通过。
- 回滚后：自有 systemd 服务、UFW/NAT 规则和新建目录均已验证移除或恢复；fail2ban 恢复部署前状态。
- 真实客户端：VLESS Reality、Hysteria2 直连、Hysteria2 端口跳跃及订阅导入均已验证；首次 Hysteria2 失败定位为云厂商 UDP 入站防护，放行后通过。

完整的独立部署与回滚测试提示词已在本页提供，可直接复制给另一位 Agent 使用。

---

## 本地验证

```sh
skills/vps-proxy-node-setup/tests/test_static.sh
```

这项检查完全离线：不连接 VPS、不生成真实凭据，也不会修改系统。
