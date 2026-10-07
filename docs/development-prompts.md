# 让 Agent 直接开始插件开发

用户提出目标，三份通用 `AGENTS.md` 负责工作目录、实施、基本验收和交付。指令不绑定产品、现成集成或某种造型；第三方能力插件无需修改 Char 源码，自定义形象通过声明式资源和受限Char事件/动作接口扩展。

| 需求 | 开发指令 | 工作区 |
| --- | --- | --- |
| 新客户端 CLI、Desktop、双端或准确起点 | [integrations/AGENTS.md](../integrations/AGENTS.md) | `integrations/<软件slug>/` 或独立项目 |
| 已有能力配置包/集成包交付/内置资源 | [Resources/Integrations/AGENTS.md](../Resources/Integrations/AGENTS.md) | 用户工作区；新增能力路由到上一份 |
| 自定义形象、动作、跟随、主题/皮肤、音效与图标 | [Resources/Skins/AGENTS.md](../Resources/Skins/AGENTS.md) | 形象工作区的 `packages/` 输出形象包 |

## 用户怎样开始

在 Char 仓库中只需说：

> 接入「软件」的「CLI/Desktop/两端」，我使用「终端及是否使用tmux」，希望「监控/点击跳转/准确回城等行为」。

只提行为即可，Agent 按可查证接口决定能力与精度；不用用户指定 workEnd、bundle、Hook 路径或协议。对无法查证且影响方案的选择集中提问，期间继续其他开发。

独立项目启动时提供 SDK 路径一次：

> Char SDK 在「仓库绝对路径」。读取其 integrations/AGENTS.md，在当前目录开发「软件和行为」。

制作形象时使用对应入口：

> 读取 Resources/Skins/AGENTS.md，按「角色、风格、参考和动作要求」制作可导入形象及匹配图标。

支持 AGENTS.md 的工具按目录加载；其他工具显式读取入口。独立目录不能假定工具自动发现另一仓库的指令。三份 AGENTS 不放入交付包，也不复制具体插件实现作为提示词。

## Agent 怎样完成

1. SDK 指南 → 工作区/骨架 → 本次所需事实与准确图标 → 实际能力 → 相关快测 → 最终生成包SDK检查。
2. 主动报告**开发及基本验收完成**，交付源码/包、能力/精度/成本与证据，真实环境未测保持待验证。
3. 提供完整、已填具体路径与菜单的 GUI 验收步骤及反馈表，**用户自己操作**。提供说明无需打开 App 或请求解锁；仅在明确要求准备/代测时执行相关动作。
4. 收到反馈后修复受影响路径并更新证据；有适用产品链路证据才声明正式支持。发布另按用户授权。

用户无需构建或敲安装命令。Node/Python 等依赖在开发阶段查证并给可交互准备方式；Swift SDK工具可能需要开发者工具链，但不是用户验收要求。

图标由 Agent 按[图标流程](plugin-icon-sourcing.md)取得：本地官方资源→网上核实官方资源→无法确认时请用户上传。上传后 Agent 转换、核对与重新打包；当前没有单独的设置上传控件，运行时不联网搜索。

## 契约与验收资料

| 需要的信息 | 统一位置 |
| --- | --- |
| 目录、CLI/Desktop/准确起点分支、骨架与工具示范 | [能力SDK指南](plugin-development.md) |
| 清单、更新、依赖与权限 | [集成格式](integration-plugin-format.md) |
| 适配器方法、事件、运行上下文与超时 | [协议](capability-adapter-protocol.md) |
| 图像动作、图标与预算 | [外观指南](appearance-development.md)、[形象格式](pet-skin-format.md)、[完整外观API](appearance-api.md) |
| 开发者检查：调度、所有权、并发、真实进程及性能 | [基本验收](plugin-basic-acceptance.md) |
| 用户的导入、加载、逐端测试、热维护与恢复 | [用户验收交付规范](plugin-user-acceptance.md) |

基本验收按[执行策略](plugin-basic-acceptance.md#执行策略快测按需检查用户验收)选择快测：调试只跑相关组，最终包确认一次，原生TUI/模型框架仅在具体缺口或明确要求时执行。同源码双端复用机制测试，各包身份/路由单独检查；覆盖到真实风险即可交付。参考按需读取，不用先遍历宿主 Sources 或全部历史文档。网络/额度中断后从已有工作继续，外部中断不计提示词缺陷。
