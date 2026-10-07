# Char 1.1.0

降低图片内存开销，提供更准确的性能计量，并更新官方菲比外观示例。

## 更新

- 图片按显示尺寸解码：动画缓存预算 16 MiB，界面图标预算 2 MiB；相同图标共享解码，主题、尺寸和形象切换释放旧资源，响应系统内存压力。
- 避免完整 1024 像素图标触发 AppKit 的大块隐式位图；完整资源仍用于 Finder 安装图标生成。
- 性能面板主要显示 physical footprint，RSS 放在计量详情；分别显示宿主、适配器和形象脚本的当前、平均及采样峰值。读取失败显示不可用。
- 显示可归属图片缓存及共享部分，明确它们已经计入宿主，不将资源估算当作插件独占内存。
- 官方菲比示例提供日光/月夜主题、分层跟随、四边独立动作、气泡皮肤、事件脚本和音效；新增同帧跟随状态接口及制作指南。
- 修正形象点击与拖拽的命中坐标，避免 Space 切换重复播放出现动作。
- 同步安装图标以版本及各架构 Mach-O UUID 识别备份；重签后恢复图标不会恢复旧程序。
- 支持 MP3、AAC、CAF、FLAC、WAV 与 AIFF 音效，提醒优先使用用户音效，其次所选形象的音效。

## 性能

同机 release、隔离演示、菲比日光、桌面 48 pt、30 fps 和 7 个演示工作端：physical footprint 闲置平均约 **57 → 30 MiB**，设置打开约 **89 → 56 MiB**，整段测试峰值约 **100 → 60 MiB**。CPU 约 **0.25%–0.33% 单核**，没有持续增长。实际占用随形象、插件及系统环境变化；这些数据不能与旧面板的 RSS 直接相减。测量方法见 [性能说明](https://github.com/CheeseFox259/Char/blob/main/docs/performance.md)。

## 安装与示例

- `Char-1.1.0-macos-universal.dmg`：拖入应用程序安装。
- `Char-1.1.0-macos-universal.zip`：应用压缩包。
- `Char-1.1.0-examples.zip`：MiniMax CLI/Desktop 插件和新版菲比形象。
- `SHA256SUMS`：附件校验和。

更新前退出 Char，替换 `/Applications/Char.app`；已有配置与已安装形象保留。更新菲比示例需从设置导入新版包，不会自动覆盖你的形象。

macOS 13+，Apple Silicon / Intel。**macOS 版本目前未经过 Apple 公证，首次启动可能需要在 Finder 中右键应用并选择“打开”**。发行包使用 ad hoc 签名；图标同步重签后，辅助功能可能需要重新添加 Char 授权。

菲比语音来自 [Genius-Society/phoebe_chubby](https://github.com/Genius-Society/phoebe_chubby)，遵循 CC BY-NC-SA 4.0。精准导航取决于客户端接口，整屏 Space 动画仍由 macOS 控制。Intel 实机与用户真实 Agent 会话不在本次自动化验收范围内。
