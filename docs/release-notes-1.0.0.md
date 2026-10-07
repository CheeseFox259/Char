# Char 1.0.0

首个稳定版本：本地 Agent 注意力桌宠、图标气泡与 Ctrl+B 回城。

## 同版本资源更新（2026-10-07）

菲比示例替换为用户已确认正常的新版美术，形象包升为 v2 并增加点击与新提醒音效（55% 音量、4 秒冷却）。音效来自 [Genius-Society/phoebe_chubby](https://github.com/Genius-Society/phoebe_chubby)，原样提供 MP3，保留 CC BY-NC-SA 4.0 来源与许可说明。App、DMG、示例 ZIP 和校验和同时重新打包，版本号仍为 1.0.0；新增形象音效格式 MP3、AAC、CAF、FLAC 及 WAV/AIFF 别名，沿用系统解码与导入时的大小/时长检查；重新构建通用应用，源代码标签不移动，本次更新的实际源码见 main 后续提交及下方来源链接。本次按用户要求未执行新的测试。新提醒优先使用用户音效，其次当前形象的 notification，最后系统 Ping。已有菲比私有副本需删除后重新导入才能获得音效；仅点击音绑定不会改变提醒音。

- 支持 Claude Code、Codex CLI/Desktop、Kimi CLI/App、DeepSeek Harness Desktop 与 pi；提供 MiniMax CLI/Desktop 能力插件示例。
- 插件支持不重启导入、启停、同 ID 更新与所属集成卸载；新增客户端无需修改 Char 源码。
- 桌面和四边放置、焦点跨屏跟随、弹性动效、眼睛跟随、悬停律动、折叠轮换与点击破碎；支持减少动态效果。
- 自定义形象支持动作、独立边缘姿态、主题、跟随层、气泡皮肤、音效与受限事件脚本；附可导入的菲比示例与源码。
- 设置中英切换、状态栏入口、原生 CPU/RSS 性能面板；性能数据有明确归属与测量范围。
- 宿主只在变化时刷新界面；形象缓存设预算并释放旧形象；日志分批续读并保持完整积压的提醒语义。
- 内置集成优化：pi/DeepSeek 直接写入白名单元数据，不再每事件启动子进程；共享 Hook 读取和 Kimi 解码、Claude/Codex 日期解析减少重复工作，维护 EOF 排空。已有 pi/DeepSeek 会话需通过维护菜单更新后重载。
- MiniMax 原生常驻入口约 9.6 MiB RSS/端，按需调用维护 helper；客户端 Hook 不随本次常驻优化重装。
- 整理公开文档与三份开发指令，保留实现、契约、性能、安装及用户验收资料。

## 下载

图标同步备份加入可执行文件标识，防止同版本更新后同步形象图标时恢复旧宿主。

- `Char-1.0.0-macos-universal.dmg`：拖入应用程序安装。
- `Char-1.0.0-macos-universal.zip`：应用压缩包。
- `Char-1.0.0-examples.zip`：两个 MiniMax 插件与菲比形象。
- `SHA256SUMS`：附件校验和。

macOS 13+，Apple Silicon / Intel。当前为 ad hoc 签名，未经过 Apple 公证，首次打开可能需要 Finder 右键“打开”或系统隐私与安全性中的“仍要打开”。

精准导航受各客户端接口限制；普通跳转/回城仅保证激活应用。Space 整屏动画由 macOS 控制。第三方集成运行于当前用户权限；形象脚本仅开放 Char 事件和动作。
