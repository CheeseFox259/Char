## Char v0.1.1

macOS 13+，Universal（Apple Silicon / Intel）。下载 DMG，将 Char.app 拖到系统“应用程序”（`/Applications`）；或解压 ZIP 后复制到同一位置。无需本地构建。

### 本版

- 默认项目、软件图标与默认桌宠一致，使用右边缘探头形象。
- 自定义形象可包含 appIcon；运行中的应用图标、状态栏图标与设置预览同步更新。旧形象包自动派生图标，删除所选形象恢复默认。
- 包含 v0.1.0 的登录启动、跨屏跟随、左键气泡破碎和中英设置修复。
- 此版本由 GitHub Actions 执行项目检查并构建 Universal ZIP、DMG 和 SHA256SUMS。

### 验证与限制

图标导入/切换/删除恢复、旧格式兼容、非法资源验证、实际设置与 Finder 图标已验证。发布前还会下载本次附件验证校验和、签名、版本和原生图标烟测。先前完整原生烟测停在 Space-arrival 检查，不能计为本版完整烟测通过；该路径不在本次图标修改范围。

**此包为 ad hoc 签名，未 Developer ID 签名、未 Apple 公证。** 从 GitHub 下载后可能需要按 macOS“隐私与安全性”中的“仍要打开”流程首次启动。无需关闭 Gatekeeper。

Finder/Launchpad 使用签名包内默认图标；运行中的应用与状态栏图标随自定义形象变化。未执行 Intel 实机、真实注销再登录或新的性能基准。

[安装说明](https://github.com/CheeseFox259/Char/blob/v0.1.1/docs/macos-release.md) · [图标验证](https://github.com/CheeseFox259/Char/blob/v0.1.1/docs/appearance-icons-verification-2026-10-05.md) · [开发文档](https://github.com/CheeseFox259/Char/blob/v0.1.1/docs/README.md)
