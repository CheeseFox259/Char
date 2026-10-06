# 自动加载的完整开发指令

三份通用指令与开发目录同放，文件名采用代码 Agent 自动发现的标准 `AGENTS.md`。它们规定制作和验证流程，具体插件/外观目标由使用者当前需求给出。

| 开发类型 | 工作目录与完整指令 |
| --- | --- |
| 集成能力包 | [Resources/Integrations/AGENTS.md](../Resources/Integrations/AGENTS.md) |
| 能力适配器/客户端扩展 | [integrations/AGENTS.md](../integrations/AGENTS.md) |
| 外观形象包 | [Resources/Skins/AGENTS.md](../Resources/Skins/AGENTS.md) |

让支持 `AGENTS.md` 的代码 Agent 在对应目录开始任务，提交想要的目标即可。根目录工作协议与该目录指令共同生效。若从仓库根目录开始，请在任务中明确读取对应文件。

指令文件不是导入包的一部分，也不会打包进应用资源。工具的自动读取取决于其 `AGENTS.md` 支持，不承诺所有客户端均会扫描次级目录。
