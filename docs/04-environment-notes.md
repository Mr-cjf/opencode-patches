# 环境说明与更新冻结指南

## 为什么留在 v1.17.20

v1.18.30 包含了性能修复，但同时也引入了**新的界面布局**（tabs and home layout）。在 v1.18.x 的应用设置中有明确文案："新设计暂时不支持 Git Worktrees"。

如果选择留在 v1.17.20，需要理解官方的旧界面切换机制：

- 官方提供了一个回退开关 `layoutTransitionEligible === true`，允许用户在新旧界面之间切换。
- 但该开关受**下线日期**控制：`oldInterfaceSunset = 2026-09-14`（已过期）。
- 此外，`oldLayoutEligible` 在首次启动时写入配置文件且**永不重算**。部分用户设备上的值为 `false`，意味着界面锁定已永久生效。

综合来看，旧界面在新版本中被"双锁死"：下线日期过期 + 资格标志不可逆。因此不能通过简单降级或配置回退来同时获得性能修复和旧界面。

## 阻止自动升级

OpenCode Desktop 内置了 electron-updater，启动时自动检查更新并静默下载。如果希望停留在 v1.17.20，需要阻断升级机制。

### 推荐做法（已验证）

1. **清除已下载的更新**：删除 `%APPDATA%\anomalyco\opencode\pending\` 目录下的内容。
2. **修改更新配置**：编辑 `resources\app-update.yml`，将 `repo` 字段改为一个不存在的仓库名，例如：
   ```yaml
   provider: github
   owner: your-non-existent-org
   repo: opencode-desktop-NEVER-EXIST
   ```
   这样更新检查会返回 404，electron-updater 静默失败，不影响任何功能。

### 不要使用的方法

**不要用防火墙阻断 `opencode.exe` 的出站连接。** 这是一个容易踩的坑——OpenCode 的 AI API 请求（如与模型对话）使用的是同一个网络栈。阻断所有出站等于一起封掉了 API 请求，导致无法正常对话。

### 注意事项

- 冻结更新意味着失去后续的所有修复与安全更新（包括未来可能修复的其他性能问题或漏洞）。
- 如果后续决定恢复更新，只需将 `app-update.yml` 改回原来的值。