<p align="center">
  <img src="Resources/Icons/Char.png" width="136" alt="Char 方块桌宠" />
</p>
<h1 align="center">Char</h1>
<p align="center"><strong>Agent 需要你时看一眼，处理后回到原处。</strong></p>
<p align="center">A local macOS companion for your AI agents.</p>
<p align="center">
  <a href="https://github.com/CheeseFox259/Char/releases/latest"><img src="https://img.shields.io/github/v/release/CheeseFox259/Char?display_name=tag" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black" alt="macOS 13+" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT" /></a>
</p>
<p align="center">
  <a href="https://github.com/CheeseFox259/Char/releases/latest"><strong>下载 macOS 版</strong></a> ·
  <a href="docs/README.md">使用指南</a> ·
  <a href="docs/development-prompts.md">制作插件与形象</a> ·
  <a href="https://github.com/CheeseFox259/Char/issues">反馈</a>
</p>

---

同时使用几个 AI Agent，却总要切换窗口查看进度？Char 将客户端状态放在桌宠旁的图标气泡里：提问、审批或一轮结束时提醒你；点气泡去处理，再按 **Ctrl+B 回城**，回到离开前的工作界面。

<p align="center"><img src="docs/assets/companion-demo.png" width="520" alt="Char 桌宠与 Claude、Codex、pi、Kimi 四个图标气泡" /></p>

<p align="center">Claude · Codex · pi · Kimi</p>

## 它能帮你做什么

- **少切窗口。** 一眼看见多个客户端的状态；CLI 带小终端角标，方便和桌面版区分。
- **处理完回到原处。** 连续查看多个 Agent，仍能回到最初的工作界面；也可在设置中选择最近起点。
- **留在你工作的屏幕上。** 桌面悬浮或四边探头，跟随跨屏焦点；调整大小、气泡距离，滚轮切换折叠气泡。
- **换成自己的桌宠。** 自定义角色、动画、图标、音效、主题和气泡外观，支持鼠标跟随与交互动作。
- **按需添加客户端。** 插件可以直接导入、启停、更新和删除，无需重启 Char。
- **本地运行。** Char 不调用模型、不发送遥测，气泡不展示对话正文。提醒音、过滤时间和减少动态效果都可调整。

## 安装与上手

支持 **macOS 13+、Apple Silicon 和 Intel**。

