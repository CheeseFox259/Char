# 能力插件开发指南

**开发入口：`integrations/AGENTS.md`。** 使用者给出软件、CLI/Desktop 和希望实现的行为即可。开发者用 Char 仓库作 SDK，交付独立 `.charintegration`，新增工作端无需修改或重新编译 Char。普通应用级回城已有内置实现。

## 按问题直接查契约

| 当前问题 | 读取位置 |
| --- | --- |
| 从哪里开始、CLI/Desktop 如何建包 | 本文第1–3节；无需读历史架构文档 |
| 字段、运行时、配置类型、更新规则 | [集成格式](integration-plugin-format.md) |
| 请求参数、事件、超时、起点 token | 本文第4节及[完整协议](capability-adapter-protocol.md) |
| 图标身份与资源取得 | [图标获取](plugin-icon-sourcing.md) |
| 怎样控制常驻开销、CPU/内存/延迟预算 | [性能要求](plugin-performance.md) |
| 怎样证明实现可交付 | [基本验收](plugin-basic-acceptance.md)的适用能力分支 |
| 怎样交给用户实际验收 | [用户验收交付](plugin-user-acceptance.md)，填写工作区 USER-ACCEPTANCE.md |

## 1. 工作目录与第一步

默认工作目录为 `integrations/<软件slug>/`；也可使用独立项目目录。不要将第三方实现塞进 `Sources/` 或内置 `Resources/Integrations/`。以本指南开始，清单字段查[格式契约](integration-plugin-format.md)，方法详情查[协议契约](capability-adapter-protocol.md)。遇到具体工具错误且契约解释不了时，才定点查看宿主实现。

建议目录：

```text
<插件工作目录>/
  README.md                 能力矩阵、依赖、安装与验收结果
  facts.md                  客户端版本、来源、去敏事件样本、未知项
  adapter/                  唯一实现源码（协议入口及必要模块）
  client-extension/         需要时携带的原生 Hook/插件模板
  tests/                    协议、采集器、维护和导航测试
  fixtures/                 去敏原生样本、v1 回放事件
  build-packages.*           从唯一源码生成完整交付包
  packages/*.charintegration/  仅运行所需文件，无说明/测试/生成器
```

下面是 **SDK 操作示例**，`Sample` 是虚构客户端，不是现成集成；生成的是尚未实现能力的骨架。替换路径和客户端身份后运行。`CHAR_SDK_ROOT` 指 Char 仓库，`CHAR_PLUGIN_WORKSPACE` 指插件项目；不依赖当前 shell 所在目录。

```sh
CHAR_SDK_ROOT="/path/to/Char"
CHAR_PLUGIN_WORKSPACE="$CHAR_SDK_ROOT/integrations/sample"
mkdir -p "$CHAR_PLUGIN_WORKSPACE/packages" "$CHAR_PLUGIN_WORKSPACE/fixtures"

# CLI：bundle 是终端应用；此例选 Warp。换终端需查证真实 bundle。
python3 "$CHAR_SDK_ROOT/scripts/new-capability-plugin.py" \
  "$CHAR_PLUGIN_WORKSPACE/packages/sample-cli.charintegration" \
  --id studio.sample.cli --name "Sample CLI" \
  --bundle dev.warp.Warp-Stable --work-end studio.sample.cli \
  --interface cli --capabilities monitor,visit,lifecycle

# Desktop：com.example.Sample 仅占位，交付时必须替换为真实客户端 bundle。
python3 "$CHAR_SDK_ROOT/scripts/new-capability-plugin.py" \
  "$CHAR_PLUGIN_WORKSPACE/packages/sample-desktop.charintegration" \
  --id studio.sample.desktop --name "Sample Desktop" \
  --bundle com.example.Sample --work-end studio.sample.desktop \
  --interface desktop --capabilities monitor,visit,lifecycle

swift run --package-path "$CHAR_SDK_ROOT" char-package-check integration \
  "$CHAR_PLUGIN_WORKSPACE/packages/sample-cli.charintegration"
swift run --package-path "$CHAR_SDK_ROOT" char-plugin-check inspect \
  "$CHAR_PLUGIN_WORKSPACE/packages/sample-cli.charintegration"
```

工具不覆盖已有目录；续开发用已有源码，每次从源码重新生成包。骨架只实现 hello/inspect，inspect 为 notInstalled，其他方法明确失败。**VALID / PROTOCOL VALID 不代表监控已实现。** 不监控时省略 work-end；仅实现具体界面准确回城时可选择 origin；不需要同时声明四种能力。

## 2. 先查清最小客户端契约

