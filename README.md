<div align="center">

# VPS Node Setup

**把一台全新 VPS 交给 AI，拿回可直接使用的节点。**

你只需要提供 SSH 登录信息，AI 会自动完成全部部署，
最终交付两条节点链接和一个订阅地址。

</div>

<br>

> [!NOTE]
> 已在 Debian 12 上完成全部验证。Ubuntu 22.04 / 24.04 理论兼容但未正式测试，如需使用请自行验证。

<br>

## 你会得到什么

| Reality 节点 | Hysteria2 节点 | 订阅地址 |
| :--- | :--- | :--- |
| 稳定的 TCP 连接 | 更快的 UDP 连接 + 端口跳跃 | 一个链接导入全部节点 |

部署过程全自动：环境检查 → 安全加固 → 安装代理 → 生成节点 → 验证可用性。

只接受**全新的、干净的 VPS**。如果检测到已有代理软件或面板，会自动停止，不会覆盖你正在使用的东西。

> [!WARNING]
> **订阅地址请像密码一样保管。** 它使用 HTTP 而非 HTTPS 传输，任何拿到链接的人都能获取你的节点。如需公开使用，请自行配置域名和 HTTPS。

<br>

---

<br>

## 三步完成

<br>

### ① 在云厂商后台放行端口

去你的云服务器控制台，找到「安全组」或「防火墙」，放行以下端口：

| 端口 | 用途 |
| :--- | :--- |
| `443` TCP | Reality 节点 |
| `8443` UDP | Hysteria2 节点 |
| `2500–3600` UDP | Hysteria2 端口跳跃 |
| 部署完成后会告诉你 | 订阅地址 |

> [!TIP]
> **Reality 能用但 Hysteria2 不通？** 说明 TCP 没问题但 UDP 被挡了。回云厂商后台检查 `8443` 和 `2500–3600` 的 UDP 是否放行。

<br>

### ② 复制提示词，发给 AI

填好你的 VPS 信息，发送给任意支持 Skill 的 AI Agent：

```text
请安装并使用这个仓库中的 Skill：
https://github.com/ianzo0/vps-node-setup-repo

如果 GitHub 无法访问，请改用 Cloudflare 备用包。下载包及其签名后，以 Minisign 验签；验签失败立即停止，不要加载或执行其中内容。验签通过后解压并加载 Skill：

- 包：https://vps-node-download.pages.dev/vps-node-setup.tar.gz
- 签名：https://vps-node-download.pages.dev/vps-node-setup.tar.gz.minisig
- 只信任公钥：`RWRvdJt+t7f7UwEUivaioOMuosD2mHFKbLTIvZtngAY3xyEoyAUzQTdD`

然后在以下全新 VPS 上完成节点部署：

- IP：
- 端口：
- 用户：root
- 密码：

不要执行 rollback。
```

<br>

### ③ 等待完成，拿到结果

AI 会自动完成所有步骤。结束后你会收到：
- 一条 **Reality 节点链接**
- 一条 **Hysteria2 节点链接**
- 一个**订阅地址**

复制到你的代理客户端即可使用。

<br>

---

<br>

## 想删掉部署？

确认你已保存好节点链接，然后把这段话发给同一个 AI：

```text
请对刚才这台 VPS 执行 rollback。
```

回滚只会删除本次部署创建的内容，不会动服务器上原有的东西。

<br>

---

<br>

## 要求与限制

| 需要 | 不支持 |
| :--- | :--- |
| Debian 12，amd64 或 arm64 | 已装过代理软件或面板的服务器 |
| 全新 VPS，root 权限 | Alpine、CentOS、Windows 等其他系统 |
| 内存 + swap ≥ 768 MB，磁盘剩余 ≥ 512 MB | 不会修改你的 SSH 设置 |

<br>

---

<br>
