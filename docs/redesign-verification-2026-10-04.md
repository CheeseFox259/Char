# 插件与桌宠视觉扩展验收

本报告对应 Issue #14 和 `2026-10-04-plugins-and-companion.md`。前一阶段原生信号、Ctrl+B 和 Tabbit 延迟的证据仍见 `acceptance-2026-10-04.md`；不能把那些结果当作本次视觉扩展已通过。

## 已验证

初次集成版本 `32d9935`：

- `scripts/check.sh` 通过：原有设置、注意力/Hold、11 组观察、平台/快捷键及四类本地集成检查；新增插件持久化/导入/删除三组、热停用与重新启用、来源插件及目标应用覆盖、自定义形象真实包校验、轨道布局检查。
- `scripts/build-app.sh` 生成签名的 release 包；`--smoke` 实际运行原生窗口，验证七工作端、模拟快捷键、首次锚点、忽略、来源删除、五种放置过渡完成、插件停用及不重放、捆绑形象导入/切换/删除。导航为 fixture，不能证明真实应用切换。
- CUA 检查了实际圆环、溢出小气泡与设置。通过设置停用 Claude 后，对应气泡立即消失；其它气泡保留。原生截图还发现按钮坐标翻转导致脚在顶部，已提交修正；边缘物理裁切的回归检查先失败后修正。

## 两轴审查

固定 PR 基线 `f5d7d46`，审查 HEAD `32d9935`，使用完整 PR diff。

### Standards

发现 1 项 P2 异步观察批次代次风险、1 项 P3 ADR 来源规则冲突、1 项 P3 重复气泡绘制的判断项。

### Spec

发现 3 项 P2：自定义动画被固定时限截短、边缘动画未定向、快速停用再启用旧批次回流；另有 P3 缺少形象预览。

所有发现交由同一修复实现者处理。修复后证据追加于下。

## 系统边界与未运行项

- 手动切换 Space 的方案选择桌宠持续存在。窗口使用公开的所有 Space / 所有应用参与策略；真实手势、全屏应用和 Stage Manager 环境仍需实机反馈。
- [整屏回城 Space 动画 #15](https://github.com/CheeseFox259/Char/issues/15)：Char 可以控制自身动画并立即派发原生激活。所检查的公开 AppKit 窗口 API 没有整屏 Space 合成器速度/曲线设置；这是该实现路径的能力边界，不能宣称已复制触摸板切换。[窗口参与策略](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)、[所有 Space](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces)、[所有应用](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)。
- 真实多显示器迁移、系统 Reduce Motion、VoiceOver 使用体验未作为已通过记录。
- CUA 的滚轮调用返回 AXError.notImplemented，不能作为真实滚轮事件证据；布局循环契约和可见菜单路径单独验证。
- 发布签名/公证与应用商店分发不适用本次本地实现。

## 修复与最终包

- 修复提交 `3c192f3`：逐工作端配置代次跟随 actor 批次，卸载/重启后拒绝旧批次，未改变的工作端仍可接收；乱序配置不能回滚，跳过停用任务的重启仍执行新观察基线。既有 ADR 显式修订。
- 同一修复提交完成物理屏幕裁切检查、NSButton 坐标方向、按自定义动画真实时长播放、四边定向、动作中断优先级、所选形象预览和可见循环菜单。两轴限定复查确认此前发现全部解决；复查只读，没有把复查计为新运行测试。
- `scripts/check.sh` 在根目录修复版通过，包括配置代次、物理四边、循环可达性、完整动画时长和 1 fps 有效形象最后帧的新检查。发布构建、实际包 `--smoke` 与严格签名检查通过。
- `656d454` 修正 Retina 缓存的重复缩放。原生位图检查先发现错误像素范围，修正后恢复正确 2× 逻辑尺寸和外层上下文；根目录实际截图确认圆泡完整、默认宠物脚在底部。设置切换左边缘后的实际截图确认部分身体隐藏、六个位置的气泡均在屏幕内侧。无障碍 orbit next/previous 与 Open Settings 动作已可访问；设置显示形象预览。
- 文件选择器实际打开，误选非形象测试目录被严格拒绝。CUA 的 Go to Folder 按键操作超时，已取消对话框；**未声称有效包通过完整 UI 选择流程**。有效包导入/渲染/删除由最终原生包 smoke 和真实包契约覆盖。
- 原生演示观察到持续重绘版约 42–44% CPU / 235–251 MiB RSS，缓存版仍有较高 CPU，因而进一步修复绘制路径。`74abb87` 把气泡和溢出容器移至独立图层，60 Hz 仅更新变换，桌宠局部重绘；此最终实现的根目录发布构建、实际包 smoke、严格 codesign 和 diff 检查通过。最终图层实现不改变之前核心/观察逻辑。
- **Blocked：** `74abb87` 演示启动后 CUA 返回 Mac 已锁定且无法自动解锁。因此最后一次图层改动后的实际截图和可比较的 CPU 样本尚未完成；不会把锁屏采样或代码推断作为性能通过。

最终演示从根目录 `build/Char.app` 运行 `--demo`，使用临时设置和模拟导航；保留供使用者解锁后体验。它不是正常原生提醒实例。当前 PR 保持草稿，待最终实机检查和第 5 项整屏 Space 动画范围决定。
