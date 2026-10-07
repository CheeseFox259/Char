# 当前实现机制与性能摘要

本文描述v1.0.0源码与运行机制；生产校验器是格式契约的实现。

## 模块地图

| 模块 | 职责 | 入口 |
| --- | --- | --- |
| CharCore | 事件、注意力、Hold、配置、几何、滚轮策略、配置代次 | [Sources/CharCore](../Sources/CharCore) |
| CharObservations | 本地日志/Hook分类、增量读取、根会话识别、目录缓存 | [LocalObservationPoller](../Sources/CharObservations/LocalObservationPoller.swift) |
| CharPlatform | 应用激活、Tabbit/VS Code返回、权限、皮肤校验与缓存 | [Platform](../Sources/CharPlatform/Platform.swift) |
| CharPluginHost | 进程协议、能力授权、自检、稳定部署与启停 | [CapabilityHost](../Sources/CharPluginHost/CapabilityHost.swift) |
| CharApp | 观察actor、定时调度、窗口、设置、图层动画、图标 | [Runtime](../Sources/CharApp/Runtime.swift) / [CompanionPanel](../Sources/CharApp/CompanionPanel.swift) |
| char-hook / integrations | 客户端原生信号变换与私有元数据流 | [CharHook](../Sources/CharHook/main.swift) / [integrations](../integrations) |
| char-package-check | 在临时环境调用真实导入/格式校验 | [CharPackageCheck](../Sources/CharPackageCheck/main.swift) |

~~~mermaid
flowchart LR
  A[客户端日志或显式原生扩展] --> B[本地增量观察 actor]
  B --> C[完整事件批次与配置代次]
  C --> D[AttentionRouter]
  D --> E[按工作端聚合的图标气泡]
  E --> F[首次来源捕获与目标应用访问]
  F --> G[Hold 与 Ctrl+B]
  G --> H[原进程或准确标签返回]
  I[能力插件注册表] --> K[版本化进程适配器]
  K -->|原生事件推送| C
  K -->|对象捕获与聚焦| F
  I --> B
  K --> L[所属客户端安装维护]
  J[数据形象包] --> E
~~~

## 观察机制

正常模式每500ms由 ObservationWorker actor读取一次，UI不做日志解析；批次完成后先全部送入路由器，再更新焦点与时间，不叠加轮询任务。

启动时将已有日志/Hook定位EOF。未闭合的最后一行留到下次，不把半个JSON当事件；文件长度/inode识别截短或替换。JournalDirectoryIndex缓存目录inode/mtime/ctime，变化才重新列举；已知日志仍每轮stat并读追加内容，配置根符号链接重新解析。Kimi通过SessionStart绑定工作端并观察主wire，不能把共有存储根等同桌面身份。

客户端桥负责可靠信号，Char不会替客户端启动模型。不同工作端不保证能识别全部七种停顿原因，当前范围见[信号矩阵](signal-feasibility.md)。Kimi/DeepSeek/pi的Hook需显式安装。能力包导入后只自检，设置中的安装维护动作使用稳定入口并备份用户配置；不自动重载工作客户端。监控适配器走本地pipe推送，事件与旧观察器共用批次和公共路由规则。

配置变化递增观察代次，移除对应提醒；快速停用/启用后旧批次被拒绝，重新启用只接收新活动。运行时只接受完整有效目录，不把半写入配置发布为新状态。

## 注意力与往返

路由器在同一executor运行，无I/O或定时器。默认过滤阈值10秒，Hold宽限期300秒。根会话停顿持续超过过滤阈值才进入未查看队列；子会话、启动前记录、过期乱序和重复记录不重复发提醒。批次声音用250ms合并，声音是可关闭的本地效果。

同一工作端聚合多个注意力项，按原因优先级与时间选择下一项。恢复运行或关闭后的未查看项可留为已恢复，状态变淡；点击只激活所属应用不表示准确定位了原会话；成功的精确或应用级访问都会清除所点击的注意力项，失败保留供重试，用户也可右键忽略首项。破碎动画最多使用18个共享图像切片，420ms后清理，Reduce Motion使用淡出。

