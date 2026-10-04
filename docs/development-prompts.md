# 可直接使用的完整开发提示词

在 Char 仓库根目录交给代码 Agent。三个提示词有完整默认目标，可直接执行；修改目标时只改开头需求段。它们不授权安装用户原生 Hook、发起模型调用、授予系统权限或发布远端变更。

## 配置插件完整开发提示词

~~~text
请为当前 Char macOS 仓库制作一个可直接导入的配置插件：
目标是让已有 Codex CLI 工作端在 Apple Terminal 中访问；名称 Codex CLI in Terminal，
ID personal.codex-terminal，输出 build/codex-terminal.charintegration。不需要自定义图标。

先阅读 AGENTS.md、CONTEXT.md、docs/plugin-development.md、
docs/integration-plugin-format.md、Sources/CharCore/IntegrationPlugins.swift、
Sources/CharApp/RuntimePlugins.swift。以生产校验代码为格式依据。

当前 .charintegration 是配置包，不执行代码、不安装 Hook。
只能使用现有 workEnd 和 returnAdapter；不要虚构新协议或精准 Terminal tab 能力。
必须交付如下完整 manifest.json：
{
  "schemaVersion": 2,
  "id": "personal.codex-terminal",
  "name": "Codex CLI in Terminal",
  "workEnd": "codexCLI",
  "bundleIdentifier": "com.apple.Terminal"
}
包中不包含脚本/符号链接。这个配置改变导航应用，Codex日志观察仍使用现有协议。
若本机 Terminal 的 bundle ID 与该值不同，先以只读方式查证并报告，不静默猜测。

执行：
swift run char-package-check integration build/codex-terminal.charintegration
必须退出0并输出 VALID。不得把其他单元检查的通过冒充这个包的校验。

把 README、安装和回退说明放在 build/codex-terminal-delivery/，不要放入包：
1. 设置导入前先停用现有 Codex CLI 观察配置，避免同工作端冲突。
2. 从设置的导入插件选择该目录；修改后先删除旧ID再重导。
3. 导入不安装原生Hook，不获取准确窗口/标签导航。
4. 停用/删除此配置只改变Char配置；可恢复/重新启用原内置配置。
如用户未明确同意，不操作其当前插件列表、不修改其Agent配置。

最终返回包绝对路径、清单、实际校验命令和退出码、安装/回退说明。
未运行的实际应用跳转必须注明，不要声称已验收。
~~~

## 新 Agent 协议或准确回城适配器的源码开发提示词

~~~text
请在当前 Char 仓库开发我指定的新原生集成。若我没有提供客户端名称、
安装位置及“提醒/准确回城”的目标，先用一个问题补齐这些输入，同时阅读
AGENTS.md、CONTEXT.md、docs/plugin-development.md、docs/signal-feasibility.md、
docs/adr/0007-unified-integrations-and-free-origins.md，检查当前工作树并保留现有改动。

先查证目标客户端官方事件/日志/API或本地已安装源码。
产出短能力矩阵：根会话来源、CLI/Desktop身份、running/question/approval/
turnEnded/failure/rateLimit/contextExhausted/unclassified/closed分别有什么可靠证据。
没有证据的类别明确不支持；不得从自然语言内容或沉默推断。不要发起模型请求来造证据。
报告当前 .charintegration 只能选择已编译适配器；新增协议必须修改源码。

提醒能力的实现：
- 扩展 Sources/CharCore/Models.swift 的 WorkEnd，更新全部穷举分支和
  Sources/CharCore/IntegrationPlugins.swift 内置配置、CompanionPanel.swift中的WorkEnd展示分支、
  RuntimePlugins图标、CLI标记、全工作端fixture；不要复用别的Agent的WorkEnd。
- 在 Sources/CharObservations 实现可靠分类/读取，或在 integrations 新建
  原生观察扩展并通过 Sources/CharHook/main.swift 的独立模式写元数据。
- 用稳定原生SessionKey、真实时间、根身份、running/stopped/closed形成ObservationEvent。
  不写问题、命令、消息正文；沿用JSONEncoder日期和枚举编码。原生Hook流
  默认是 ~/Library/Application Support/Char/harness-hooks.jsonl，支持CHAR_HOOK_EVENTS。
- 启动和重新启用以EOF为基线，只处理完整新行；保持500ms轮询、批次时间排序、
  重复/乱序水位、半行、截短、文件轮转、目录/符号链接根变化、子会话过滤、
  快速停用再启用代次与原客户端返回/错误语义。
- 原生扩展安装与Char配置导入分开，提供备份、显式安装、卸载步骤；
  不自行写用户持久配置。

