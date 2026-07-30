# 其他 Agent 独立测试提示词

将测试包中的 `vps-proxy-node-setup` 文件夹安装或加载为 Skill，然后把下面这段话和一台全新测试 VPS 的 SSH 信息交给另一个 Agent。

## 完整部署测试

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

## 回滚测试

确认节点链接已经另行保存、且允许删除测试节点后，再单独发送：

```text
请使用刚才安装的 Skill，对刚才这台测试 VPS 执行 rollback。完成后只汇报回滚验证结果。
```