创建 facts.md，逐项填事实/来源/未知；只查本次所需能力。

| 分支 | 需要确认 | 最小验证 |
| --- | --- | --- |
| 所有客户端 | 软件身份、安装/数据根、版本、运行时依赖 | bundle 与客户端版本；干净 PATH 的运行时查找 |
| CLI | 根会话 ID、终端、tmux 使用方式、Hook 环境白名单 | 用真实调用形状的去敏样本；无 tmux / 有 tmux 分别测试 |
| Desktop | 根会话 ID、窗口/会话 API、事件根和加载入口 | 确认本地插件发现/启用机制；不要假定与 CLI 完全相同 |
| monitor | 原生事件/API或结构化日志，根/子会话区别 | 每个信号有可信字段契约或样本；未实测原生类别写待验证 |
| visit / origin | 对象身份、聚焦 API、活跃/存活查询 | 同应用两窗口/会话间确认到达，查询失败分开处理 |
| lifecycle | 客户端插件发现→注册/启用→加载流程、所属记录 | 临时配置根里客户端能发现并列出扩展，而非只检查文件存在 |

官方文档/帮助优先，再检查已安装客户端的定点源码。原生结构化字段（如 stopReason/status）不等于正文关键词，可以验证后使用；新增轮询要说明成本。没有可验证信号就降级并列缺口，不按沉默、正文或无输出猜原因。

大文件先看类型/大小。ASAR 先列目录再提取指定文件，SQLite 只查询必要结构化字段，打包 JS 先限定文件和片段。限制搜索输出和耗时，避免扫描整个二进制。资料未找到时记录当前未知与替代方案，不反复广搜 Char 源码。

## 3. 一个包对应一个工作端

CLI/Desktop 分开包、唯一 id/workEnd、各自 clientInterface；共用源码可由一个生成器输出两包。每个包只能发布清单 workEnd 的事件。名称、图标和 CLI 角标由清单表达。

**准确图标是交付内容。** 按[图标获取与上传流程](plugin-icon-sourcing.md)先取本地官方资源，失败后主动网上查找官方资源，仍无法确认则请用户上传或提供文件路径。核对目标产品，记录来源，将确认的PNG独立放进源码并由清单icon引用；承载终端和客户端扩展自己的占位图不能代替Agent身份。CLI角标由宿主绘制。网络获取在开发阶段完成，运行时使用包内资源。

新workEnd直接按格式契约命名，不需要查询内置WorkEnd列表。CLI的bundle来自使用者承载终端的应用身份（例如本指南骨架的Warp）；Desktop的bundle来自目标App身份。它们与CLI可执行文件、Hook PID是不同信息。应用包的Info.plist或客户端正式API可查证bundle，不必搜索Char源码。

| 能力 | 必须实现 | 不具备精确能力时 |
| --- | --- | --- |
| 所有 v3 适配器包 | hello、只读 inspect | notInstalled / unavailable 并说明具体缺项 |
| monitor | start、stop、v1 事件推送 | 只声明已证实信号；不发布猜测事件 |
| visit | nativeID→对象聚焦→确认 | 激活应用返回 fallback，失败 unavailable |
| origin | capture、check、focus、release | 无具体来源对象则拒绝 capture 或省略 origin，宿主退回应用级锚点 |
| lifecycle | install、update、uninstall | 先临时目录验证；只有显式操作才改客户端配置 |

特别注意：多个 CLI 通常共享终端 bundle；该 bundle **只允许一个启用的 origin 提供者**。应用级起点不占此名额。不要给只会 open 应用的包声明 origin。首次/最近/关闭起点、Ctrl+B、过滤/排序、提醒音、已查看、Hold 和桌宠动画都由 Char 实现。

### 不同需求的实现分支

以下是通用方案示范，不绑定现成插件；按实际客户端事实选择，不为凑齐能力重复实现公共规则。

| 用户需求 | 目录/包与实现 | 验收重点 |
| --- | --- | --- |
| 只接 CLI，无 tmux | 一个 cli 包；原生 Hook 监控，visit 可用终端应用级降级 | 原生根身份、承载终端、无 TUI 污染；不宣称 pane 精度 |
| CLI 同时支持直接终端与 tmux | 同一个 cli 工作端，target 携带可查证的定位信息 | 两种环境分测；只有 server/client/前台确认齐全才 exact，否则 fallback |
| 只接 Desktop | 一个 desktop 包，按本端插件/API/结构化日志入口采集 | App 身份与加载入口；窗口 API 可定位才宣称准确 |
| 同产品 CLI+Desktop | 唯一源码与生成器输出两个包，按原生宿主事实分流；Hook 可共享 | 两端各自身份/事件；两个进程成本；共享所有权与两种卸载顺序 |
| 任意应用的应用级回城 | 使用宿主已有回城，不新增空壳 origin | 首次/最近起点按用户设置，应用级精度明确 |
| 某应用精准回到标签/文档 | 单个 application 包声明 origin；无监控时省略 workEnd | capture/check/focus/release 的对象与实例绑定；同 bundle 一个 origin 提供者 |

