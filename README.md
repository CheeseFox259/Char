# Char

macOS 本机 Agent 注意力桌宠。观察 Claude Code TUI、Codex CLI、Codex Desktop、DeepSeek Harness Desktop、Kimi CLI、Kimi Code App 和 pi 的新状态，为持续停顿显示图形气泡；会话内容不上传，气泡不显示问题或命令原文。

CLI 支持直接在 Warp 或 Warp + tmux 中运行。首版点击气泡激活对应工作端应用最近位置，显示降级标记并保留未查看提醒。精准 Warp pane、Codex 聊天和微信会话能力分别跟踪于 [#10](https://github.com/CheeseFox259/Char/issues/10)、[#11](https://github.com/CheeseFox259/Char/issues/11)、[#12](https://github.com/CheeseFox259/Char/issues/12)。Tabbit 和 VS Code 仅在可用集成能验证准确来源时建立 Hold；微信使用明确降级的应用实例；Warp 应用级来源不建立 Hold。

保存来源后的返回行为称为**回城**：点击桌宠或按 **Ctrl+B**。快捷键仅在 Hold 中注册，无 Hold 时释放。

## 构建与检查

需要 macOS 13+、Swift 6 工具链。安装 Command Line Tools 即可构建，不需要完整 Xcode。集成检查需要 Node.js 和 Python 3.11+。

```sh
scripts/check.sh
scripts/build-app.sh
```

构建生成 `build/Char.app`，使用本机临时签名。将应用放在稳定位置后运行；右键桌宠打开设置。自启动偏好默认开启，实际启用状态取决于 macOS 登录项授权。该构建尚未进行 Developer ID 签名或公证。

验收程序使用可执行 Swift 检查，失败时返回非零退出码；本机 Command Line Tools 不含 XCTest。演示和冒烟模式的具体命令、已运行证据及未运行的发布检查见 [验证记录](docs/verification.md)。

## 本地集成

- [pi 被动扩展](integrations/pi/README.md)、[Kimi CLI/App Hook](integrations/kimi/README.md)、[DeepSeek Desktop 插件](integrations/deepseek/README.md)：这三类集成需显式启用，原生能力与实测范围见 [新增工作端观察契约](docs/new-agent-observation.md)。
- [观察器与可选官方 Hook](docs/observation-integration.md)：记录格式、各工作端可用信号、显式安装方法。
- [应用激活与返回集成](docs/platform-integration.md)：Tabbit Automation、可选 VS Code 扩展和微信应用级返回。
- [产品规格](docs/spec.md)及[往返行为](docs/attention-trip.md)：过滤、排序、忽略、声音和 Hold 规则。

Hook 和扩展均需显式安装；构建、检查和演示不会改写用户 harness 配置。设置与显示器位置保存在本机；注意力项与 Hold 不跨重启恢复。
