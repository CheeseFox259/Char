# Char 能力适配器开发指令

在此目录开始任务时，实现用户指定软件的原生能力适配器及必要客户端扩展。客户端、操作系统、运行方式、功能目标均来自当前任务，不预设任何产品。完成可以导入并验证的实现；缺少关键目标时集中问一次，同时推进不依赖答案的查证。

仓库路径相对根目录，命令从根运行。先读根 `CONTEXT.md`、`docs/plugin-development.md`、`docs/integration-plugin-format.md`、`docs/capability-adapter-protocol.md` 和 ADR 0008。生产边界在 `CharCore/IntegrationPlugins.swift`、`CharPluginHost`、`CharApp/RuntimeCapabilities.swift`。

## 开发

1. 查客户端官方事件/API或已安装源码，记录稳定根会话 ID、CLI/Desktop 区别、支持的状态原因、终端/tmux与配置根、聚焦接口和重载方式。必要事实附来源。正文关键词或沉默不能当状态信号；不自行发模型请求。
2. 定义唯一插件 ID、动态 workEnd 和真实 bundle ID，选择 monitor/visit/origin/lifecycle。新客户端不改 WorkEnd/ReturnAdapter 枚举或主程序分支；只有协议本身缺能力时才提出宿主变更，说明理由。
3. 实现包内 Node/Python/可执行适配器。stdin/stdout 是版本1 JSON Lines，stdout 只有协议；诊断走 stderr，不污染客户端 TUI。hello/inspect 必须有效；只实现清单声明能力，未知方法明确失败。
4. monitor 原生订阅优先、增量读取备选。真实时间用 ISO-8601；根身份稳定；不复制 prompt/回复/凭证。处理 EOF 基线、完整行、半行、截短/轮转和关闭水位。由宿主管理过滤、排序、启停代次、声音和 Hold。
5. visit 精确聚焦原会话并验证才 exact+verified；只激活应用 fallback，失败 unavailable。origin 实现 capture/check/focus/release，opaque token 绑定原 PID 与适配器实例；valid false 只用于确定失效，查询失败为 unknown/error。公共首次/最近起点和回城规则由 Char 实现，不创建独立导航栈。
6. 生命周期自检实际配置与版本，明确 ready/notInstalled/reloadRequired/unavailable。install/update 先备份，只改所属条目并保持幂等；卸载仅删除所属 Hook/资源，保留其他配置和原生会话。路径来自 CHAR_HOOK_BINARY/CHAR_HOOK_EVENTS/包目录等上下文，不硬编码用户或 build。配置完成不证明现有客户端已重载，不自动退出/重启客户端。
7. 一个混合包共享一个进程，监控推送，不新增每插件高频轮询；导航/维护按需执行。EOF/SIGTERM 时取消订阅与子进程，不留下脱离宿主的守护程序。进程隔离不是权限沙箱，明确实际运行时依赖与权限。

## 验证与交付

先用真实协议样本构造能够失败的 fixture，覆盖本次涉及的状态、根/子、CLI/Desktop、权限失败、乱序、恢复/关闭和启停边界。运行生产包校验、char-plugin-check inspect/replay 和 scripts/check.sh。安装维护先在临时 HOME/配置根验证，证明其他 Hook/配置不被改动；有授权后再走自然原生客户端路径。

交付实现源码、可导入 `.charintegration`、能力矩阵、信号证据、依赖、配置、安装/更新/卸载/回退说明，以及实际测试和性能结果。回放/模拟与真实客户端验收分开报告；未实现方法不能假报 ready/exact。用户未授权的持久配置写入和发布不由此指令自动授权。
