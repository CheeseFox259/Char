# 新工作端与回城验收（2026-10-04）

本报告仅记录此次新增需求的实际证据。原完整验收仍见 `acceptance-2026-10-03.md` 和下一阶段计划；缺少信号或未运行环境项不转成通过。

## 已观察

- 工作端扩展为七类：Claude Code、Codex CLI、Codex Desktop、DeepSeek Harness Desktop、Kimi CLI、Kimi Code App、pi。Kimi 两种界面由用户明确要求同时支持。
- CUA 检查 native-navigation-probe worktree 的实际 release 包：七类按钮都出现在面板，两行排列，未裁切。pi 点击后出现应用级降级标记与最初来源徽标；这只证明模拟导航路径。
- 实际设置窗口提供“回城”状态和重试入口，首次 Hold 显示“Ctrl+B 已注册”。初次自动化和实体按键未观察到状态变化。调整 Carbon 的注册与处理目标为 Event Dispatcher 后，用户实体按 Ctrl+B，来源图标消失；临时诊断同时收到真实 Carbon 回调并确认 Hold 结束。自动化按键仍不能送达，不能由注册成功或 mock dispatch 代替实体证据。诊断代码已移除。
- 交互式 `--demo` 的导航是模拟的，气泡不激活真实 Agent 应用。用户反馈“不跳转”发生在该模式，仍须使用正常运行路径核对真实目的地。
- 原生 Carbon 派发契约在旧实现上已通过，覆盖真实回调和 AppKit 事件队列。它没有复现实体键盘送达失败，不能作为该问题已修复的证据。

- 根目录正常包 `2b12530` 以隔离 Foundation HOME、私有测试事件流运行，没有 `--demo`/`--smoke`。七类提醒使用注入的元数据，均观察到用户点击后的应用降级状态，仍保持未查看；这证明正常导航路径，不是七客户端的原生信号证据。
- 用户批准发起 Tabbit Automation 授权，设置由 Permission needed 变成 Authorized。清空旧 Hold、重新生成气泡后，用户确认实体 Ctrl+B 回到原 Tabbit 标签且来源图标消失；同时反馈跳回前有明显 2–3 秒卡顿，正在定位。

## pi 原生检测证据

实现者用本机 pi 1.0.0、临时配置与 localhost 服务端运行真实 CLI。扩展通过真实 `char-hook` 记录了 running → turnEnded → closed，以及 running → failure → closed。两个真实原生会话身份不同，tmux 信息均为空，转发流不含测试正文。没有使用真实账户、用户配置或现有 Agent 会话。

pi 需要显式安装被动扩展，普通会话 JSONL 不提供最终 settled 边界。其权限审批、限流、上下文耗尽及自定义扩展子进程身份不能由当前接口可靠分类；没有用错误文字补齐这些类别。详见 `integrations/pi/README.md`。

## 仍待本轮收口

- [x] DeepSeek/Kimi 集成已合并；原生协议与来源区分、根会话及延迟事件契约已检查。实际客户端生命周期仍需独立证据。
- [ ] 实体 Ctrl+B 的真实回调与 Tabbit 原标签回城已通过；2–3 秒卡顿反馈待修复和复测。
- [x] 正常运行的七类气泡均观察到应用级降级状态，包括 DeepSeek、Kimi App、Warp。
- [ ] 七工作端最终组合检查、打包/签名/smoke 与双轴审查。
- [ ] 当前能力、明确安装步骤和剩余环境项同步到 PR。

`scripts/check.sh` 和 `scripts/build-app.sh` 在 `2b12530` 通过；最终修复后的组合检查、签名验证和 smoke 待收口。双轴审查发现 Kimi 在 SessionStart 绑定迟到时可能提前消费 wire 事件；回归已在原实现复现，修复正在验证。

用户真实配置中的可选 Hook/扩展尚未由本轮自动安装。Kimi CLI/App 与 DeepSeek Desktop 的实际客户端生命周期仍待独立证据，不能用 Hook fixture 或 Cordis 手动派发替代。VS Code 单实例、微信逐步回城、多屏/Spaces/全屏、VoiceOver、睡眠/唤醒、实际听音及登录周期仍需按前阶段计划取得证据。#5 原必需类别缺口继续保留，详见 `signal-feasibility.md`。
