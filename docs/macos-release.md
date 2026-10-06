# macOS v0.2.1

## 下载与安装

[GitHub Release](https://github.com/CheeseFox259/Char/releases/tag/v0.2.1) 提供 Universal ZIP、DMG 和 SHA256SUMS。两个可执行文件均包含 arm64 与 x86_64，要求 macOS 13 或更高版本。Intel 架构已编译并检查，运行验收在 Apple Silicon 上进行。附件由 GitHub Actions 构建，安装无需本地工具链。

1. 下载 DMG，将 Char.app 拖到系统“应用程序”（`/Applications`）；或解压 ZIP 后复制到同一位置。`~/Applications` 是独立的用户应用目录，系统“应用程序”窗口不会直接列出其中的 App。
2. 从这个固定位置启动，避免同时运行旧的 build/Char.app。
3. 在桌宠右键菜单或状态栏打开设置，选择中文或 English，检查“登录时启动”的实际状态。
4. 原生 Agent 观察 Hook 仍需按各集成指南显式安装；首次安装不会自动改写 Agent 配置。

本版本只有 ad hoc 签名，**没有 Developer ID 签名或 Apple 公证**。从 GitHub 下载后 macOS 可能阻止首次运行；确认来源后按系统“隐私与安全性”中的“仍要打开”流程操作。不需要关闭 Gatekeeper。Apple 的说明：[打开未知开发者的 App](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)。

可先验证下载内容：

```sh
shasum -a 256 -c SHA256SUMS
```

## 本次变化

- 修复运行中到停顿/轮次结束的过滤期间气泡暂时消失。气泡持续可见，等待确认不会提前生成提醒；已查看、忽略与关闭规则继续有效。
- 状态标记独立于壳体和 Agent 图标，使用 280 ms 非线性交叉淡化与 320 ms 轻微弹性过渡；减少动态效果时仅 120 ms 淡化。

### v0.2.0 已包含的变化

- v3 能力插件支持监控、访问、准确起点与安装维护；导入、启停、同 ID 更新、删除即时生效，无需重启 Char。旧配置包与形象包兼容。
- pi、Kimi CLI/App、DeepSeek 的本地集成支持自检、安装、更新与移除，使用稳定运行目录，保留私有备份。已有客户端可能需要重载。
- 修复 pi 错误写入终端显示与过期 Hook 路径迁移，补充插件骨架、校验、回放及三份通用开发指令。
- 新增首次/最近/关闭回城起点策略与应用级起点选项。

### v0.1.2 已包含的变化

- 设置预览局部更新，Ctrl+B 状态只在变化时发布；静止设置的七气泡演示 CPU 对照由 37.79% 降至 2.65%。不可见预览跳过绘制，减少动态效果与关闭设置时停止时钟。测试条件与范围见 [性能实测](performance-optimization-2026-10-06.md)。
- 前台身份与显示器几何查询分开，来源捕获与回城状态检查减少重复几何读取；焦点跟随继续使用 150 ms 几何检查。

### v0.1.1 已包含的变化

- 默认项目与软件图标采用右边缘探头的桌宠形象。
- 形象包可声明 appIcon，运行中的应用图标、状态栏图标和设置预览随形象切换；旧形象包自动生成图标。删除所选形象会恢复默认。Finder/Launchpad 使用签名包内的默认图标。
- 新增 tag 触发的远端发布工作流：检查、Universal 构建、ZIP/DMG/校验和检查后上传草稿，下载实际产物验收后发布。

### v0.1.0 已包含的修复

- ServiceManagement 的未找到状态允许尝试注册；注册前刷新当前安装包的 LaunchServices 记录。界面显示实际启动状态。
- 焦点跟随优先使用 AX 焦点窗口；无权限时使用前台应用最前面的可见普通窗口几何。跨屏窗口按相交面积选择屏幕，保持共享放置方式与现有弹性过渡。
- 左键成功访问后清除点击项，保留其他项与首次回城来源。应用级成功也清除，但仍使用应用级反馈图标；失败保留重试。
- 破碎使用短暂的图像切片和合成器变换/透明度，最多18片、420ms清理；减少动态效果时淡出。
- 中英设置即时切换并持久化，菜单和 Char 自有状态文案跟随语言；权限系统弹窗及底层 OS 错误使用系统语言。
- 说明段落移至文档，设置保留控制名称、必要状态、错误和图例。插件与导航反馈共用 scope / macwindow / exclamationmark.circle.fill。

## 重建

需要 Swift 6 工具链和 macOS Command Line Tools，检查还需要 Node.js、Python。

```sh
scripts/check.sh
scripts/package-release.sh
```

产物位于 `build/release/0.2.1/`。打包脚本分别编译两种架构，通过 lipo 合并 Char 与 char-hook，重新签名，制作 ZIP、只读 DMG 和校验和；不会复制开发 AGENTS.md 或安装用户观察 Hook。常规安装使用已发布附件，不需要执行重建命令。

## 验证边界

设置与查询优化证据见 [性能实测](performance-optimization-2026-10-06.md)，图标行为证据见 [图标验证记录](appearance-icons-verification-2026-10-05.md)，先前功能证据见 [v0.1.0 验证记录](release-verification-0.1.0.md)。没有执行真实注销/重新登录、Intel 实机或全套 VoiceOver；这些不能由编译或烟测替代。演示性能结果不代表真实观察模式的相同降幅。
