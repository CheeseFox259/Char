# MiniMax Code · CLI 与 Desktop 能力插件示例

一份源码生成两个可导入包：

制作自己的客户端插件时，让开发助手读取[完整开发指令](../AGENTS.md)，再描述目标软件和所需行为。本示例的源码和成品包可用于参考。

| 界面 | 包 | workEnd | 承载应用 |
| --- | --- | --- | --- |
| CLI | [minimax-code-cli.charintegration](packages/minimax-code-cli.charintegration) | minimaxcode.cli | Warp，自动添加终端角标 |
| Desktop | [minimax-code-desktop.charintegration](packages/minimax-code-desktop.charintegration) | minimaxcode.desktop | MiniMax Code App |

## 安装

从 [Char Release](https://github.com/CheeseFox259/Char/releases/latest) 下载示例 ZIP，或直接使用本目录的两个包。在 **设置 → 插件 → 导入插件…** 分别选择整个目录，确认信任后打开开关。新用户分别通过维护菜单“安装”，让 MiniMax 加载客户端 Hook 后“自检”；完整 GUI 步骤见 [用户验收](USER-ACCEPTANCE.md)。

两个包版本 **1.1.0**，共用 MiniMax `char-observer` Hook **1.0.0**。从旧版更新仅需同 ID 导入，保留开关，Hook 未改变时无需重装或重载客户端。支持 macOS 13+ arm64/x86_64；监控入口为 Universal 可执行文件，自检、维护和导航仍需要 PATH 中可用的 Node。

## 能力与边界

- monitor：按 CLI/Desktop surface 分流，根会话提醒，子会话不打扰。SessionStart 登记上下文，UserPromptSubmit 运行中，PermissionRequest 审批，Stop 轮次结束，SessionEnd 关闭；正常进程退出由五秒存活检查推断。
- question：映射 PreToolUse/ask_user，但客户端必须暴露该工具；部分 provider 不可用。
- 不声明 failure、rateLimit、contextExhausted，没有结构化来源时不从正文猜测。
- visit：应用级 fallback，CLI 激活 Warp，Desktop 激活 MiniMax Code；无会话级公开定位接口，不声明 origin/exact。应用级回城由 Char 提供。
- lifecycle：只读 inspect，安装/更新备份，共享所有权；最后一个所有者卸载时清理所属 Hook 与事件流，保留用户配置、会话及无关文件。

客户端契约基于 MiniMax Code CLI 0.5.5、Desktop 3.1.1；版本变化时应重新自检。[接口事实与字段](facts.md)。图标来自官方 App 的 `icon.icns`，随包保存 512×512 PNG；CLI 角标由 Char 绘制。

## 实现与重建

```text
native-adapter/       轻量常驻协议与监控、双架构构建
adapter/             按需 Node 维护/导航与参考监控
client-plugin/       MiniMax 本地 Hook 模板
icons/ fixtures/     官方图标与去敏回放
packages/            从唯一源码生成的两个运行包
 tests/              隔离协议、读取、共享维护与性能工具
```

在仓库根运行：

```sh
bash examples/integrations/minimax-code/native-adapter/build.sh
node examples/integrations/minimax-code/build-packages.mjs
node --test examples/integrations/minimax-code/tests/adapter.test.mjs
swift run char-package-check integration examples/integrations/minimax-code/packages/minimax-code-cli.charintegration
swift run char-package-check integration examples/integrations/minimax-code/packages/minimax-code-desktop.charintegration
```

原生客户端 TUI/模型框架为按需检查，不是默认测试。基本检查不修改真实客户端、不发起模型请求；真实 GUI 验收由用户操作。

## 性能

同机隔离测量的原生入口约 **9.6 MiB RSS/端**，物理 footprint 约 **3.3 MiB/端**，空闲 CPU <0.01% 单核；单条追加→协议帧 p95 <2 ms。同条件 Node 参考入口为 52.9 MiB RSS，约降低 82%。不包含 Char/UI/外部客户端；RSS 不等于独占新增 RAM。

Node helper 按需调用后退出；一次自检总耗时约 118 ms，单独测量 helper 生命周期 RSS 高水位约 49.1 MiB，不能算作常驻占用。安装/导航峰值未测。

文件通知驱动、512 KiB/批、最长行 1 MiB，根状态最多 4096 个；超容量淘汰最久未更新的存活推断状态，不阻止新事件转发。普通 helper 2.6 秒、维护 14 秒；监控队列独立。

复测工具 `tests/performance-compare.mjs`、`tests/helper-cost.mjs`，原始输出在忽略的 `reports/`。通用目标与口径见 [性能契约](../../../docs/plugin-performance.md)。