若目标含准确回城：
- 扩展ReturnAdapter和清单验证及Sources/CharPlatform/Platform.swift的捕获/
  存活/匹配/返回/删除依赖路径，必要时加客户端本地桥。
- 捕获opaque token并绑定原进程，确认精确聚焦后才返回exact；只激活应用返回fallback。
- 临时查询失败保留Hold以重试，确定关闭才失效；访问多个Agent保留首次锚点；
  任意前台Agent也可成为来源。绝不能把fallback标为已查看。
- 使用客户端正式接口；系统授权通过显式设置操作。不要读取网页/聊天正文作定位。

先添加能抓住真实协议错误的fixture再实现，在临时目录运行，拒绝未知/子/过期事件；
覆盖清单冲突、启停/删除、根身份、恢复/关闭与实际支持的原因。
命令：
bash scripts/check.sh
bash scripts/build-app.sh
build/Char.app/Contents/MacOS/Char --smoke
codesign --verify --deep --strict build/Char.app
仅在原生环境和用户授权齐备时实际验收；fixture不算真实客户端验收。

交付：代码和测试、完整.charintegration配置包、能力矩阵、
安装/卸载指南、实际检查记录、剩余类别和准确导航边界。
若新集成没有可靠信号或准确API，给出已查证的阻断证据与最小后续方案，
不要用虚构实现完成交付。遵循仓库原有分支/Issue约定，不擅自提交远端或合并。
~~~

## 外观形象包完整制作提示词

~~~text
请为当前 Char 制作可导入的桌宠形象包：
角色是奶白色粗圆角小方块、两个竖线眼睛、没有手脚，细深色描边，
温柔可爱。名称 Moon Square，ID studio.moon-square，
输出 build/moon-square.charpet；不要改变Char窗口、气泡或系统Space动画。

先阅读 docs/appearance-development.md、docs/pet-skin-format.md、
Sources/CharPlatform/PetSkins.swift、Sources/CharApp/RuntimePlugins.swift，
并检查 Resources/Skins/example.charpet/manifest.json。以生产校验器为准。
形象包不执行代码，自定义眼睛目前没有鼠标方向通道，不声称会自动跟随鼠标。

制作128×128透明画布、anchor {x:0.5,y:0.5}，七组单独的8-bit RGBA PNG：
idle 48帧@24fps；press 12帧@24fps；return 12帧@24fps；
depart 12帧@24fps；arrive 12帧@24fps；edgePeek 12帧@24fps；
edgeHide 12帧@24fps，共120引用。每组至少2帧。
采用保持体积的柔和压缩/拉伸与阻尼回弹，不用均匀机械缩放。
idle包含呼吸、轻倾、眨眼，首尾连续。press压缩后回弹；return短弹性反馈。
depart逐渐收小/透明，arrive从小/透明展开。edgeHide/edgePeek要与App施加的
边缘缩回/探出叠加检查，避免双重移动或角色跑出128画布。
保持人物比例、线宽、颜色和眼距一致，眼睛与身体一起运动。

可以用代码绘制矢量再栅格化，或用可用图像工具制作后切帧。
生成器脚本、预览网格/动画和README放在build/moon-square-delivery，
不放入.charpet。若需要工具安装先报告依赖，不擅自安装。
每一帧实际存在，不交付空白帧、同一静态图冒充全部动画或只有清单的包。

manifest.json必须实际枚举每组所有有序路径，schemaVersion:1，
canvasSize:{width:128,height:128}，clips只包含
idle/press/return/depart/arrive/edgePeek/edgeHide，fps与上面一致。
包内只有manifest.json与被引用PNG；不留未引用图片、APNG、RGB或索引色PNG、
符号链接。清单≤64KiB、单PNG≤4MiB、整包≤32MiB、≤600目录项、
≤480帧引用、唯一帧像素总量≤16777216。这个目标120张128×128在预算内。

执行：
swift run char-package-check skin build/moon-square.charpet
必须退出0；检查真实帧的RGBA类型、尺寸、非空alpha和首尾连续性。
生成包外的七动作预览并实际查看，检查角色身份、透明背景和裁切，不仅看文件数量。
说明设置“导入形象”会导入并立即选择，重名ID更新须先删除旧自定义包。
未明确获准时不修改用户皮肤目录或当前选择。

如可运行Char且用户同意切换测试形象，检查桌面/四边、36/48/88pt、
press/return、跨屏、Reduce Motion、重启选择与删除回退；
否则这些标为未运行。不把格式校验说成互动和性能验收。
最终交付包绝对路径、生成器和预览、实际校验结果、安装/更新/删除说明，
以及唯一帧数×尺寸×4的像素内存估算和实际测量边界。
~~~
