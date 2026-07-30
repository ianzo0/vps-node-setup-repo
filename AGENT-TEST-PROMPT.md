# 其他 Agent 独立测试提示词

将测试包中的 `vps-proxy-node-setup` 文件夹安装或加载为 Skill，然后把下面这段话和一台全新测试 VPS 的 SSH 信息交给另一个 Agent。

## 完整部署测试

```text
请使用 $vps-proxy-node-setup 在这台全新 VPS 上完成自动部署。

先执行只读 preflight；符合条件后直接执行完整 apply，不需要再次询问确认。云厂商入站防护是部署前置条件，须放行 TCP 443、UDP 8443 与 UDP 2500-3600。部署完成后读取生成的订阅 TCP 端口并提示用户到云厂商后台放行。随后执行一次 resume 和 status，确认不会重复生成凭据，并检查 sing-box、端口跳跃和订阅服务状态。

最后只输出 VLESS Reality 链接、Hysteria2 链接、订阅地址、验证结果和仍需外部客户端确认的边界。明确提醒：云厂商入站防护必须放行 TCP 443、UDP 8443、UDP 2500-3600 和订阅 TCP 端口；VPS 内的 UFW 通过不代表外部 UDP 可达。不要把 SSH 密码、Reality 私钥、服务器 JSON 或完整状态文件写入项目、日志或最终回复。

除非我另外明确要求，否则不要执行 rollback。
```

## 回滚测试

确认节点链接已经另行保存、且允许删除测试节点后，再单独发送：

```text
请使用 $vps-proxy-node-setup 对刚才的测试部署执行 rollback。完成后确认三个自有服务已移除、自有 UFW/NAT 规则已删除、原有 UFW 状态和配置备份已恢复，并说明哪些系统软件包按设计保留。
```
