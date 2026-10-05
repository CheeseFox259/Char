# 通用指令与动效验证，2026-10-05

## 范围与原因

焦点不跟随来自遗留 `--demo` 进程；demo 不读取真实 foreground，未启动跨屏检测。切回正常模式后，用户在两块屏幕之间切换应用窗口，确认跟随及边缘状态正常。保留原150ms检测和工作窗口几何路径，不将鼠标位置当作工作焦点。

Space旧实现把任意隐藏当作 Space 准备，并且仅准备半缩小、不透明姿态；全Spaces持续可见时 workspace 通知被忽略。首轮实现让 workspace 通知确认切换，窗口可见性辅助协调；透明准备、持续可见的离开/出现、隐藏后的出现均使用同一桌宠+气泡场景。下表记录首轮，最终修正见后续实机反馈。运动期间重复通知不重播；跨屏已有离开/出现时由迁移姿态完成反馈。

| 修改前 | 修改后 |
| --- | --- |
| 隐藏首帧仍不透明，缩到一半 | 隐藏即同步提交整个场景透明姿态 |
| 持续可见的Space通知无反馈 | 确认通知触发180ms离开+600ms回弹出现 |
| 气泡180ms匀速路径 | 240ms单调缓入缓出，折叠收小/移位/长大同步采样 |
| 跨屏初始速度跳变 | 100ms五次离开+220ms零初速阻尼回弹；保留中断姿态 |

公开API边界：[activeSpaceDidChangeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification)在发生Spaces变化时发出，不提供手势开始事件或Space ID；[occlusionState](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.struct)只描述遮挡。窗口保留[canJoinAllSpaces](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces)和[stationary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/stationary)策略。离开反馈从可用通知起播放，不宣称在系统滑动开始前收起。

## 自动检查

- 改动前 `Char --smoke --space-motion-check`：失败 `hidden Space first frame is not transparent`。
- 改动后同检查：通过透明首帧、确认出现、持续可见离开/出现。
- `bash scripts/check.sh`：通过核心、观察、平台、形象包、Hook和原生集成契约检查。保留USB接收器已验收的滚轮策略。
- Release构建、完整原生 `--smoke`、`--smoke --space-motion-check`、`--smoke --orbit-path-check` 和 ad hoc 签名检查：通过。完整smoke第一次失败是测试仍等待300ms，而新迁移默认320ms；等待改为450ms使检查从静止状态开始，未削弱Space首帧/完成断言。

实际图层检查读取提交给CALayer的 position/scale 样本，拒绝可见反向长弧和匀速路径；包含正向、反向及中途接续。模拟workspace通知只验证应用路径，不代表系统手势完整实测。

## 实机与性能

用户确认新版正常模式的跨屏与气泡轮换正常；Space仍先完整出现再重播（无闪烁），见下方修正。本次没有添加持续采样、显示器查询或新绘制时钟；气泡曲线在输入时一次生成25个样本，由合成器播放，Space使用现有60Hz时钟。此前性能数字见 [性能分析](companion-performance-2026-10-04.md)，不是当前版本的CPU测量。优先优化路径仍是动态图像重绘/焦点AX查询；曲线数学开销按代码机制判断较小，未用历史样本宣称新版本变快。

三份通用指令位于 Resources/Integrations、integrations、Resources/Skins 的 AGENTS.md，包资源复制排除这些文件。安装包和形象包的开发标准指向生产验证器，不预设具体插件或角色设计。

## 后续实机反馈与修正

用户确认气泡轮换、跨屏同步正常；Space先完整出现再重播，说明可靠公开通知到达后补播离开/出现不能解决提前收起。最终策略：全Spaces窗口持续可见时保持连续；仅实际隐藏并透明准备过的场景，在确认切换后非线性重现。避免用晚到的通知补演已过去的过程。

对前一提交4aebd92运行新的无补播断言：失败 `already-visible Space replayed appearance`；修正版同一原生路径通过。这条检查保留在 `--smoke --space-motion-check`。

悬停改为1.8pt深灰轮廓、内外白色柔光和1.8秒缓入缓出的轻呼吸。使用固定圆形shadowPath和独立图层，移出/隐藏/Reduce Motion时停止；不新增图片重绘时钟。黑白背景真实观感与最终Space连续性待本次实机确认。

修正后的 scripts/check.sh、Release构建、完整原生smoke、Space专项检查和严格签名验证均通过。图层轮换路径未在此次悬停修改中改变；此前实际正向/反向/中断路径检查通过。
