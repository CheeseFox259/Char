# 能力插件实施与验证

日期：2026-10-06。分支：`codex/capability-plugins`。这是开发版本；尚未发布、合并或替换正式 `/Applications/Char.app`。

## 已完成

| 部分 | 实现与证据 |
| --- | --- |
| 动态工作端 | WorkEnd 字符串身份，清单提供名称/图标/CLI类别；独立新 ID 聚合并创建原生气泡 |
| v3 包 | monitor/visit/origin/lifecycle 独立组合；旧 v1/v2、七个内置观察器与旧平台适配保持兼容 |
| 热加载 | 导入、自检、启停、同ID更新、删除，不要求重启 Char；更新保留启停、重建代次、退出旧进程 |
| 协议宿主 | 版本1 JSON Lines，进程外请求/事件、能力检查、身份约束、超时和错误清理；停用插件的维护进程也受宿主管理 |
| 来源与回城 | 插件捕获/检查/聚焦/释放具体对象；锚点绑定原PID和适配器实例，宿主管理首次/最近/关闭策略与应用级起点偏好 |
| 生命周期 | 设置中自检/安装/更新/移除，状态图标区分配置可用、需安装更新、需重载、不可用；可选择卸载集成并删除 |
| 稳定入口 | 打包携带 canonical 原生资源，宿主部署到当前用户 Char/runtime；客户端配置不再依赖开发目录 |
| 原生维护 | pi、Kimi CLI/App、DeepSeek 的所属安装升级卸载，私有备份；Kimi迁移并去重历史Char Hook，共享客户端保留必要Hook |
| 开发交付 | 包骨架、生产格式校验、握手自检、事件回放、完整协议/指南及三个通用次级 AGENTS.md |

原生客户端可能需要重载：热加载的是 Char 的包/适配器；正在运行的 pi 扩展、桌面客户端或 Hook 加载不能由此推断。安装结果显示 reloadRequired；inspect 的 ready 仅证明它能核对的配置，真实监控需自然活动验收。

## Verified

- `bash scripts/check.sh`：完整项目门槛通过，包括宿主新客户端、旧观察/平台契约、Hook、pi、Kimi、DeepSeek和原生生命周期。
- `swift run char-plugin-checks`：临时新包导入，声明之外身份拒绝、子会话过滤、动态聚合、visit、capture/check/focus、install/update/uninstall、禁用/更新/删除、版本错、坏帧、超时；禁用和退出后用 OS PID 存活检查确认维护/监控进程退出。
- `python3 Tests/check_new_agent_hooks.py .build/debug/char-hook`：旧路径迁移、历史重复Char Hook去重、幂等、不改其他Hook及并发私有事件写入。
- `node integrations/native/adapter.test.mjs .build/debug/char-hook`：临时 HOME 中 pi/Kimi/DeepSeek install→inspect→update→uninstall；保留用户文件、同事件用户Hook、无关TOML/YAML与共享Kimi安装。
- `bash scripts/build-app.sh` 与 `codesign --verify --deep --strict build/Char.app`：生产优化构建、原生资源打包和 ad hoc 签名检查通过。
- 解锁期间 `build/Char.app/Contents/MacOS/Char --smoke` 通过；最终构建 `--capability-smoke` 单独复验新增动态包的原生 App 路径通过。通用smoke最后一次复跑失败见下文；真实进程适配器→事件→Char气泡→模拟精确访问→捕获起点→模拟确认回城→禁用/更新/删除。没有激活用户客户端或发起模型请求，导航精度为 fixture 证据。
- `scripts/new-capability-plugin.py` 实际生成临时包；`char-package-check integration` 通过，`char-plugin-check inspect` 骨架正确返回 notInstalled，未假报完成；`char-plugin-check replay` 三条记录解码为一个气泡/一个注意力项，子记录不提醒。
- CUA 查看隔离设置：能力使用图标，独立插件显示可用，维护菜单包含自检/安装/更新/移除；点击 fixture 安装后变为“需要重载客户端”。首次起点和应用级起点设置可见。没有操作正式客户端的安装/授权菜单。
- `git diff --check`：通过。

