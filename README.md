# Char

macOS 本机 Agent 注意力桌宠。观察 Claude Code TUI、Codex CLI、Codex Desktop、DeepSeek Harness Desktop、Kimi CLI、Kimi Code App 和 pi 的新状态，为持续停顿显示图形气泡；会话内容不上传，气泡不显示问题或命令原文。

CLI 支持直接在 Warp 或 Warp + tmux 中运行。点击气泡激活对应工作端应用最近位置；成功后清除所点击的提醒并播放破碎动画，应用级跳转仍显示降级标记，失败则保留提醒供重试。精准 Warp pane、Codex 聊天和微信会话能力分别跟踪于 [#10](https://github.com/CheeseFox259/Char/issues/10)、[#11](https://github.com/CheeseFox259/Char/issues/11)、[#12](https://github.com/CheeseFox259/Char/issues/12)。任意前台应用（包括其他 Agent、Warp 与微信，Char 自身除外）都可以成为应用级回城起点。Tabbit 和 VS Code 在可用集成能验证准确来源时保存准确锚点，否则明确降级到同一应用实例；连续访问多个 Agent 保留首次来源。

保存来源后的返回行为称为**回城**：点击桌宠或按 **Ctrl+B**。快捷键仅在 Hold 中注册，无 Hold 时释放。

## 下载与安装

[下载 macOS v0.1.0](https://github.com/CheeseFox259/Char/releases/tag/v0.1.0)：支持 Apple Silicon 和 Intel，要求 macOS 13+。将 Char.app 放到 Applications 后启动；中英设置可随时切换。安装与签名说明见 [发布指南](docs/macos-release.md)。

## 构建与检查

需要 macOS 13+、Swift 6 工具链。安装 Command Line Tools 即可构建，不需要完整 Xcode。集成检查需要 Node.js 和 Python 3.11+。

```sh
scripts/check.sh
scripts/build-app.sh
# Universal ZIP、DMG 和 SHA256
scripts/package-release.sh
```

构建生成 `build/Char.app`，使用本机临时签名。将应用放在稳定位置后运行；右键桌宠打开设置。自启动偏好默认开启，实际启用状态取决于 macOS 登录项授权。该构建尚未进行 Developer ID 签名或公证。

验收程序使用可执行 Swift 检查，失败时返回非零退出码；本机 Command Line Tools 不含 XCTest。演示和冒烟模式的具体命令、已运行证据及未运行的发布检查见 [验证记录](docs/verification.md)。

## 本地集成

- [pi 被动扩展](integrations/pi/README.md)、[Kimi CLI/App Hook](integrations/kimi/README.md)、[DeepSeek Desktop 插件](integrations/deepseek/README.md)：这三类集成需显式启用，原生能力与实测范围见 [新增工作端观察契约](docs/new-agent-observation.md)。
- [观察器与可选官方 Hook](docs/observation-integration.md)：记录格式、各工作端可用信号、显式安装方法。
- [应用激活与返回集成](docs/platform-integration.md)：Tabbit Automation、可选 VS Code 扩展和微信应用级返回。
- [产品规格](docs/spec.md)及[往返行为](docs/attention-trip.md)：过滤、排序、忽略、声音和 Hold 规则。

Hook 和扩展均需显式安装；构建、检查和演示不会改写用户 harness 配置。设置与显示器位置保存在本机；注意力项与 Hold 不跨重启恢复。


### 桌宠、插件与自定义形象

右键桌宠 → Settings 可选择桌面或四个边缘放置，管理统一集成插件、导入和切换形象。拖动靠近边缘会吸附；只有气泡折叠时滚轮才循环。桌宠大小36–88 pt、气泡距离8–72 pt可调，容量自动适配。插件启停和删除立即生效；重新启用只观察新活动。删除配置插件不会修改已经安装在原生 Agent 中的观察 Hook，卸载步骤仍见相应集成 README。

- [配置插件格式](docs/integration-plugin-format.md)：导入 `.charintegration` 目录；可用 `Resources/Integrations/safari.charintegration` 导入 Safari 应用级回城配置示例；所有前台应用本身无需插件也可应用级回城。
- [自定义形象格式](docs/pet-skin-format.md)：导入 `.charpet` 目录；`Resources/Skins/example.charpet` 是完整的七动画示例。设置中的导入会直接切换到新形象。

Char 保持显示在所有 Space。桌宠跨屏动作和回城反馈采用弹性动画；整屏 Space 切换速度由 macOS 控制，不提供自定义曲线。


## 开发者与完整文档

- [文档索引](docs/README.md)：使用、实现、集成、性能、验收与平台评估。
- [实现机制与性能摘要](docs/architecture.md)。
- [集成插件开发指南](docs/plugin-development.md)、[外观包开发指南](docs/appearance-development.md)。
- [可直接使用的完整开发提示词](docs/development-prompts.md)：配置包、新原生协议/准确返回、七动画形象包。
- [Windows 移植可行性](docs/windows-feasibility.md)：需要新的桌面壳与平台适配，本版本尚无 Windows 构建。

开发包可调用生产校验器检查，不访问用户目录：

~~~sh
swift run char-package-check integration Resources/Integrations/safari.charintegration
swift run char-package-check skin Resources/Skins/example.charpet
~~~

当前集成是配置包，只选择七种已编译观察协议与内置回城适配器；新增Agent协议或新的准确回城需要源码扩展。形象包仅包含清单和图片，不执行代码。完整格式、限制和安装/回退见开发指南。

正常包的USB接收器滚轮首格、连续、反向和轻动已由用户确认正常；有线连接的输入送达问题仍记录在诊断中。性能历史有效样本与局限见文档，未承诺所有机器相同CPU占用。
