# 能力适配器协议 v1

生产实现：`Sources/CharPluginHost/AdapterProcess.swift`、`CapabilityHost.swift`；应用接入：`Sources/CharApp/RuntimeCapabilities.swift`。适配器是包内独立进程，不加载进 Char 地址空间。

## 传输与上下文

stdin 接收 UTF-8 JSON Lines，stdout 仅发送完整 JSON Lines。每条都有整数 `version:1`。调试输出用 stderr（产品宿主丢弃它）；不要写终端 UI、网页/消息正文或凭证。启用时宿主先请求 `hello` 和 `inspect`；停用插件的显式维护进程握手后只执行所选维护方法。

请求：`{"version":1,"id":"唯一字符串","method":"方法名","params":{}}`

响应二选一：`{"version":1,"id":"同一字符串","result":{}}` 或 `{"version":1,"id":"同一字符串","error":"简短原因"}`。事件不带请求 ID。未知方法返回错误。请求可并发，按 ID 匹配；适配器自行保证客户端操作的顺序与资源生命周期。

| 环境变量 | 含义 |
| --- | --- |
| `CHAR_PLUGIN_ID`, `CHAR_PLUGIN_VERSION` | 当前包身份/版本 |
| `CHAR_PLUGIN_DIRECTORY` | 安装后的包根；工作目录也是包根 |
| `CHAR_WORK_END` | 清单声明的工作端，未声明为空 |
| `CHAR_PLUGIN_CONFIG` | configuration 的 JSON 字符串字典 |
| `CHAR_HOOK_BINARY`, `CHAR_HOOK_EVENTS` | 宿主解析的稳定 Hook 和事件入口 |
| `CHAR_SUPPORT_DIRECTORY` | 当前用户 Char 数据根 |
| `CHAR_NATIVE_ROOT` | 宿主部署的内置原生集成目录 |
| `HOME`, `PATH` | 当前用户、运行时查找路径；可选 `KIMI_CODE_HOME` |

不得把上述上下文固化为开发者用户名、项目绝对路径或 `build/Char.app`。第三方原生事件可直接由监控适配器推送；不要将 v1 事件 JSON 原样写进旧 Hook 流：旧流是另一种 Swift 编码契约。

## 方法

| 方法 | 能力 | params / result |
| --- | --- | --- |
| `hello` | 所有 | result 必须 `protocolVersion:1` |
| `inspect` | 所有 | result `status` 为 `ready`、`notInstalled`、`reloadRequired`、`unavailable`，可选 `detail` |
| `start` / `stop` | monitor | 幂等开始/停止原生订阅；成功 result `{}`；start 后持续推送事件 |
| `visit` | visit | params `nativeID`、`bundleIdentifier`，可选 `processID`、`tmuxPaneID`、`sourcePath`；result `outcome` |
| `capture` | origin | params `processID`、`bundleIdentifier`；result 非空 opaque `token`（≤4096字符）及同一 `processID` |
| `check` | origin | params `token`、`processID`；result `valid:true/false/null` 和 `active:true/false` |
| `focus` | origin | params `token`、`processID`；result `outcome` |
| `release` | origin | params `token`；释放该锚点，result `{}`；幂等，不关闭客户端内容 |
| `install` / `update` / `uninstall` | lifecycle | result 与 inspect 相同；可选 params `retainSharedIntegration` 为内置共享安装提示 |

`outcome` 只有 `exact`、`fallback`、`unavailable`。`exact` 响应必须附 `verified:true`。只激活应用是 fallback；失败是 unavailable，不能悄悄报告成功。实际运行时，visit 还核对前台 bundle；回城先确认来源 PID 仍存活并激活该实例，再 focus，再 check 确认 active 才认可 exact。插件负责使用客户端正式接口确认具体对象，宿主无法独立验证插件内部 API 的真实性。

`valid:false` 仅表示确定关闭/失效；无法查询应为 null 或返回错误，保留重试。`active` 必须确认原 token 真正处于当前焦点。锚点绑定插件进程实例和来源应用 PID，不可跨进程重启复用；Char 自身不能成为起点。默认首次起点和连续访问规则在 Char 内核，插件不实现自己的导航栈。

## 监控事件

事件帧 `{"version":1,"event":{...}}`，event 字段：

| 字段 | 契约 |
| --- | --- |
| `workEnd` | 必须等于清单声明值，不能发布其他插件的事件 |
| `nativeID` | 稳定原生根会话身份，非空，≤1024字符 |
| `timestamp` | 真实事件 ISO-8601 时间，可有小数秒 |
| `state` | `running` / `stopped` / `closed` |
| `reason` | stopped 必填：`question` / `approval` / `turnEnded` / `failure` / `rateLimit` / `contextExhausted` / `unclassified` |
| `isChild` | 可选布尔值，默认 false；子会话不进入提醒 |
| `target` | 可选对象，含 processID、tmuxPaneID、sourcePath 必要元数据；应用身份由清单覆盖 |

只使用可信原生事件或增量日志，正文关键词和“很久没输出”不能推断原因。启动/重新启用从新活动开始，不回放历史记录。日志实现保持完整行、EOF 基线、截短/轮转、关闭水位；公共过滤、排序、重复/乱序、已查看、声音与 Hold 交给 Char。

## 生命周期与成本

- monitor 适配器启用后建立一个进程；ready 才 start。origin 适配器捕获时保留进程以维护 opaque 状态。visit/lifecycle-only 操作按需启动，结束即退出。混合包共享一个适配器进程。
- 自检可能执行，因此导入可信代码后明确授权运行。进程隔离不提供权限沙箱；适配器有当前用户的文件/进程能力。产品没有自动下载运行时或网络遥测。
- 每个请求默认超时 3 秒，生命周期 15 秒；超时拒绝该请求，后续可重试。退出/格式错会失败并清理。帧缓冲≤1MiB，待取事件≤4096，过量新事件丢弃，因此不要用协议承载大文件或无限突发流。
- 禁用/删除/更新/Char 退出会关闭宿主所属进程。不支持插件自行派生脱离宿主的常驻守护程序；stdin EOF/SIGTERM 后应退出并取消订阅/子进程。
- 不给每个插件添加高频轮询；事件通过 pipe 推送，宿主沿现有500ms批次取出。当前准确 Hold 的存活/焦点检查共享该调度，不遍历所有客户端。
- install/update 必须备份并幂等维护自己所属的记录；uninstall 只移除自己的 Hook/资源，保留用户配置、原生会话和其他插件。不自动启动模型或退出工作客户端。配置就绪不等于已运行会话已重载。

可从 Node/Python 开发，也可带可执行入口（整包受8MiB限制）。缺少运行时应显示 unavailable，不能假装 ready。协议版本1是当前唯一支持版本。