仅 origin 的骨架可用第1节生成器，改 `--interface application --capabilities origin` 并省略 `--work-end`；要自行实现具体对象协议，骨架不会赋予精确能力。跳转/维护可按需组合。

客户端原生集成可能随版本迁移：例如用户 Hook 被弃用并改为客户端插件。以目标版本的帮助/发现机制查证，记录“写文件→发现→启用→加载→事件”各层，不照搬另一版本的路径或旧 Hook 模板。无法隔离发现/加载时留给用户实际验收。

## 4. 直接可用的协议参考

包入口的当前工作目录是安装后的包根。环境提供 `CHAR_PLUGIN_ID`、`CHAR_PLUGIN_VERSION`、`CHAR_PLUGIN_DIRECTORY`、`CHAR_WORK_END`、`CHAR_PLUGIN_CONFIG`（字符串字典 JSON）、`CHAR_SUPPORT_DIRECTORY`、`CHAR_HOOK_BINARY`、`CHAR_HOOK_EVENTS`、`CHAR_NATIVE_ROOT`、HOME/PATH。不要假定终端里的额外环境一定会由 App 或客户端 Hook 转发；需要的可变配置由清单 configuration 提供并检查。

stdin/stdout 是 UTF-8 JSON Lines，每行一个 version=1 帧，整数版本、字符串请求 id，响应按 id 匹配。stdout 只有协议；stderr 用于开发诊断（产品宿主丢弃它，用户可见错误放 inspect.detail / error）。异步请求按 ID 应答，资源操作保证顺序。未知方法错误，start/stop/release 幂等，EOF/SIGTERM 取消订阅、排空必要在途操作并退出。

**握手/自检：**

```json
{"version":1,"id":"h1","method":"hello","params":{}}
{"version":1,"id":"h1","result":{"protocolVersion":1}}
{"version":1,"id":"i1","method":"inspect","params":{}}
{"version":1,"id":"i1","result":{"status":"notInstalled","detail":"Client extension has not been installed."}}
```

inspect 的 status 只能 ready / notInstalled / reloadRequired / unavailable。检查配置、版本、入口文件/执行权限及可查询的启用记录；无法证实客户端已加载时说明边界。install/update 返回 reloadRequired 不等于监控失败，也不证明运行中的会话已重载。

**监控：** start/stop 成功 result `{}`；start 后推送：

```json
{"version":1,"event":{"workEnd":"studio.sample.cli","nativeID":"root-session-1","timestamp":"2026-10-06T08:00:00.123Z","state":"running","isChild":false}}
{"version":1,"event":{"workEnd":"studio.sample.cli","nativeID":"root-session-1","timestamp":"2026-10-06T08:00:01.456Z","state":"stopped","reason":"approval"}}
```

state=running/stopped/closed；stopped 必带 question/approval/turnEnded/failure/rateLimit/contextExhausted/unclassified 之一。nativeID 非空、最终长度≤1024（**包括自加前缀**）；添加命名空间不能破坏限制，也不要截断稳定 ID 导致碰撞。时间来自真实事件，优先保留毫秒。target 可含 processID、tmuxPaneID、sourcePath；bundle 由宿主按清单覆盖。子会话标记 isChild=true，不用字段是否存在替代值判断。

**导航和回城：**

```json
{"version":1,"id":"v1","method":"visit","params":{"nativeID":"root-session-1","bundleIdentifier":"com.example.Sample"}}
{"version":1,"id":"v1","result":{"outcome":"fallback"}}
{"version":1,"id":"c1","method":"capture","params":{"processID":1234,"bundleIdentifier":"com.example.Sample"}}
{"version":1,"id":"c1","result":{"token":"opaque-instance-bound-token","processID":1234}}
{"version":1,"id":"k1","method":"check","params":{"token":"opaque-instance-bound-token","processID":1234}}
{"version":1,"id":"k1","result":{"valid":null,"active":false}}
```

capture 只有真实具体对象已捕获时才返回上述 token；token 绑定来源 PID 和适配器实例，进程重启失效。capture 的 processID 是前台**应用** PID；它可能是终端 PID，不是 CLI/Hook PID。不能沿终端祖先链寻找其后代 CLI/tmux 会话。