验收包在临时注册表创建，主程序未加入该客户端的分支/枚举常量。新增源文件中的 fixture 是测试数据，不是生产客户端专用实现。

## 性能证据

机型 Mac16,12，macOS 26.5.1；本机 Node 26.5.0。运行 `swift run char-plugin-checks --measure`，监控适配器握手/发出fixture事件后静止20.83秒；通过 `/bin/ps` 两次读取该进程累计 CPU 时间及 RSS，CPU 为时间差/墙钟，100%代表一核。

| 项 | 实测 |
| --- | --- |
| 适配器累计CPU增量 | 两次显示值相同；计算显示0.000%，低于ps计量精度，不能宣称零开销 |
| Node适配器RSS | 47.86 → 47.86 MiB |
| 禁用后 | 宿主进程列表清空，原PID经OS检查不存在 |
| 停用插件维护时退出 | 临时维护进程也被宿主停止，原PID不存在 |

这是单个空闲 fixture 适配器的成本，不是活跃客户端、Char整体或电池/GPU测量。没有测多插件线性增长，也未把原v0.1.2数据冒充新版本实测。额外常驻内存值得关注：当前内置原生维护适配器是按需进程，不会为四个内置客户端平白保留四个Node进程。新增monitor插件会常驻一个进程；origin按需启动并保持实例状态；visit/lifecycle-only操作后退出。一个混合包共用进程，无每插件高频轮询，沿已有500ms批次取出推送事件。

下一步优化先测真实插件是否在空闲时仍查询/解析，再选增量读取、缓存或更轻的运行时；不以延迟事件或隐藏内存成本作为性能优势。

## Not run

- 新构建安装后的真实 pi、Kimi CLI/App、DeepSeek 重载与自然事件验收；本阶段未改它们当前已经修复的客户端配置，也没有代替用户重启工作会话。
- 新第三方客户端的真实准确窗口/会话导航；独立适配器的协议路径已证明，客户端自身可靠性须逐插件验收。
- Universal Release发布、公证、远端合并与下载安装；当前工作是实现/本地验证。
- 真实常驻观察模式整机功耗、GPU/WindowServer及长期多插件峰值。

## Blocked / Not applicable

能力插件必要验证已完成。界面检查曾因Mac锁定暂停，用户解锁后完成。最终通用smoke复跑在既有“Space notification arrival feedback”断言失败，未算作通过；当前生产插件代码此前的完整smoke通过。没有据此修改Space行为或削弱其断言；新增--capability-smoke单独复验插件原生路径，通用Space gate在发布前需复验。交互预览中提醒被确认后会使测试项失效，fixture已改用重新取当前项/必要时补建测试项，避免强制解包；普通最终smoke通过。

没有调用外部模型，不需要服务端/网络迁移。进程隔离不是权限沙箱，不把第三方插件的行为承诺为Char内置的隐私保证。

## 开发入口

- [开发指南](plugin-development.md)、[格式v3](integration-plugin-format.md)、[协议v1](capability-adapter-protocol.md)、[架构决定](adr/0008-process-capability-plugins.md)。
- [实现指令](../integrations/AGENTS.md)、[交付包指令](../Resources/Integrations/AGENTS.md)、[外观指令](../Resources/Skins/AGENTS.md)。

## 发布前复验

2026-10-06：再次运行 `build/Char.app/Contents/MacOS/Char --smoke`，包括此前失败的 Space notification arrival feedback 在内的完整原生烟测通过。未修改生产 Space 行为或削弱断言。v0.2.0 发布与下载安装证据另记于版本验证记录。

## 发布完成

v0.2.0 已合入 main、经远端 Universal 构建发布，并从 GitHub Release 安装到 `/Applications/Char.app`。此前未发布状态与失败记录为开发时历史；最终下载产物的完整烟测通过。实际配置迁移与验收边界见 [版本验证记录](release-verification-0.2.0.md)。
