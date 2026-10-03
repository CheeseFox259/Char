# 新工作端与回城验收（2026-10-04）

本报告仅记录此次新增需求的实际证据。原完整验收仍见 `acceptance-2026-10-03.md` 和下一阶段计划；缺少信号或未运行环境项不转成通过。

## 已观察

- 工作端扩展为七类：Claude Code、Codex CLI、Codex Desktop、DeepSeek Harness Desktop、Kimi CLI、Kimi Code App、pi。Kimi 两种界面由用户明确要求同时支持。
- CUA 检查 native-navigation-probe worktree 的实际 release 包：七类按钮都出现在面板，两行排列，未裁切。pi 点击后出现应用级降级标记与最初来源徽标；这只证明模拟导航路径。
- 实际设置窗口提供“回城”状态和重试入口，首次 Hold 显示“Ctrl+B 已注册”。自动化按键没有观察到状态变化；用户实体按键也反馈无变化。该项仍在排查，不能由注册成功或 mock dispatch 宣称可用。
- 交互式 `--demo` 的导航是模拟的，气泡不激活真实 Agent 应用。用户反馈“不跳转”发生在该模式，仍须使用正常运行路径核对真实目的地。
- 原生 Carbon 派发契约在旧实现上已通过，覆盖真实回调和 AppKit 事件队列。它没有复现实体键盘送达失败，不能作为该问题已修复的证据。

## pi 原生检测证据

实现者用本机 pi 1.0.0、临时配置与 localhost 服务端运行真实 CLI。扩展通过真实 `char-hook` 记录了 running → turnEnded → closed，以及 running → failure → closed。两个真实原生会话身份不同，tmux 信息均为空，转发流不含测试正文。没有使用真实账户、用户配置或现有 Agent 会话。

pi 需要显式安装被动扩展，普通会话 JSONL 不提供最终 settled 边界。其权限审批、限流、上下文耗尽及自定义扩展子进程身份不能由当前接口可靠分类；没有用错误文字补齐这些类别。详见 `integrations/pi/README.md`。

## 仍待本轮收口

- [ ] DeepSeek/Kimi 集成合并、根会话与延迟事件契约及对应原生来源证据。
- [ ] 实体 Ctrl+B 回城问题定位和受影响路径重验。
- [ ] 正常运行的 DeepSeek、Kimi App、Warp 应用级激活。
- [ ] 七工作端最终组合检查、打包/签名/smoke 与双轴审查。
- [ ] 当前能力、明确安装步骤和剩余环境项同步到 PR。

用户真实配置中的可选 Hook/扩展尚未由本轮自动安装。Tabbit Automation、VS Code 单实例、微信逐步回城、多屏/Spaces/全屏、VoiceOver、睡眠/唤醒、实际听音及登录周期仍需按前阶段计划取得证据。#5 原必需类别缺口继续保留，详见 `signal-feasibility.md`。
