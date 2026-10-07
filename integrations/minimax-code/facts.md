# MiniMax Code 客户端事实（去敏）

核对日期：2026-10-06。所有事实来自本机已安装客户端与隔离运行，未使用用户账号、额度或既有会话。

## 身份

| 项目 | 值 | 来源 |
| --- | --- | --- |
| Desktop 应用 | MiniMax Code 3.1.1（build 3.1.1.179） | `/Applications/MiniMax Code.app/Contents/Info.plist` |
| Desktop bundle ID | `com.minimax.agent.cn` | 同上 `CFBundleIdentifier` |
| Desktop 可执行文件 | `MiniMax Code`（进程名 `/Applications/MiniMax Code.app/Contents/MacOS/MiniMax Code`） | 同上 `CFBundleExecutable` |
| Desktop 运行形态 | Electron + `app.asar`（约 396 MB），URL scheme `minimax-cn://` | Info.plist `ElectronAsarIntegrity` / `CFBundleURLSchemes` |
| CLI 可执行 | `mcode`，`--version` = 0.5.5 | `~/.minimax-code/bin/mcode` → `releases/0.5.5/.mcode-launcher` |
| CLI 发行包 | npm `@minimax-ai/code`，`updateOwner: npm-prefix`，安装根 `~/.minimax-code` | `~/.minimax-code/install.json` |
| CLI 进程名 | `ps -o comm=` 显示 `minimax-code`（argv 亦为 `minimax-code`） | 真实 TUI 运行 `ps -o pid=,ppid=,args=` |
| 承载终端 | Warp 0.2026.09.30，bundle `dev.warp.Warp-Stable`，`mcode` 运行于其中 | `defaults read` + 进程祖先链 |
| 数据根 | `<home>/.minimax`（客户端用 `homedir()` 拼接，运行期自行写入 `MINIMAX_DATA_DIR`） | `chunks/chunk-ALZ67EMN.js` 中 `join(e.homeDir??FCe.homedir(),".minimax")` |
| 关键子目录 | `v2/plugin-data/hooks/<plugin>`（Hook 可写状态）、`v2/plugin-hook-cache`、`v2/sessions`、`v2/sqlite`、`plugins/`（本地插件市场） | 目录实测 |

## 本地插件与 Hook（官方文档 + 客户端代码核对）

来源：客户端内置参考文档 `Local MiniMax Plugin V1 Reference` 与 `… Plugin Hook Reference`（Desktop `app.asar` 与 CLI `chunks/` 内同一份实现）。

- 本地插件目录：`{{DATA_DIR}}/plugins/<plugin-directory>/`，**CLI 与 Desktop 共用同一数据根，因此同一插件两端共用**。
- 清单：`<plugin>/.minimax-plugin/plugin.json`，`schemaVersion: 1`。
  - 必填：`name`、`version`(semver)、`description`、`author`、`icon`、`category`、`exampleQueries`、**`apps` / `mcpServers` / `skills` 三个数组必须存在（可为空数组）**、`$schema`/`displayName`/`darkIcon`/`hooks`/`hostBindings` 可选。
  - 未声明字段会被拒绝；`category` 取值来自固定枚举（`Office`、`Studio`、`Design & Sites`、`Code`、`Business`、`Sales`、`Productivity`、`Science & Healthcare`、`Education`、`Other`）。
  - 缺少 `apps`/`mcpServers`/`skills` 会被判 `MANIFEST_SCHEMA_INVALID`，插件被静默忽略——这是开发中实测到的失败原因。
- 安装语义：本地插件**通过目录存在即安装**（`mutateLocal` 对 `install` 直接抛 `LOCAL_PLUGIN_INSTALL_UNSUPPORTED`），默认启用，禁用状态记录在 `v2/sqlite/runtime-state.sqlite` 的 `local_runtime_plugin_local_disabled`。
- Hook 文档：`{"hooks":{"<Event>":[{"matcher?":…,"hooks":[{"type":"command","command":…,"timeout":1..10}]}]}}`，路径写进清单 `hooks` 数组。
- 支持事件：`SessionStart`、`SessionEnd`、`UserPromptSubmit`、`PreToolUse`、`PermissionRequest`、`PostToolUse`、`SubagentStart`、`SubagentStop`、`Stop`、`PreCompact`、`PostCompact`。
- 环境：只透传 `PATH/HOME/LANG/TERM/SHELL/USER/TMPDIR/…` 少量变量，另加 `PLUGIN_ROOT`、`PLUGIN_DATA`、`MINIMAX_PROJECT_DIR`；`command` 支持 `${PLUGIN_ROOT}` 展开；无 shell，`stdout/stderr` 各封顶 64 KiB，`SessionEnd` 共享 3 秒预算。
- 失败语义：Hook 异常/超时**默认 fail-open**，不会向客户端抛错；因此本集成不依赖客户端暴露诊断，自检只看自身文件与事件到达。
- 钩子示例工具名（用于 `matcher`）：`bash`、`read`、`write`、`edit`、`task` 等原生名；`ask_user` 是客户端内置工具（`steps` 结构），其结果带 `waiting_for_user`。

