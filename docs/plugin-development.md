# 能力插件开发指南

新客户端可以在不修改 Char 源码的情况下接入监控、跳转、准确回城和安装维护。一个包可选择其中任意能力；任意应用仍有内置应用级回城。旧 v1/v2 配置包继续使用现有能力。

## 1. 开始开发

三份通用、可自动读取的[完整开发指令](development-prompts.md)分别位于实现、交付包和外观目录。把具体客户端、运行方式和目标告诉代码 Agent；指令没有预设某个客户端或角色。

从仓库根运行骨架工具（把占位值替换为需求中的真实值）：

```sh
python3 scripts/new-capability-plugin.py <输出目录.charintegration> \
  --id <唯一插件ID> --name <显示名称> --bundle <真实bundleID> \
  --work-end <唯一工作端ID> --interface <cli或desktop> \
  --capabilities monitor,visit,origin,lifecycle
```

只需要部分能力就删去对应项；不监控时可省略 work-end。骨架可通过格式和协议校验，但 inspect 明确返回 notInstalled，其他能力尚未实现；**它不是可交付的客户端集成**。将实现、依赖及资源放入包，文档/fixture/生成器留在包外。不要更改 WorkEnd/ReturnAdapter 来增加新客户端。

## 2. 查证和实现

阅读[清单](integration-plugin-format.md)和[完整协议](capability-adapter-protocol.md)。从官方事件/API或已安装源码确认：根会话身份、CLI/Desktop、状态原因、终端/tmux环境、窗口/标签聚焦能力和客户端加载方式。记录未知类别，不能从回答正文或无输出推断。

| 能力 | 开发要求 |
| --- | --- |
| monitor | 原生订阅优先；增量日志从 EOF 开始，处理完整行/轮转；转换必要元数据为 v1 事件 |
| visit | 通过可靠接口聚焦 nativeID；确认后 exact+verified，应用激活 fallback，失败 unavailable |
| origin | capture/check/focus/release；opaque token 绑定原 PID，确定关闭与查询失败分开 |
| lifecycle | inspect/install/update/uninstall；只管理自己所属配置，备份、幂等、可回退，不自动重启客户端 |

stdin/stdout 用 JSON Lines，stdout 不写诊断文字；配置根、终端环境通过清单 configuration 与宿主上下文配置。安装目标引用 `CHAR_HOOK_BINARY` 等稳定入口，不能引用构建目录。客户端原生扩展可以随包携带并由 lifecycle 安装，不能只在 README 写一条开发路径。

首次/最近/禁用起点、过滤、气泡排序与回城快捷键由 Char 统一处理。开发者只实现具体软件接口；无需复制一套公共规则。相同应用的多个准确提供者不能同时启用。

## 3. 开发工具与测试

```sh
swift run char-package-check integration <包目录>
swift run char-plugin-check inspect <可信包目录>
swift run char-plugin-check replay <包目录> <events.jsonl>
bash scripts/check.sh
# 原生能力路径（隔离配置与模拟导航）
build/Char.app/Contents/MacOS/Char --capability-smoke
```

包校验调用生产导入器但只写临时目录。inspect 会执行你的适配器，仅请求 hello/inspect；开发工具上下文与正式 app 运行上下文有区别，不要将工具提供的路径写成产品配置。回放文件每行是 event 对象或带 event 的帧，workEnd 必须与清单一致；回放走真实宿主解码与 AttentionRouter，既不安装 Hook，也不运行客户端适配器。日期用 ISO-8601；不要套用旧 Swift Hook 时间格式。

为真实协议样本构建失败 fixture，再覆盖本次涉及的根/子、CLI/Desktop、启动基线、重复/乱序、关闭、权限失败、精度确认和安装升级卸载。测试模型请求不是必需步骤；优先模拟原生事件/API，真实客户端使用用户自然发生的活动验收。

## 4. 导入与交付验收

1. 用户明确导入可信包；Char 复制包、自检并显示可用状态。运行时代码拥有当前用户权限，进程隔离不是沙箱。
2. 需要 Hook 时通过插件菜单安装/更新；显示 reloadRequired 后由用户重载客户端。不要把 ready 解释为现有会话已经加载扩展。
3. 新活动产生气泡，点击进入、保存来源、Ctrl+B 回城；exact 必须真实确认对象，fallback 必须准确标示。
4. 禁用不接收旧进程事件，重启只看新活动；同 ID 新包导入保留启停、重建进程代次。
5. 删除可选保留客户端集成，或卸载自己的集成再删除。其他插件/用户 Hook、原生会话和普通应用级来源保持可用。

交付完整包、能力矩阵、证据链接、运行时依赖、配置项、安装/升级/卸载/回退方法和实测记录。分别报告格式检查、回放、模拟导航与真实客户端测试。缺失信号明确列出；不要宣称所有软件能自动精确定位。

## 5. 性能要求

一个混合包共用一个进程。监控使用原生事件推送；日志读取采用增量与目录缓存；visit/lifecycle-only 不空闲常驻。停止时取消订阅与子进程。测量适配器与 Char 的 CPU/RSS，注明会话数、文件根、气泡/设置状态、时间和样本长度。新增进程内存不可忽略；先减重复工作，再按实测优化，不能用丢事件或延长响应换数字。
