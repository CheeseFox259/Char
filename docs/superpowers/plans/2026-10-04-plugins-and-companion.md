# Plugins and Companion Implementation Plan

> 沿用使用者指定的 implement-spec：独立实现 worktree、根分支集成、双轴审查与受影响路径验证；此计划直接执行，不另设启动批准。

**Goal:** 来源和 Agent 配置可导入、启停、删除；桌宠与轨道气泡按参考图重新实现，支持可替换形象和桌面/边缘动效。

**Architecture:** 配置插件是版本化本地 manifest，不执行任意导入代码。适配器协议仍由 Char 提供；来源插件可选择准确 Tabbit/VS Code 或应用级来源，Agent 插件选择现有七种原生协议并配置目标应用。外部桥接仍使用已授权的显式原生集成。形象为独立验证的 PNG 动画包。AppKit 窗口承载自绘、可中断弹性动画；状态和布局放在纯模型中验证。

**Tech Stack:** SwiftPM / Foundation / AppKit / SwiftUI / Core Animation，现有契约执行器；无新网络依赖。

## 明确行为

参考 `docs/reference/visual-motion.png`：奶油色粗深色描边圆角方块，两根竖线眼睛、两只小圆脚；idle 呼吸/挤压/弹起/微倾斜/眨眼。圆形透明高光气泡使用所属 Agent 图标，固定 52 pt；desktop 360° 轨道，edge 为向屏内半圈。轨道最多 6 个位置，超额时最后一个是溢出气泡，含最多 3 个独立可点小气泡；滚轮循环旋转可达所有工作端，保留未查看/原因/过去/降级语义。

桌面默认放置；拖近四条屏幕边缘吸附，也可在设置明确选择 desktop/left/right/top/bottom。按屏保存桌宠中心与放置边缘。跨屏分两阶段：desktop 缩小淡出→目标弹性出现；edge 缩回→目标边缘探出，目标窗口不沿屏幕连线滑动。减少动态效果关闭循环变形，过渡改为短淡入淡出。

Space 策略选持续存在：canJoinAllSpaces + stationary，macOS 14+ canJoinAllApplications，避免每次 Space 通知重定位/隐藏。回城即刻发起原生激活，同时桌宠回城反馈使用弹性曲线，不人为增加等待。公开 AppKit 不提供整屏 Space 切换曲线控制；系统切换动画不能伪装成 Char 已控制。来源 PID、准确验证及失败 Hold 重试保留。

## 任务图与文件职责

```text
A 配置插件 registry ─┐
B 自定义形象标准 ───┼→ D Runtime / Settings / Platform 集成 → E 实际包验收与审查
C 桌宠/轨道/动画 ───┘
```

### A 配置插件

文件：新增 `Sources/CharCore/IntegrationPlugins.swift`、`Tests/CharCoreChecks/PluginChecks.swift`、`docs/integration-plugin-format.md`；实现者不改 Runtime/Settings/Package/main 检查入口。

- [ ] 定义 `IntegrationPlugin: Codable, Identifiable`，字段 schemaVersion=1、id、name、kind(agent/source)、workEnd(Agent 必需)、bundleIdentifier、sourceAdapter(Tabbit/VSCode/application)、可选 icon，相对路径图标只接受包内 PNG。
- [ ] `IntegrationPluginStore(directory:)` 提供加载/导入目录/启停/删除/恢复内置。首次注册七 Agent+三来源；删除留下 tombstone，重启不自动复活；显式恢复才重新安装。
- [ ] 拒绝重复 ID、同一工作端多个启用配置、未知版本、缺字段/无效 bundleID/越界图标和软链接；失败不影响已安装配置。
- [ ] 实际临时目录契约：启停/删除/重新实例化、导入/重复/错误和 asset 可达，配置原子写入。

### B 自定义形象

文件：新增 `Sources/CharPlatform/PetSkins.swift`、`Tests/CharPlatformChecks/PetSkinChecks.swift`、`docs/pet-skin-format.md` 和 `Resources/Skins/example.charpet`；不改 Runtime/Settings/main。

