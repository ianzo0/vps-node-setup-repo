# 发布检查清单

发布日期：待定
正式支持平台：Debian 12（`amd64`、`arm64`）。Ubuntu 仅为理论支持，需自行测试，不作为首版正式支持平台。

## 当前发布任务（按顺序处理）

- [x] 已完成：支持平台文案统一为 Debian 12 正式支持、Ubuntu 理论支持。
- [x] 已完成：fail2ban 使用 systemd journal 后端；部署前后状态快照与 rollback 恢复逻辑已实现。
- [x] 已完成：回滚后的同机再次部署会归档旧状态，避免跳过新部署阶段；对应离线回归测试通过。
- [x] 已完成：静态测试、Shell 语法、模板 JSON 与敏感信息模式扫描通过。
- [x] 已完成：已建立独立 Git 仓库并添加 `.gitignore`；尚未提交或推送。
- [x] 已完成：在重置后的 Debian 12 测试 VPS 部署最终版；fail2ban 和三项自有服务均为 `active`，`fail2ban-client ping` 成功。
- [x] 已完成：用户从外部客户端验证 VLESS Reality、Hysteria2 直连与端口跳跃，以及订阅；Hysteria2 首次失败由云厂商入站防护拦截，放行 UDP 后通过。
- [x] 已完成：在同一 VPS 执行最终版 rollback；验证 fail2ban、UFW、NAT、自有服务和脚本新建目录均恢复或移除。
- [ ] 待执行：最终敏感信息复扫、提交 Git 变更并由用户发布。

## 可自行测试

- [ ] 在干净的 Debian 12 VPS 上运行 `skills/vps-proxy-node-setup/tests/test_static.sh`。
- [ ] 执行 `deploy.sh preflight`，确认资源、端口、既有 UFW 和 NAT 冲突检查均通过。
- [ ] 执行一次完整部署，并确认三个自有 systemd 服务为 `active`。
- [ ] 确认 fail2ban 为 `active`，且 `fail2ban-client ping` 返回 `Server replied: pong`。
- [ ] 确认自有 NAT 链和 `PREROUTING` 跳转存在，且未改动共享 NAT 规则。
- [ ] 执行 `rollback`：确认三项自有服务、UFW 规则、NAT 链与脚本新建的空目录均移除，UFW 恢复部署前状态。
- [ ] 在同一测试 VPS 的 rollback 后再次部署，确认旧状态已归档且不会跳过新部署步骤。
- [ ] 在部署前未安装 fail2ban 的极简 Debian 12 上，回滚后确认 fail2ban 为 `disabled` 且 `inactive`，而非 `failed`。
- [ ] 若使用 Ubuntu 22.04/24.04 或 Ubuntu Pro/ESM 20.04，重复上述部署与回滚测试；结果仅代表自行验证，不将该系统列入正式支持。

## 需要用户配合测试

- [ ] 在云厂商安全组/入站防护中放行 TCP 443、UDP 8443、UDP 2500–3600 和生成的订阅 TCP 端口；VPS 内 UFW 放行不代表外部可达。
- [ ] 从 VPS 外部网络分别用实际客户端完成 VLESS Reality 与 Hysteria2 握手和流量测试。
- [ ] 不以 Reality 通过替代 Hysteria2 测试：Reality 仅验证 TCP 443，Hysteria2 必须单独验证 UDP 8443 与端口跳跃范围。
- [ ] 使用真实客户端确认端口跳跃范围可用，并核对订阅链接导入结果。
- [ ] 如需公开订阅，提供自管域名与 HTTPS 反向代理；默认令牌保护 HTTP 地址不应公开。

## 另一 agent 已完成的实测证据

- 已在全新 Debian 12 测试 VPS 完成两次前向部署：依赖安装、BBR、sing-box 校验、Reality/Hysteria2 服务、订阅服务、NAT 端口跳跃和 `postcheck` 均通过。
- 已在真实部署上执行过一次 `resume`；未重复安装或重生成凭据，三项自有服务保持 `active`。
- 第二次重置系统后的完整流程未再出现依赖顺序或脚本权限问题；外部订阅访问返回 HTTP 200。

## 发布阻塞项

- [x] 已完成本轮 fail2ban 回滚方案的真实 Debian 12 部署与 rollback 验证。
- [x] 已完成本轮修订的独立 Agent 前向测试：部署、`status`、`resume` 与 rollback 均通过。
- [x] 已完成外部客户端的 Reality/Hysteria2 真实握手测试。
