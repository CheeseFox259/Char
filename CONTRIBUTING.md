# Contributing to Char

Issues 用于缺陷、客户端接口与需求讨论。请提供版本、客户端/终端、复现步骤、预期和实际行为；截图避免包含会话正文、凭据或私人信息。

## 从哪里开始

- 新客户端：先读 [examples/integrations/AGENTS.md](examples/integrations/AGENTS.md) 与 [插件指南](docs/plugin-development.md)，默认在独立集成目录开发，以 Char 为 SDK。
- 新形象：先读 [examples/appearance/AGENTS.md](examples/appearance/AGENTS.md) 与 [外观指南](docs/appearance-development.md)。
- 已有配置能力：读 [examples/configuration/AGENTS.md](examples/configuration/AGENTS.md)。
- 修改宿主：阅读 [CONTEXT.md](CONTEXT.md)、[架构](docs/architecture.md) 与相关 ADR；只改变当前需求涉及的模块。

开发过程中先跑相关检查；最终提交运行 `bash scripts/check.sh`。界面改动需提供真实 Char 截图与检查范围，性能改动提供相同条件的前后测量。构建/回放不替代用户的真实客户端验收。

PR 说明：行为变化、原因、验证、未测项及迁移方式。新增插件/形象包含可导入包、唯一源码与重建方法，遵守图标来源、信号精度、性能及卸载所有权契约。

本地会话导出、实验报告、历史计划和用户数据放在 `.local-archive/`，该目录不上传。示例输出只包含运行资源，原始性能样本放在忽略的报告目录。