首次访问前捕获前台来源，任何应用（包括另一个Agent，Char自身除外）都能成为应用级起点。默认连续访问其他Agent保留首次锚点，可选最近起点或不记录；应用级起点也可单独关闭。应用级锚点绑定原应用实例PID；Tabbit/VS Code只有获取可验证的opaque token才用准确锚点。页面正文不用于定位。

Ctrl+B仅在Hold有效时注册，冲突状态在设置呈现；结束Hold即释放。回城成功后结束Hold，失败且来源仍存活可重试；确定来源关闭/原进程结束/依赖准确插件移除会失效。临时查询错误与确认关闭分开处理。手动回到来源也结束Hold，离开Agent时累计宽限、回到Agent暂停。

**内置访问Agent仍是应用级降级**，不能承诺Warp pane、Codex聊天、微信会话的精确定位。v3包可提供独立visit/origin，通过协议报告并确认准确对象；准确origin绑定提供者实例和原应用PID，无法查询保留重试，已移除/升级则失效。Tabbit/VS Code“准确回城能力”图标仅表示已配置对应适配器，不等于当前已授权。

## 插件与本地数据

[集成包](integration-plugin-format.md)版本3统一监控、跳转、准确起点和生命周期，没有Agent/来源分区。workEnd为动态身份，新软件可用独立进程适配器接入而无需改源码；旧七个观察器和三个平台路径保留兼容。导入先验证、复制并再次验证，再原子写注册表；内置删除有tombstone，不随重启恢复。

[形象包](pet-skin-format.md)保留v1七种PNG动作，v2增加独立边缘、跟随图层、主题、气泡样式、音效和行为偏好。资源完整校验、复制再次校验后同目录重命名安装。图片/解析姿态缓存，gaze量化；脚本通过独立JavaScriptCore helper响应有界事件并返回Char动作，无OS桥或逐帧脚本调用。删除恢复默认并停止脚本/音效。[完整接口](appearance-v2-api.md)与[架构决定](adr/0009-appearance-capabilities-and-installed-icons.md)定义权限、超时及恢复。

选中形象/主题的静态安装图标通过原Release备份、暂存App资源替换、重新ad hoc签名和严格验证后事务更新；注册LaunchServices但缓存呈现仍由用户检查。未提供权限沙箱，也不自动改签Developer ID安装；签名变化可能需要重建AX授权。

| 本机位置 | 数据 |
| --- | --- |
| ~/Library/Application Support/Char/settings.json | 过滤、声音、登录等偏好 |
| 同目录 companion.json | 全局放置、归一化位置、大小、气泡距离 |
| 同目录 integrations/registry.json、packages/ | 插件目录、启停、删除记录及资源 |
| 同目录 skins/selection.json、*.charpet | 形象选择和安装包 |
| 同目录 runtime/char-hook、runtime/native-integrations/ | 稳定事件入口和内置原生资源，应用升级部署 |
| 同目录 integration-backups/ | 显式生命周期操作的私有配置备份 |
| 同目录 harness-hooks.jsonl | 显式原生集成写入的元数据流 |
| ~/.claude/projects、CODEX_HOME/sessions、KIMI_CODE_HOME/sessions | 原客户端持有的本地日志 |

注意力项与Hold不跨Char重启恢复。构建/检查不会安装用户Hook。集成包删除可选择保留客户端集成或先卸载所属集成；不会删除原生会话。Char内置流程无网络遥测/模型调用；第三方适配器以用户权限运行，进程隔离不是沙箱，导入可信代码需明确确认。本地观察可能接触含工作内容的日志，气泡不显示其原文。[ADR](adr/0004-local-only-session-data.md)规定本地处理。

## 窗口、命中与动效

