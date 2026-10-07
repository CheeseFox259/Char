# Char 1.0.0

首个稳定版本：本地 Agent 注意力桌宠、图标气泡与 Ctrl+B 回城。

- 支持 Claude Code、Codex CLI/Desktop、Kimi CLI/App、DeepSeek Harness Desktop 与 pi；提供 MiniMax CLI/Desktop 能力插件示例。
- 插件支持不重启导入、启停、同 ID 更新与所属集成卸载；新增客户端无需修改 Char 源码。
- 桌面和四边放置、焦点跨屏跟随、弹性动效、眼睛跟随、悬停律动、折叠轮换与点击破碎；支持减少动态效果。
- 自定义形象支持动作、独立边缘姿态、主题、跟随层、气泡皮肤、音效与受限事件脚本；附可导入的菲比示例与源码。
- 设置中英切换、状态栏入口、原生 CPU/RSS 性能面板；性能数据有明确归属与测量范围。
- 宿主只在变化时刷新界面；形象缓存设预算并释放旧形象；日志分批续读并保持完整积压的提醒语义。
- 内置集成：pi/DeepSeek 直接写入白名单元数据；共享 Hook 读取和 Kimi 解码、Claude/Codex 日期解析减少重复工作，维护 EOF 排空。
- MiniMax 原生常驻入口约 9.6 MiB RSS/端，按需调用维护 helper。
- 整理公开文档与三份开发指令，保留实现、契约、性能、安装及用户验收资料。

## 下载

- `Char-1.0.0-macos-universal.dmg`：拖入应用程序安装。
- `Char-1.0.0-macos-universal.zip`：应用压缩包。
- `Char-1.0.0-examples.zip`：两个 MiniMax 插件与菲比形象。
- `SHA256SUMS`：附件校验和。

macOS 13+，Apple Silicon / Intel。当前为 ad hoc 签名，未经过 Apple 公证，首次打开可能需要 Finder 右键“打开”或系统隐私与安全性中的“仍要打开”。

精准导航受各客户端接口限制；普通跳转/回城仅保证激活应用。Space 整屏动画由 macOS 控制。第三方集成运行于当前用户权限；形象脚本仅开放 Char 事件和动作。

菲比语音来自 [Genius-Society/phoebe_chubby](https://github.com/Genius-Society/phoebe_chubby)，遵循 CC BY-NC-SA 4.0。支持 MP3、AAC、CAF、FLAC、WAV 与 AIFF 音效。新提醒优先使用用户音效，其次当前形象的提醒音，最后系统 Ping；声音遵守静音设置与冷却。