1. 从 [Release](https://github.com/CheeseFox259/Char/releases/latest) 下载 DMG，把 **Char.app 拖入“应用程序”**；也可下载 ZIP，解压后复制应用。
2. 打开 Char，从状态栏图标或桌宠右键菜单进入设置，选择中文 / English，并调整桌宠位置。
3. 在 **设置 → 插件** 启用需要的客户端。有安装按钮的集成，按菜单提示安装并重载客户端。
4. **点击气泡 → 处理 Agent → Ctrl+B 回城**。右键气泡可以忽略提醒。

> macOS 版本目前未经过 Apple 公证，首次启动可能需要在 Finder 中右键应用并选择“打开”

遇到首次启动、辅助功能或自动化权限问题，请查看 [安装指南](docs/macos-release.md)。默认过滤时间为 10 秒，可在设置中调整。成功跳转会清除点击的提醒；回城起点在退出 Char 后清除。

## 支持的客户端

| 客户端 | 如何使用 |
| --- | --- |
| Claude Code | 启用内置插件，[接入说明](docs/observation-integration.md) |
| Codex CLI、Codex Desktop | 启用内置插件，[接入说明](docs/observation-integration.md) |
| Kimi CLI、Kimi Code App | 安装内置集成，[Kimi 指南](integrations/kimi/README.md) |
| DeepSeek Harness Desktop | 安装内置集成，[DeepSeek 指南](integrations/deepseek/README.md) |
| pi | 安装内置扩展，[pi 指南](integrations/pi/README.md) |
| MiniMax Code CLI、Desktop | 从示例包导入，[MiniMax 指南](integrations/minimax-code/README.md) |
| 其他客户端 | 可自行制作插件，或让开发助手按[插件指南](docs/plugin-development.md)接入 |

CLI 支持 **Warp** 和 **Warp + tmux**。其他终端也可通过自定义插件接入。不同客户端能够提供的状态有所不同，见 [提醒类型](docs/signal-feasibility.md)。

### 回城能回到哪里

普通应用可回到原应用；原进程需要保持运行。Tabbit 可回到原标签，VS Code 可回到支持的编辑器或终端标签，需要安装相应集成并完成授权。自定义插件也可以提供准确定位。

点击 Agent 气泡时，通常打开对应应用最近使用的位置；提供准确导航的插件可定位到具体会话。更多见 [回城指南](docs/attention-trip.md)。

## 添加自己的插件

你使用的软件不在列表里，也可以接入 Char。插件可提供状态提醒、跳转、准确回城和安装维护，按需求组合。

**你只需要描述软件和使用方式。** 让开发助手读取 [integrations/AGENTS.md](integrations/AGENTS.md)，告诉它软件名称、CLI 或桌面版，以及希望收到哪些提醒。开发完成后会交付可导入的 `.charintegration` 包和操作说明。

在 **设置 → 插件 → 导入插件…** 选择完整包。需要客户端集成时，再通过该插件的维护菜单安装。插件可随时关闭或删除；添加新客户端无需重新编译 Char。

[MiniMax CLI/Desktop 示例](integrations/minimax-code/README.md)包含成品包和源码。详细接口见 [插件开发指南](docs/plugin-development.md)。第三方插件会运行本机代码，请仅导入可信来源。

## 换个桌宠

<p align="center"><img src="docs/assets/feibi-companion-demo.png" width="520" alt="菲比形象与 Claude、Codex、pi、Kimi 四个图标气泡" /></p>

形象包可自定义角色和表情、闲置与四边动作、眼睛跟随、软件图标、主题、气泡皮肤、音效和交互。选择形象后，桌宠、状态栏与软件图标一起变化。

在 **设置 → 桌宠与动效 → 导入形象…** 选择 `.charpet` 包即可使用。[菲比示例](examples/appearance/feibi/README.md)提供七组动画、探头图标，以及点击和提醒语音；声音遵守静音开关和播放冷却。

想制作自己的角色？将参考图和要求交给开发助手，让它读取 [Resources/Skins/AGENTS.md](Resources/Skins/AGENTS.md)。也可以查看 [制作指南](docs/appearance-development.md)和[可自定义范围](docs/appearance-customization.md)。

**MiniMax 插件与菲比形象**都在 [Release](https://github.com/CheeseFox259/Char/releases/latest) 的示例 ZIP 中提供，解压后可直接导入。更新已有形象时，先删除旧包再导入；软件图标同步可能需要重新授权辅助功能，详见 [安装指南](docs/macos-release.md)。

## 运行占用

内置客户端共用观察器，形象资源按需缓存，不为每个内置客户端启动常驻进程。

| 本机测量场景 | 内存 RSS | 平均 CPU（单核） |
| --- | ---: | ---: |
| 默认桌宠、4 个演示气泡与设置窗口 | 27.6–27.7 MiB | 0.073% |
| MiniMax 示例适配器空闲，每个工作端 | 约 9.6 MiB | <0.01% |

桌宠样本只测呈现，不包含真实客户端观察和焦点查询。

Char 的占用会随形象、气泡数量、插件和设置窗口变化，启动时可能出现短暂峰值。打开 **设置 → 性能** 可以查看当前值、平均值和峰值；RSS 包含共享内存，并不等于独占用量。测量条件与机制见 [性能说明](docs/performance.md)。

## 参与项目

欢迎提交问题、插件、形象包和改进建议。开发环境与构建方式见 [贡献指南](CONTRIBUTING.md)，技术细节见 [实现架构](docs/architecture.md)，安全问题见 [SECURITY.md](SECURITY.md)。目前提供 macOS 应用；Windows 相关计划见 [平台评估](docs/windows-feasibility.md)。

## 许可与致谢

[MIT](LICENSE) © 2026 CheeseFox。客户端名称、图标和角色素材属于各自权利人。

菲比语音来自 [Genius-Society/phoebe_chubby](https://github.com/Genius-Society/phoebe_chubby)，遵循 [CC BY-NC-SA 4.0](https://github.com/Genius-Society/phoebe_chubby/blob/main/LICENSE)。素材来源与许可见 [说明](examples/appearance/feibi/ASSET-NOTICES.md)。
