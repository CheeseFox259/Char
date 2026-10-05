# v0.1.0 验证记录

日期：2026-10-05。实现问题：[GitHub #16](https://github.com/CheeseFox259/Char/issues/16)。代码验证固定点：5307789，发布 tag 还包含使用和验证文档。

## 已验证

| 范围 | 方法与结果 |
| --- | --- |
| 登录启动修复 | 原 notFound 检查失败；修复后平台检查通过。实际从 `~/Applications/Char.app` 启动，设置显示 Enabled → Disabled → Enabled，无旧报错。 |
| 真实跨屏 | 正常观察模式、AX 未授权；用户点击另一屏幕应用再返回，确认“跟随”。几何检查涵盖 AX 缺失、AX 优先、其他进程排除、空窗口/覆盖层排除、屏幕间隙与最大相交面积。 |
| 左键清除 | 实际界面 Claude 聚合计数 2→1→气泡消失；首次来源继续保留。Core 验证成功应用级和精确访问清除点击项，失败可重试。 |
| 破碎动画 | 原生烟测验证短暂碎片存在并清理、Reduce Motion 仅淡出；隔离演示用户确认“可见，效果可以”。隔离演示没有激活真实 Agent。 |
| 中英设置 | English→中文立即更新窗口、控制、状态和图例；界面截图确认说明段落移除、插件符号一致。设置检查验证旧字段解码、默认语言和选项持久化；最终安装包重启后仍为中文，实际登录状态仍为已启用。 |
| 登录错误双语 | Spec 审查发现原始错误文案未本地化；类型化错误修复和启动路径补齐后，平台检查通过，定向再审查无剩余发现。底层 OS 诊断保留原文。 |
| 项目契约 | 最终源码运行 `scripts/check.sh` 通过，含 Core、Observations、Platform、Hook、VS Code、pi、Kimi 和 DeepSeek 集成检查。第一次增量构建出现旧 Settings 初始化符号缓存；清理 SwiftPM 构建缓存后全量检查通过，没有修改检查以绕过失败。 |
| 发布构建 | `scripts/package-release.sh` 通过；Char 与 char-hook 均为 arm64 + x86_64。Mach-O 两个切片最低系统均为13.0。 |
| 原生渲染回归 | 最终包 `--smoke`、`--smoke --space-motion-check`、`--smoke --orbit-path-check` 通过；保留已接受的滚轮策略、Space 不重播和非线性路径。 |
| 发布容器 | ZIP 解压、DMG 校验/只读挂载，应用树与构建包逐项一致；Applications 链接正确；严格 ad hoc 签名和 SHA256 校验通过。 |
| 审查 | Standards 无可操作发现；Spec 的一项 P2 已修复并复查。 |

## 未运行

- 真正注销再登录：本次仅验证 ServiceManagement 的实际启停状态，不打断用户工作。
- Intel 实机运行、最低 macOS 13 实机：完成交叉编译与包结构检查。
- 下载隔离后的 Gatekeeper 首次安装：包未 Developer ID 签名或公证，安装说明如实记录此限制。
- 完整 VoiceOver、所有自定义外观的破碎美术验收及新的 CPU/GPU/WindowServer 基准。减少动态效果的淡出契约检查不等于完整系统偏好体验验收。

## 阻塞与不适用

没有阻塞本次声明范围的发布问题。没有可用 Developer ID 证书，因此公证不在本次产物范围；不得将 ad hoc 验证写成公证通过。Windows 发布不适用，评估仍见 [Windows 可行性](windows-feasibility.md)。准确 Warp pane、Codex 聊天、微信会话仍按已有 issue 单独跟踪，左键清除不宣称准确定位。

发布位置：[GitHub v0.1.0](https://github.com/CheeseFox259/Char/releases/tag/v0.1.0)。源码和 tag、三个附件及其 SHA256 在发布后逐项比对。日常实例恢复到固定安装路径与用户真实配置，隔离演示退出。