focus params 同 check，返回 outcome；release params 仅 token、成功 result `{}`。valid=false 只用于确定关闭；查询不了是 null/error。active 要确认原对象，而非同 bundle 任意窗口。visit/focus 的 exact 必须 verified=true 且对象真在前台。tmux 要区分 socket/server、session、window、pane、attached client 与前台终端窗口；后台甚至无客户端的 pane 也可能 pane_active/window_active=1，单凭这些标志不能证明准确到达。仅有 pane_id 时，不承诺跨 server 精确导航。

**维护：** install/update/uninstall 返回与 inspect 同形状的状态。路径用运行时上下文，不依赖 build/Char.app。模板 JSON 用 JSON 序列化，命令参数独立做 shell 引用；测试空格、引号和 `$` 路径，不能用字符串替换同时解决两种转义。

两个包共用一个客户端扩展时，生命周期需自行登记和协调拥有者（插件 ID + 配置根），并串行修改共享资源；删除任一包不应破坏另一包。**当前 retainSharedIntegration 只是内置 Kimi 专用提示，没有通用第三方引用计数接口。** 无法安全判断时保留共享资源、提供显式最终清理说明；不要凭假设删除。扩展无需共享时各自命名更简单。更多方法、限制和超时以[完整协议](capability-adapter-protocol.md)为准。

普通请求的总预算为3秒，维护操作为15秒；所有串行子进程共用剩余预算。visit完整params包括nativeID、bundleIdentifier，可选processID、tmuxPaneID、sourcePath；应用级结果只返回fallback或unavailable，准确结果还需verified=true。configuration只能是字符串字典；数组/对象配置采用有明确格式的字符串并在解析时检查。

## 5. 开发与验收流程

| 顺序 | 产物/验证 | 通过条件 |
| --- | --- | --- |
| 1 | 工作目录、facts、能力矩阵、hello/inspect 骨架 | 身份真实、范围明确、工具能给出有效协议响应 |
| 2 | 可信字段/去敏样本→事件转换→采集器快测 | 根/子、两端分流正确；无正文或凭证落盘；无 TUI 输出；并发 Hook 不写坏行 |
| 3 | 临时 HOME/配置根维护测试 | 发现/启用路径可说明；幂等、版本检查、备份、失败恢复、不误删；两包共存与两种卸载顺序 |
| 4 | 导航/起点隔离测试 | 不同窗口/会话不会误报 exact；对象关闭、PID 错误、查询失败、旧 token 都有正确结果 |
| 5 | 从唯一源码生成交付包，生产工具测试 | 包校验、inspect、回放及实际适配器 start/stop 通过；退出无残留 |
| 6 | 成本与交付 | 基本验收通过，主动交付测试包、成本记录及用户GUI验收步骤 |
| 7 | 用户真实验收 | 用户完成客户端发现/启用→重载→自然事件→气泡→点击→回城→热禁用/更新/删除并回报；开发者据结果修复并更新状态 |