## 原生事件 → Char 状态映射（实测）

| 原生 Hook | payload 关键字段 | Char v1 | 实测 |
| --- | --- | --- | --- |
| `SessionStart` | `source` | 不发布事件，仅登记会话上下文 | ✅ 隔离 TUI/exec 均实测 |
| `UserPromptSubmit` | `prompt`（不使用） | `running` | ✅ |
| `PreToolUse`（matcher `ask_user`） | `tool_name` | `stopped` / `question` | ⚠️ 映射有实现；自定义 provider 下客户端未暴露该工具，待真实模型下由用户验收 |
| `PermissionRequest` | `tool_name` | `stopped` / `approval` | ✅ 通过 `permission.json` 的 `ask` 规则触发实测 |
| `Stop` | `stop_hook_active`（不使用） | `stopped` / `turnEnded` | ✅ |
| `SubagentStart` / `SubagentStop` | `agent_id`、`agent_type` | 不产生提醒，仅登记子代理 | ⚠️ 未在自动化中触发，映射有实现 |
| `SessionEnd` | `reason`（clear/logout/resume/other） | `closed` | ✅ TUI `/new` 实测 |
| 进程退出 | 无 | `closed`（按观测到的客户端 PID 消失推断） | ✅ 适配器推断路径实测；文档明确正常退出不触发 `SessionEnd` |

未映射的缺口（不猜测、不发布）：

- **失败 / 限流 / 上下文耗尽**：官方文档写明 `Stop`/`SubagentStop` 只在正常完成时触发，取消与失败不触发，客户端没有对应 Hook 事件，因此这三类原因**没有原生来源**。
- **提问（question）**除 `ask_user` 工具边界外没有其它原生信号；普通回答型回合结束只能记为 `turnEnded`。
- **压缩**（`PreCompact`/`PostCompact`）属于继续工作，不映射为 `contextExhausted`。
- **ACP surface**（`mcode acp`）未单独取证；Hook 运行在同一套 runtime 中，但本版本只对 TUI/headless 做了实测。

## 端到端实测样本（去敏，2026-10-06）

隔离 HOME + 本地 stub 模型 provider（`anthropic-messages`），无账号、无额度、无用户会话：

```json
{"v":1,"ts":"2026-10-06T15:05:22.757Z","ev":"SessionStart","signal":"context","state":null,"sid":"mvs_…","cwd":"/private/…/work","surface":"cli","pid":16513}
{"v":1,"ts":"2026-10-06T15:05:22.874Z","ev":"PreToolUse","signal":"tool","state":"running","sid":"mvs_…","cwd":"/private/…/work","surface":"cli","pid":16513}
{"v":1,"ts":"2026-10-06T15:05:22.923Z","ev":"PermissionRequest","signal":"approval","state":"stopped","sid":"mvs_…","cwd":"/private/…/work","surface":"cli","pid":16513}
{"v":1,"ts":"2026-10-06T15:05:28.774Z","ev":"PostToolUse","signal":"tool","state":"running","sid":"mvs_…","cwd":"/private/…/work","surface":"cli","pid":16513}
{"v":1,"ts":"2026-10-06T15:05:28.864Z","ev":"Stop","signal":"turnEnded","state":"stopped","sid":"mvs_…","cwd":"/private/…/work","surface":"cli","pid":16513}
```

会话身份为客户端原生 `mvs_<32 hex>`（`local_runtime_sessions.session_id` 同源），非插件自造。

## 跳转精度：两端都没有会话级公开接口

- CLI：Warp 没有本插件可用的“定位到某个 tab/pane”公开接口；`tmux pane` 活跃也不等于终端窗口在前台（SDK 契约明确）。因此 CLI `visit` 只做“激活承载终端”，返回 `fallback`。
- Desktop：Deep Link 只把窗口置前并把 `{action, params}` 转发给渲染进程，主进程侧未注册任何会话动作；会话激活（`activateSession`/`openSessionById`）只存在于渲染进程内部状态与内部 HTTP 路由（`/mavis/api/…`），不是正式接口，且不能证明“该会话正处于焦点”。
- 结论：**Desktop 不声明 `origin`**。按 SDK 契约“只会打开应用的包不声明 origin，宿主退回应用级锚点”，本集成只声明 `monitor + visit + lifecycle`，跳转一律 `fallback`/`unavailable`，绝不返回 `exact`。

## 其它未知与降级

- Desktop Hook 运行：本版本 Desktop `app.asar` 内含同一套 Hook 实现与同一份参考文档，静态核对一致；但桌面端 Hook 事件需要在真实回合中产生，开发期未使用用户账号发起模型请求，**Desktop 原生载荷留待用户验收**。
- `v2/plugin-hook-cache` 由客户端在加载 Hook 包时生成，属客户端所有；本集成不写、不删，只在卸载时清理自己拥有的 `v2/plugin-data/hooks/char-observer` 与 `plugins/char-observer`。
- 自检不读取客户端 sqlite：文件存在、客户端已加载、Hook 已产生事件是三件事，本集成只对前两件负责，第三件由事件到达时间佐证。