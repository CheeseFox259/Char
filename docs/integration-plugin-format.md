# 集成插件格式

一个 `.charintegration` 目录可同时提供监控、跳转、准确起点和安装维护。新客户端使用动态 `workEnd`，无需修改 Char 枚举或重编译。所有包使用 schemaVersion 3。仅组合已有内置能力的包不需要适配器代码。进程适配器在独立进程运行，**拥有当前用户权限，不是操作系统沙箱**。形象包使用独立的形象接口。

## 包和清单

包内有 `manifest.json`、可选 PNG 图标，以及适配器代码/依赖资源。根目录和内容均禁止符号链接；总计不超过 8 MiB。入口与图标只能使用包内相对路径，禁止绝对路径、`.`/`..` 路径段。PNG 可解码且宽高不超过 2048。原生入口必须有执行权限。

| 字段 | 契约 |
| --- | --- |
| `schemaVersion` | 整数 `3`，其他值拒绝导入 |
| `id` | 唯一 1–128 个 ASCII 字母、数字、点、下划线或短横线；首位字母/数字 |
| `name` | 去空白后非空，最多 100 字符 |
| `bundleIdentifier` | 目标应用真实点分 bundle ID；宿主用它决定应用身份 |
| `version` | 可选包版本字符串，建议使用语义版本；升级始终重新导入完整包 |
| `clientInterface` | 可选 `cli` / `desktop` / `application`；`cli` 显示终端角标 |
| `workEnd` | 可选动态身份，与 `id` 同字符约束；新身份必须有 `monitor` 适配器 |
| `icon` | 可选包内相对 PNG 路径 |
| `adapter` | 可选进程描述符，见下表 |
| `returnAdapter` | 内置导航能力：`application` / `tabbit` / `vscode`；其他准确能力使用 `origin` |

| adapter 字段 | 契约 |
| --- | --- |
| `protocolVersion` | 必填整数 `1` |
| `runtime` | `node`、`python3`、`executable`；Node/Python 必须可从宿主 PATH 找到 |
| `entrypoint` | 必填包内相对入口文件 |
| `capabilities` | 非空且只包含 `monitor`、`visit`、`origin`、`lifecycle` |
| `configuration` | 可选字符串字典，用于客户端配置根/运行方式等；不是凭证库 |

至少有一种能力。一个工作端只能有一个启用插件；一个 bundle ID 只能有一个启用的准确起点提供者，包括声明内置精准导航的配置包。多个 CLI 监控可以共享同一个终端。普通应用级回城无需插件，也不占有该应用。

内置 `workEnd` 包括 `claudeCode`、`codexCLI`、`codexDesktop`、`deepseekDesktop`、`kimiCLI`、`kimiDesktop`、`pi`。`tabbit` 和 `vscode` 必须对应各自真实 bundle ID。外部能力插件不需要新增 `ReturnAdapter` 枚举值。

## 导入、更新、删除

生产导入器验证整个包和冲突，复制到 UUID 安装目录，再原子提交注册表。失败不改变原目录。设置导入同 ID 的新包会更新，保留启停状态；运行中的旧适配器退出，准确锚点失效，观察代次重建。已安装包不支持直接修改文件，应重新导入完整包。

启停是用户意图；`ready` / `notInstalled` / `reloadRequired` / `unavailable` 是自检结果。`ready` 不证明已经运行的原生客户端加载了新 Hook。安装和更新通过显式操作执行；导入只自检，不自动改客户端配置。删除可选“仅删除插件”或“卸载集成并删除”；卸载失败保留插件供修复。Kimi CLI/Desktop 的共享 Hook 会在另一启用客户端仍需要时保留。

注册表使用schemaVersion 3。应用升级时会刷新已知内置插件的清单，保留启停状态和删除记录；恢复内置插件为显式操作，冲突能力恢复为禁用。

应用级锚点不依赖插件。准确锚点绑定提供者、原进程及适配器实例，禁用/删除/更新提供者后失效；查询临时失败保留重试。默认保留首次起点，用户可改为最近起点或关闭记录，并可禁用应用级起点。

## 校验

- `swift run char-package-check integration <目录>`：生产格式/复制检查，临时注册表，无客户端操作。
- `swift run char-plugin-check inspect <目录>`：执行可信适配器，只握手与自检，不请求安装、监控或导航。
- `swift run char-plugin-check replay <目录> <events.jsonl>`：临时回放进程走真实事件解码和路由器，不执行客户端适配器代码。
- `bash scripts/check.sh`：宿主、当前协议、原生生命周期与公共规则检查。

退出码 0 通过、1 检查失败、2 用法错误。实际用户目录仍会独立检查启用冲突。详见[协议](capability-adapter-protocol.md)与[开发指南](plugin-development.md)。
