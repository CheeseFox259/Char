# Char 文档

使用指南、自定义开发接口和维护资料。

## 使用

- [安装与发布](macos-release.md)：DMG/ZIP、首次打开、权限、签名与构建。
- [回城规则](attention-trip.md)：首次/最近起点、应用级与准确返回。
- [客户端接入](observation-integration.md)、[原生信号矩阵](signal-feasibility.md)、[平台导航](platform-integration.md)。
- [形象自定义范围](appearance-customization.md)、[性能面板](performance-dashboard.md)、[性能与机制](performance.md)。

## 自定义开发

| 目标 | 入口 | 可导入示例 |
| --- | --- | --- |
| 新客户端的监控、跳转、回城或安装维护 | [插件开发指南](plugin-development.md) / [性能要求](plugin-performance.md) | [MiniMax CLI + Desktop](../examples/integrations/minimax-code/README.md) |
| 已有能力的名称、图标与目标应用 | [配置包格式](integration-plugin-format.md) | [配置包目录](../Resources/Integrations) |
| 新角色、动作、主题、跟随或气泡皮肤 | [形象开发指南](appearance-development.md) / [完整 API](appearance-api.md) | [菲比](../examples/appearance/feibi/README.md) |
| 使用开发 Agent | [三份开发指令](development-prompts.md) | 在对应目录读取 AGENTS.md 后提出需求 |

契约：[适配器协议](capability-adapter-protocol.md)、[插件格式](integration-plugin-format.md)、[形象格式](pet-skin-format.md)、[图标获取](plugin-icon-sourcing.md)。

交付：[基本验收](plugin-basic-acceptance.md) → [用户 GUI 验收](plugin-user-acceptance.md)。

## 维护

- [架构](architecture.md)、[领域术语](../CONTEXT.md)、[架构决定](adr)。
- [新增客户端信号](new-agent-observation.md)、[准确导航边界](native-navigation-feasibility.md)、[Windows 可行性](windows-feasibility.md)。
- [1.2.0 版本说明](release-notes-1.2.0.md)、[1.1.0 版本说明](release-notes-1.1.0.md)、[1.0.0 版本说明](release-notes-1.0.0.md)、[贡献指南](../CONTRIBUTING.md)、[安全与信任](../SECURITY.md)。
