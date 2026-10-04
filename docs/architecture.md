# 当前实现机制与性能摘要

本文是当前源码的导航。历史验收日志保留其当时版本和结果；格式以生产校验器为准。

## 模块地图

| 模块 | 职责 | 入口 |
| --- | --- | --- |
| CharCore | 事件、注意力、Hold、配置、几何、滚轮策略、配置代次 | [Sources/CharCore](../Sources/CharCore) |
| CharObservations | 本地日志/Hook分类、增量读取、根会话识别、目录缓存 | [LocalObservationPoller](../Sources/CharObservations/LocalObservationPoller.swift) |
| CharPlatform | 应用激活、Tabbit/VS Code返回、权限、皮肤校验与缓存 | [Platform](../Sources/CharPlatform/Platform.swift) |
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
  I[配置插件注册表] --> B
  I --> F
  J[数据形象包] --> E
~~~

## 观察机制

正常模式每500ms由 ObservationWorker actor读取一次，UI不做日志解析；批次完成后先全部送入路由器，再更新焦点与时间，不叠加轮询任务。

启动时将已有日志/Hook定位EOF。未闭合的最后一行留到下次，不把半个JSON当事件；文件长度/inode识别截短或替换。JournalDirectoryIndex缓存目录inode/mtime/ctime，变化才重新列举；已知日志仍每轮stat并读追加内容，配置根符号链接重新解析。Kimi通过SessionStart绑定工作端并观察主wire，不能把共有存储根等同桌面身份。

客户端桥负责可靠信号，Char不会替客户端启动模型。不同工作端不保证能识别全部七种停顿原因，当前范围见[信号矩阵](signal-feasibility.md)。Kimi/DeepSeek/pi的Hook需显式安装，配置插件导入不会代替这一步。

配置变化递增观察代次，移除对应提醒；快速停用/启用后旧批次被拒绝，重新启用只接收新活动。运行时只接受完整有效目录，不把半写入配置发布为新状态。

## 注意力与往返

路由器在同一executor运行，无I/O或定时器。默认过滤阈值10秒，Hold宽限期300秒。根会话停顿持续超过过滤阈值才进入未查看队列；子会话、启动前记录、过期乱序和重复记录不重复发提醒。批次声音用250ms合并，声音是可关闭的本地效果。

同一工作端聚合多个注意力项，按原因优先级与时间选择下一项。恢复运行或关闭后的未查看项可留为已恢复，状态变淡；点击只激活所属应用不表示查看了原会话。精确访问才清除对应项，用户也可右键忽略首项。

首次访问前捕获前台来源，任何应用（包括另一个Agent，Char自身除外）都能成为应用级起点。连续访问其他Agent保留首次锚点。应用级锚点绑定原应用实例PID；Tabbit/VS Code只有获取可验证的opaque token才用准确锚点。页面正文不用于定位。

Ctrl+B仅在Hold有效时注册，冲突状态在设置呈现；结束Hold即释放。回城成功后结束Hold，失败且来源仍存活可重试；确定来源关闭/原进程结束/依赖准确插件移除会失效。临时查询错误与确认关闭分开处理。手动回到来源也结束Hold，离开Agent时累计宽限、回到Agent暂停。

**当前访问Agent均是应用级降级**，不能承诺Warp pane、Codex聊天、微信会话的精确定位。Tabbit/VS Code“准确回城能力”图标仅表示已配置对应适配器，不等于当前已授权。

## 插件与本地数据

[集成包](integration-plugin-format.md)版本2统一提醒与回城能力，没有Agent/来源分区。七个workEnd及三个returnAdapter是编译期集合；新增协议需改源码。导入先验证、复制并再次验证，再原子写注册表；内置删除有tombstone，不随重启恢复。

[形象包](pet-skin-format.md)版本1只提供七个动画PNG序列；完整校验后以同目录重命名安装。设置导入后立即选择，自定义删除回到内置方块。图片按帧身份缓存；不加载脚本。自定义位图没有默认方块的程序化眼睛跟随协议。

| 本机位置 | 数据 |
| --- | --- |
| ~/Library/Application Support/Char/settings.json | 过滤、声音、登录等偏好 |
| 同目录 companion.json | 全局放置、归一化位置、大小、气泡距离 |
| 同目录 integrations/registry.json、packages/ | 插件目录、启停、删除记录及资源 |
| 同目录 skins/selection.json、*.charpet | 形象选择和安装包 |
| 同目录 harness-hooks.jsonl | 显式原生集成写入的元数据流 |
| ~/.claude/projects、CODEX_HOME/sessions、KIMI_CODE_HOME/sessions | 原客户端持有的本地日志 |

