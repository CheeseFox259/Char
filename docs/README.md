# Char 文档索引

当前版本：macOS原生桌宠；七工作端被动观察，v0.3.0 v3集成能力插件与v2外观能力包。源码推送与本地验证不代表签名、公证或全环境发布验收已完成。

## 使用与开发

| 目的 | 文档 |
| --- | --- |
| 安装、构建、操作、当前能力边界 | [项目README](../README.md) |
| 一次注意力往返与首次来源 | [往返行为](attention-trip.md) / [领域术语](../CONTEXT.md) |
| 当前实现机制、模块地图、本地数据和性能摘要 | [实现总览](architecture.md) |
| 自制配置插件 / 新Agent / 新准确返回 | [集成插件开发指南](plugin-development.md) |
| 进程接口与安装维护 | [能力协议v1](capability-adapter-protocol.md) |
| 自制桌宠形象与动作 | [外观包开发指南](appearance-development.md) |
| 随开发目录自动加载的通用指令 | [三份 AGENTS.md](development-prompts.md) |
| 生产格式细则 | [集成插件v3](integration-plugin-format.md) / [形象包v1/v2](pet-skin-format.md) / [外观完整API](appearance-v2-api.md) |
| Windows可行性、风险与分阶段门槛 | [Windows评估](windows-feasibility.md) |

## 原生能力与安装

- [信号可行性矩阵](signal-feasibility.md)、[新增客户端观察合同](new-agent-observation.md)：哪些信号已确认，哪些缺失。
- [观察集成](observation-integration.md)、[平台集成](platform-integration.md)、[准确导航边界](native-navigation-feasibility.md)。
- [pi](../integrations/pi/README.md)、[Kimi CLI/App](../integrations/kimi/README.md)、[DeepSeek](../integrations/deepseek/README.md)、[已批准安装记录](native-integration-activation.md)。
- [ADR](adr)：本地处理、单返回锚点、统一集成与自由来源等决定；[产品规格](spec.md)是原始需求，当前批准降级与验收结果见下列记录。

## 发布

- [v0.3.0 外观能力](release-notes-0.3.0.md)、[本轮验证](appearance-v2-verification-2026-10-07.md)。
- [v0.2.2 边缘宿主修复](release-notes-0.2.2.md)。

- [v0.2.0 Release 发布、替换与集成迁移](release-verification-0.2.0.md)。

- [macOS 安装、构建与发布](macos-release.md)。
- [v0.1.2 Release 发布、下载安装与实测](release-verification-0.1.2.md)。

## 性能与验收

- [气泡状态连续性修复](bubble-state-continuity-2026-10-06.md)：过滤期持续可见、状态图层过渡与回归检查。

- [能力插件验证](capability-plugins-verification-2026-10-06.md)：动态客户端、进程协议、稳定生命周期、原生App路径与成本。

- [设置与前台查询性能优化实测](performance-optimization-2026-10-06.md)：设置 CPU 同场景从 37.79% 降至 2.65%、预览生命周期、轻量身份查询与验证范围。
- [v0.1.1 Release 优化前性能报告](performance-0.1.1-2026-10-06.md)：实际安装包 CPU/RSS、设置静止开销、多屏查询和优化顺序。
- [性能组成、历史实测与下一步优化](companion-performance-2026-10-04.md)：CPU/RSS、场景/版本、采样方法和限制。
- [轨道/距离/统一集成验收](orbit-verification-2026-10-04.md)：实际设置、缓存与回归、接收器正常包实体通过。
- [有线滚轮送达诊断](wheel-diagnosis-2026-10-05.md)：受控实验、连接方式更正、探针清理；有线原因未定。
- [本轮图标/文档/工具验收](developer-docs-verification-2026-10-05.md)。
- 历史：[初版验证](verification.md)、[2026-10-03验收](acceptance-2026-10-03.md)、[2026-10-04验收](acceptance-2026-10-04.md)、[视觉重构](redesign-verification-2026-10-04.md)、[交互修正](companion-polish-verification-2026-10-04.md)。

历史记录中的待测/失败结论只代表当时版本，不覆盖后续明确复验；后续“通过”也只覆盖注明的配置，不能外推其他客户端和连接方式。

- [形象与软件图标验证记录](appearance-icons-verification-2026-10-05.md)。

## v0.2.0

- [版本变化](release-notes-0.2.0.md)
- [能力插件实现与验证](capability-plugins-verification-2026-10-06.md)

- [设置性能面板](performance-dashboard.md)：实时CPU/RSS、平均/峰值及归属口径。
