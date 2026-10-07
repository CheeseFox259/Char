# 示例与开发指令

先导入一个现成示例试用，也可以将需求交给开发助手，按对应的 `AGENTS.md` 制作自己的插件或形象。

| 想做什么 | 示例 | 完整开发指令 |
| --- | --- | --- |
| 接入客户端，监控状态、点击跳转、准确回城或维护集成 | [MiniMax Code CLI / Desktop](integrations/minimax-code/README.md) | [客户端插件](integrations/AGENTS.md) |
| 制作角色、动作、眼睛跟随、主题、气泡皮肤、音效和图标 | [菲比形象](appearance/feibi/README.md) | [自定义形象](appearance/AGENTS.md) |
| 调整已有内置能力的名称、图标与目标应用 | [Safari 配置包](../Resources/Integrations/safari.charintegration) | [配置包](configuration/AGENTS.md) |

## 直接试用

- MiniMax CLI：[完整插件包](integrations/minimax-code/packages/minimax-code-cli.charintegration)。
- MiniMax Desktop：[完整插件包](integrations/minimax-code/packages/minimax-code-desktop.charintegration)。
- 菲比：[完整形象包](appearance/feibi/packages/feibi.charpet)。

从 Char 设置导入整个包目录。客户端插件的安装、重载和逐端验收见 [MiniMax 操作步骤](integrations/minimax-code/USER-ACCEPTANCE.md)；形象的使用见 [菲比操作步骤](appearance/feibi/USER-ACCEPTANCE.md)。MiniMax日常试用无需构建源码；新版菲比使用分层同步接口，需要按其步骤打开配套本地验证版，当前Release暂不支持该新版包。

## 开发自己的作品

将 Char 仓库作为 SDK，告诉开发助手读取上表对应的开发指令，然后描述需求。例如：

> 读取 examples/integrations/AGENTS.md，为我接入「软件」的「CLI / Desktop / 两端」，我使用「终端及是否使用 tmux」，需要「提醒、跳转或回城」。

> 读取 examples/appearance/AGENTS.md，按这张参考图和我的动作、跟随、主题、音效要求制作可导入形象。

指令包含工作目录、契约入口、图标来源、性能要求、基本检查和交付流程。开发助手负责交付完整包和无需终端命令的验收步骤，用户在应用中自行验收。独立工作区需提供 Char SDK 的绝对路径；详细说明见 [开发入口](../docs/development-prompts.md)。

MiniMax 的两端共用源码与客户端 Hook，分别生成运行包；菲比包含素材、绘画层、生成器和形象包。制作新作品时按自己的需求选择能力，示例源码用于参考。素材许可见各示例说明。