注意力项与Hold不跨Char重启恢复。构建/检查不会安装用户Hook。配置包删除不改变原客户端配置。无网络遥测/模型调用；本地观察可能接触含工作内容的日志，气泡不显示其原文。[ADR](adr/0004-local-only-session-data.md)规定本地处理。

## 窗口、命中与动效

非激活透明NSPanel使用statusBar层级、加入Spaces及全屏辅助策略；菜单栏入口提供设置/回城/显示/静音/退出。macOS系统桌面转场速度不由Char修改。手动Space局部重现方案按用户接受的范围保留，不宣称所有全屏/Space条件均已通过。

默认桌宠48pt，可调36–88；气泡固定44pt，间距默认20pt、可调8–72。几何根据轨道弦长计算容量，桌面整圆、四边内向弧；超容量保留最后折叠区，最多3个可点击小泡。无折叠禁止循环。滚轮策略区分普通刻度、无手势阶段的平滑鼠标事件束、触摸板距离累积和惯性。

气泡CGImage独立CALayer呈现，命中取当前presentation位置，不等动画完成。普通滚动180ms线性角速度；折叠跨越先收小再转移/展开，避免开放边缘反向长弧。二维缩放读取hypot(m11,m12)，避免XYZ聚合导致小泡错误放大。新输入从当前呈现状态接续；过期隐藏回调按代次取消。

桌宠呼吸、轻倾及泡泡闲置走合成器关键帧；位图仅在眼睛/眨眼/短反馈/实际帧或回城叠加改变时更新。眼睛跟随与悬停、窗口穿透命中用60Hz轻时钟；仅在值变化时设置穿透。设置关闭后移除HostingView，避免隐藏TimelineView常驻布局。系统Reduce Motion通知更新偏好，不每帧查询系统设置。

跨显示器默认90ms离开+150ms到达，用共享放置与归一化位置，150ms显示器检测配合workspace通知。自定义形象可替代动作时长。上述是代码参数；实际两屏总延迟还受事件/焦点查询影响，未把参数宣称为计时验收。

## 性能证据与下一步

完整过程、方法和排序方案见[性能分析](companion-performance-2026-10-04.md)。以下均是Char自身累计CPU时间差/墙钟，100%为单核；不含WindowServer/GPU。

| 场景与采样源码 | CPU单核平均 | RSS | 证据边界 |
| --- | ---: | ---: | --- |
| 正常观察、零泡，旧740c583 | 18.84% | 约48.4MiB | 20秒历史顺序样本 |
| 正常观察、零泡，3c7e62d | 5.75% | 约58.3MiB | 开始/结束均解锁，20秒 |
| 七泡、8pt间距、空Agent根/私有Hook，3c7e62d | 4.75% | 64.7–65.8MiB | 视频防锁屏、设置关闭，20秒 |

已执行：最小stat元数据、目录列表缓存、追加读取、位图缓存、合成器idle、隐藏设置释放、稳定窗口穿透和相同快照不重复发布。缓存增加内存，跨日多项改动/日志树/背景条件不同，不能隔离每项贡献，也不能相减算I/O成本。**这些不是本次图标修改后的新测量。**

剩余样本可见AX/CG焦点窗口查询、目录/文件stat、60Hz指针与命中读取和CA事务。下一阶段先拆分应用身份与显示器几何查询，再评估静止指针降频；验证要同版本/同根/同气泡/同设置状态复测，同时检查新日志发现与动画，不能靠降低及时性换CPU数字。

实体滚轮最终正常包在USB接收器模式下由用户确认首格、连续、反向与轻动均正常。有线采集无及时有效输入，具体原因未确定，仍是已记录兼容问题；临时设备/系统探针已清理。详情见[滚轮诊断](wheel-diagnosis-2026-10-05.md)。

## 发布状态

当前是本地ad hoc签名macOS包，未Developer ID签名、公证或发布安装器。构建/fixture通过与用户实机反馈分别记录；真实多屏、完整VoiceOver/Reduce Motion、睡眠/登录及部分来源异常路径仍有历史未运行项。源码推送不代表这些项目已验收，见[文档索引](README.md)中的各报告。
