# pi 监控失败与终端残留修复

日期：2026-10-06。使用者报告 Warp 直接运行和 Warp + tmux 都没有 pi 提醒，并在 TUI 与退出后的终端看见 `Char: Pi observation could not append a local event.`。

## 原因与复现

已安装 `~/.pi/agent/extensions/char/index.js` 中的 `hookBinary` 仍指向早期本地 `build/Char.app/Contents/MacOS/char-hook`。该文件已不存在，正式 Release 的 `/Applications/Char.app/Contents/MacOS/char-hook` 则可执行。原事件文件存在且可写。

将已安装 observer 和原 hook 配置用于临时事件目录，派发 `agent_start → message_end(stop) → agent_settled`，稳定复现同一警告，断言因没有轮次结束事件而失败。独立调用正式 Release hook 成功写出规范事件，没有终端输出。临时 fixture 没有写入真实观察流，没有读取或保存会话正文。

两种终端运行方式使用同一份坏配置。旧扩展在 `execFile` 失败后直接写 `process.stderr`，绕过 pi 对终端的渲染管理；报错是扩展输出，未进入输入框或发送给模型。

## 修复

- 本机 Char pi 扩展已备份为私有 ZIP，存于忽略目录 `build/pi-diagnosis/backups/`，随后重装。当前路径固定为 `/Applications/Char.app/Contents/MacOS/char-hook`；事件目的地保持不变。没有改动其他 pi 扩展、用户会话、Char app 或其他客户端配置。
- 错误改为交互模式下最多一次 `ctx.ui.notify(..., 'warning')`。不直接写 stdout/stderr；print 模式与关闭事件不弹警告，避免退出/重载时再留下文字。
- 安装指南补充 Release 稳定路径、旧安装修复与 `/reload`。扩展是 app 外部的独立配置；替换 Char.app 不会自动迁移这份配置。
- 不新增计时器、目录轮询或模型请求；成功事件路径及其元数据白名单保持不变。

## 已验证

1. 缺失 executable 的回归检查先失败：捕获到直接终端输出；修复后通过。覆盖一个交互通知、重复失败、无 UI 模式、仅关闭时失败及不伪造事件。
2. `CHAR_PI_PACKAGE=/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent node integrations/pi/observer.test.mjs`：本机 pi 1.0.3 的真实 loader/runner 及元数据测试通过。
3. `node integrations/pi/native-cli.test.mjs /opt/homebrew/bin/pi /Applications/Char.app/Contents/MacOS/char-hook`：真实 pi CLI、正式 Release hook、仅 localhost 服务四次运行通过。直接与 tmux 元数据各覆盖成功/失败；验证原生会话身份、running/stopped/closed 和正文不落盘。tmux 测试使用 `TMUX_PANE` fixture，不宣称操作过真实 tmux 窗口。
4. 重装后重新运行最初的已安装扩展复现：临时流成功出现 `turnEnded`，无原警告。
5. `bash scripts/check.sh` 和 `git diff --check` 通过。

## 实际使用确认与边界

已请求使用者在每个运行中的 pi 执行 `/reload` 或重启，并在自然结束一轮时分别确认气泡及终端残留。现有会话已载入的旧 JavaScript 不会因磁盘文件替换自动更新；本记录尚不声称用户的两个 Warp 场景已验收。

没有替使用者发起真实模型请求、退出工作会话、操作其终端，或修改应用权限。Char app 源码与签名包未改动，本次直接复用安装的 v0.1.2 hook；未重建、安装或发布新的 app。