- [ ] `PetSkinStore(directory:)` 管理默认内置、目录导入、选择、删除、重启保留；默认形象不可删。
- [ ] 版本 1 manifest：id/name/schemaVersion、canvasSize、anchor、clips idle/press/return/depart/arrive/edgePeek/edgeHide，每 clip 明确 frames 与 fps；idle 有眨眼/呼吸/压缩/回弹的制作要求。包内 PNG RGBA 等尺寸，长度/帧率/像素尺寸/总字节受明确标准约束。
- [ ] 加载器检查版本、必需 clips、缺帧、格式/尺寸/alpha、路径越界/软链接、唯一 ID；先完整验证再安装，错误不改当前形象。公开 `image(for:clip:elapsed:)` 可直接被自绘 renderer 调用。
- [ ] 制作一个可直接导入的示例动画包，用同一标准验证，而非只给空模板。

### C 视觉与动画

文件：替换 `Sources/CharApp/CompanionPanel.swift`，新增 `Sources/CharApp/CompanionMotion.swift`、`Sources/CharCore/CompanionLayout.swift`、`Tests/CharCoreChecks/CompanionLayoutChecks.swift`；不改 Runtime/Settings，约定 root 提供 petPlacement、selectedPetSkin、agentIcon(for:)。

- [ ] 保留 surface.pet / surface.buttons / refresh() 接口，加入 `transition(to:placement:animated:)` 与 `returnFeedback()`，窗口透明区域点穿，只有可见 pet/bubble 参与 hitTest。
- [ ] 纯布局决定轨道、6 槽溢出、三小气泡、循环 offset；所有工作端可经滚轮和点击到达，edge 不裁切交互槽。
- [ ] 正式默认矢量圆角方块与光泽圆泡；图标、原因/数量/过去/降级都保留。固定 hit area 随弹性位置，缩放只改变绘制，不阻断事件。
- [ ] 自绘 idle 包含柔和呼吸、压缩回弹、微倾斜及眨眼。spring/非线性 motion 可中断，使用单一共用刷新时钟，Reduce Motion 停止循环。
- [ ] Space panel 支持全部 Spaces，保持置顶，不自行捕获用户屏幕或改变系统动画设置。

### D 集成（根代理）

文件：Runtime.swift、SettingsView.swift、Platform.swift、LocalObservationPoller.swift、AttentionRouter.swift、测试入口与 spec/README。

- [ ] 设置有桌面/四边选择、插件启停/导入/删除/恢复、形象预览/导入/选择/删除；即时生效，无需重启。UI 显示来源准确/应用级能力。
- [ ] 源插件立即门控捕获/验证/回城；卸下当前来源清 Hold。Agent 卸下停止读取其 journal/适配，立即移除其注意力和运行计数；重新加载以当时 EOF 基线拒绝历史回放。已禁用流不能经竞态回流到 router。
- [ ] 保留原生独立会话身份、首来源 Hold、应用降级未查看、Ctrl+B Hold-only。自定义应用级来源可保存同 PID 的应用锚点，名称显示来自 manifest。
- [ ] 多屏位置保存以 pet 中心为基准；桌面切换不重定位，实际显示器变化才触发 depart/arrive。

### E 收口

- [ ] `scripts/check.sh`：插件/形象/布局新增行为契约及已有注意力、来源、原生观察通过。
- [ ] `scripts/build-app.sh`、严格 codesign、实际包 smoke：旧热键/来源保护+新溢出循环、skin 导入、四边放置和中断动画；无外部调用。
- [ ] CUA 实际展示 desktop、四边、overflow、设置插件热卸载/恢复、示例皮肤导入。截取本应用窗口，不读用户聊天。
- [ ] 用户实体手动 Space/触摸板验证持续存在和回城感受；没有环境/接口的整屏动画控制明确记限制，不能把 mock 转成实机通过。
- [ ] 双轴审查、修复、文档/Issue/PR 同步；只在实现检查确实完成后 ready。