非激活透明NSPanel使用statusBar层级、加入Spaces及全屏辅助策略；菜单栏入口提供设置/回城/显示/静音/退出。macOS系统桌面转场速度不由Char修改。Space反馈由 NSWorkspace.activeSpaceDidChangeNotification 确认，遮挡变化只负责透明准备/显示协调；持续可见时保持现状，避免切换后迟到的离开/出现补播；隐藏时先透明准备再出现。普通遮挡/锁屏不作为 Space 证据。公开通知在切换后发出，不提前识别手势开始，。

默认桌宠48pt，可调36–88；气泡固定44pt，间距默认20pt、可调8–72。几何根据轨道弦长计算容量，桌面整圆、四边内向弧；超容量保留最后折叠区，最多3个可点击小泡。无折叠禁止循环。滚轮策略区分普通刻度、无手势阶段的平滑鼠标事件束、触摸板距离累积和惯性。

气泡CGImage独立CALayer呈现，命中取当前presentation位置，不等动画完成。普通滚动240ms按单调 smoothstep 非线性角速度采样；折叠跨越先收小再转移/展开，避免开放边缘反向长弧。二维缩放读取hypot(m11,m12)，避免XYZ聚合导致小泡错误放大。新输入从当前呈现状态接续；过期隐藏回调按代次取消。

桌宠呼吸、轻倾及泡泡闲置走合成器关键帧；悬停为中灰细轮廓、内外弱白色环形柔光，独立图层1.6秒压缩/拉伸与浮动，退出悬停、隐藏或Reduce Motion时停止。柔光使用描边轮廓的shadowPath，圆心透明，气泡图像不因悬停逐帧重绘；位图仅在眼睛/眨眼/短反馈/实际帧或回城叠加改变时更新。眼睛跟随与悬停、窗口穿透命中用60Hz轻时钟；仅在值变化时设置穿透。设置预览由独立AppKit视图以12Hz局部更新，不触发整个SwiftUI表单布局；预览不可见时跳过绘制，Reduce Motion或窗口解绑时停表，关闭设置释放HostingView。Ctrl+B文字只在变化时发布。系统Reduce Motion通知更新偏好，不每帧查询系统设置。

跨显示器默认100ms离开+220ms到达，用共享放置与归一化位置，150ms显示器检测配合workspace通知。离开为零端点速度的五次曲线，到达为零初速阻尼回弹；中断从当前缩放/透明度/边缘位移接续。正常模式优先读取辅助功能焦点窗口；无权限时读取前台应用最前面的可见普通窗口数字几何，以最大屏幕相交面积确定显示器，demo 不启动跨屏查询。自定义形象可替代动作时长。上述是代码参数；实际两屏总延迟还受事件/焦点查询影响，未把参数宣称为计时验收。

## 能力插件成本

监控与使用过的准确起点适配器按需保持进程；访问/生命周期独占适配器完成即退出。一个混合包共享一个进程。宿主不为每插件增加轮询定时器；原生事件推送，沿现有500ms调度取出，准确Hold只检查当前锚点。启停/更新/删除/退出清理进程及订阅；常驻Node/Python的独立RSS必须单独计入，不能套用旧版本Char单进程数据。性能预算与测量见[性能契约](plugin-performance.md)。

## 性能与发布

v1.0.0只在快照或显式配置变化时刷新桌宠与状态栏；当前形象缓存有32MiB解码估算预算、LRU淘汰，切换形象释放非当前资源。图层持有当前纹理，缓存预算不等于整个进程内存上限。

原生日志每次读取512KiB，完整行后解析UTF-8，最长16MiB；超长行安静跳过并输出不含正文/路径的诊断。积压分批立即续读，在消化完本批积压后才更新焦点与推进注意力时间，避免把已恢复的停顿误报。半行、轮转与截短保持代次语义。

性能归属、最新版本测量和已知代价见[性能说明](performance.md)。发行从main与版本tag构建Universal ZIP/DMG和示例附件；ad hoc签名、未Apple公证，安装与权限见[发布指南](macos-release.md)。构建、回放、隔离UI和用户真实客户端使用分别记证据，不由架构描述宣称全环境可用。