按[基本验收的执行策略](plugin-basic-acceptance.md#执行策略快测按需检查用户验收)先跑最小进程往返、退出和临时目录清理，再扩展对应机制测试。调试中只跑失败组，最终生成包检查一次；已通过且实现未变的证据复用。超时后的强杀记为失败，不能当清理通过。tmux 用临时独立 server，测试结束前验证实际 pane；测试中应用激活、用户配置写入与模型请求需要明确区分。宿主回放只验证解码和路由，不执行客户端采集器，也不能证明原生 Hook 被加载。

完整反例及通过条件以[基本验收](plugin-basic-acceptance.md)为准；开始实现相关能力时读取对应分支。原生模型服务器/PTY完整框架属于按需检查；只为当前缺失契约做有限探测，实际交互交用户验收。它覆盖生产调度自动续读、UTF-8/子身份完整序列、真实清单配置、所有权/失败恢复、跨进程共享和正确退出。不要以测试总数替代这些实际路径证据。

```sh
# 继承第1节的路径变量。先构建自己的完整包，再按适用能力执行。
CHAR_PLUGIN_PACKAGE="$CHAR_PLUGIN_WORKSPACE/packages/sample-cli.charintegration"
swift run --package-path "$CHAR_SDK_ROOT" char-package-check integration "$CHAR_PLUGIN_PACKAGE"
# v3 执行 inspect；v1/v2配置包不运行适配器。
swift run --package-path "$CHAR_SDK_ROOT" char-plugin-check inspect "$CHAR_PLUGIN_PACKAGE"

# monitor 包准备本工作端的合成SDK回放样本；不改SDK示例、不执行客户端。
CHAR_PLUGIN_FIXTURE="$CHAR_PLUGIN_WORKSPACE/fixtures/sdk-replay.jsonl"
python3 - "$CHAR_PLUGIN_PACKAGE/manifest.json" \
  "$CHAR_SDK_ROOT/docs/examples/capability-cli-events.jsonl" "$CHAR_PLUGIN_FIXTURE" <<'PYFIXTURE'
import json, pathlib, sys
manifest, sample, output = map(pathlib.Path, sys.argv[1:])
work_end = json.loads(manifest.read_text())["workEnd"]
events = [json.loads(line) for line in sample.read_text().splitlines() if line.strip()]
for event in events:
    event["workEnd"] = work_end
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text("\n".join(json.dumps(event, ensure_ascii=False) for event in events) + "\n")
PYFIXTURE
swift run --package-path "$CHAR_SDK_ROOT" char-plugin-check replay \
  "$CHAR_PLUGIN_PACKAGE" "$CHAR_PLUGIN_FIXTURE"
# Desktop可选用capability-desktop-events.jsonl；各包都绑定自己的workEnd。
# Node快测示例：选择本插件已有的相关测试；不要在调试时反复重跑慢原生套件。
node --test "$CHAR_PLUGIN_WORKSPACE"/tests/*.test.mjs
```

[CLI 回放样本](examples/capability-cli-events.jsonl)包含运行、审批、恢复、子会话与关闭；[Desktop 样本](examples/capability-desktop-events.jsonl)包含运行、轮次结束与关闭。它们是宿主协议示范，**不是某个客户端的真实 Hook 载荷**。构建自己的采集器 fixture 时使用目标客户端实际去敏格式，保留顺序、空白、null、转义字符和调用环境。

replay显示的是整段处理后的最终快照；末尾closed清除根会话时，0气泡/0注意力项是合法结果。若需证明中间提醒，用停顿时截止的样本或协议/路由状态断言；不为最终0反复探索Char源码。

仅做外部插件可用上述 SDK 工具和本插件测试；不必修改主仓库 scripts/check.sh。若本次改变 Char 宿主或内置集成，额外运行 `bash "$CHAR_SDK_ROOT/scripts/check.sh"`。App 的隔离验证需已有可运行实例，外部作者无需为了写插件构建整个 App。

## 6. 性能与交付等级

性能设计与验收采用[集成插件性能要求](plugin-performance.md)：设计前明确进程/运行时成本，常驻路径最小化，按需helper遵守同一请求预算；包版本与Hook版本独立。默认目标、超目标的一次替代对照和GUI验收均在该契约中。

按[基本验收的性能分支](plugin-basic-acceptance.md#6-性能分开测量并保留原始样本)先确认基准脚本的路径/返回值/清理，再做一次轻量采样，分别记录 Hook、单包/双包适配器与延迟的原始样本及边界。运行机制不变时复用结果。两个启用 monitor 包是两个进程，共享源码不会自动合并；原生推送优先，日志增量且有界自动续读。事件正确性通过后再优化，不丢事件、不拖延响应换低占用。

README 包含：包/源码/重建与测试命令；信号/精度矩阵；客户端版本与事实/图标来源；运行时、权限、配置；升级、卸载、回退和共享资源保留方式；性能条件与原始样本；已验证/失败/待验证项。用户交互说明另放 USER-ACCEPTANCE.md。

- **待验收测试包**：开发和适用基本验收通过，已知正确性问题修复，真实客户端/Char 界面留待用户验收。可以明确宣布开发完成。
- **正式支持**：有各交付端所需的原生加载/事件、Char 气泡、导航与热维护证据；未支持的类别仍明确列出。用户反馈可作为验收证据，记录版本、环境与具体路径；不能将一端结果推广全部环境。

默认不发起模型请求或操作用户工作客户端。插件是当前用户权限代码，进程隔离不是沙箱。发布与支持列表按当前授权及实际证据更新。

## 7. 完成交付

按[用户验收交付规范](plugin-user-acceptance.md)准备完整 GUI 步骤、实际包绝对路径、加载方式、等待时间、反馈表和恢复，写入工作区 USER-ACCEPTANCE.md。**最终回复直接给全部填好的步骤，不只贴文件链接，也不以打开 App 或要求解锁代替交付说明。** 用户自行操作；明确要求某项准备或代测时再执行该项。

主动分别报告开发/基本验收完成与待用户验收；收到反馈后只对失败路径修复、重建并提供相应重导入步骤。资源修正不要求重新安装无关客户端集成，GUI 未测试不冒充已通过。
