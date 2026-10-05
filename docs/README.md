# Char 文档索引

当前版本：macOS原生桌宠；七工作端被动观察，统一集成配置与数据形象包。源码推送与本地验证不代表签名、公证或全环境发布验收已完成。

## 使用与开发

| 目的 | 文档 |
| --- | --- |
| 安装、构建、操作、当前能力边界 | [项目README](../README.md) |
| 一次注意力往返与首次来源 | [往返行为](attention-trip.md) / [领域术语](../CONTEXT.md) |
| 当前实现机制、模块地图、本地数据和性能摘要 | [实现总览](architecture.md) |
| 自制配置插件 / 新Agent / 新准确返回 | [集成插件开发指南](plugin-development.md) |
| 自制桌宠形象与动作 | [外观包开发指南](appearance-development.md) |
| 随开发目录自动加载的通用指令 | [三份 AGENTS.md](development-prompts.md) |
| 生产格式细则 | [集成配置v2](integration-plugin-format.md) / [形象包v1](pet-skin-format.md) |
| Windows可行性、风险与分阶段门槛 | [Windows评估](windows-feasibility.md) |

## 原生能力与安装

- [信号可行性矩阵](signal-feasibility.md)、[新增客户端观察合同](new-agent-observation.md)：哪些信号已确认，哪些缺失。
- [观察集成](observation-integration.md)、[平台集成](platform-integration.md)、[准确导航边界](native-navigation-feasibility.md)。
- [pi](../integrations/pi/README.md)、[Kimi CLI/App](../integrations/kimi/README.md)、[DeepSeek](../integrations/deepseek/README.md)、[已批准安装记录](native-integration-activation.md)。
- [ADR](adr)：本地处理、单返回锚点、统一集成与自由来源等决定；[产品规格](spec.md)是原始需求，当前批准降级与验收结果见下列记录。

## 发布

- [macOS v0.1.0 安装、构建与发布证据](macos-release.md)。

## 性能与验收

- [性能组成、历史实测与下一步优化](companion-performance-2026-10-04.md)：CPU/RSS、场景/版本、采样方法和限制。
- [轨道/距离/统一集成验收](orbit-verification-2026-10-04.md)：实际设置、缓存与回归、接收器正常包实体通过。
- [有线滚轮送达诊断](wheel-diagnosis-2026-10-05.md)：受控实验、连接方式更正、探针清理；有线原因未定。
- [本轮图标/文档/工具验收](developer-docs-verification-2026-10-05.md)。
- 历史：[初版验证](verification.md)、[2026-10-03验收](acceptance-2026-10-03.md)、[2026-10-04验收](acceptance-2026-10-04.md)、[视觉重构](redesign-verification-2026-10-04.md)、[交互修正](companion-polish-verification-2026-10-04.md)。

历史记录中的待测/失败结论只代表当时版本，不覆盖后续明确复验；后续“通过”也只覆盖注明的配置，不能外推其他客户端和连接方式。

- [形象与软件图标验证记录](appearance-icons-verification-2026-10-05.md)。
