# 新工作端与回城验收（2026-10-04）

本报告仅记录此次新增需求的实际证据。原完整验收仍见 `acceptance-2026-10-03.md` 和下一阶段计划；缺少信号或未运行环境项不转成通过。

## 已观察

- 工作端扩展为七类：Claude Code、Codex CLI、Codex Desktop、DeepSeek Harness Desktop、Kimi CLI、Kimi Code App、pi。Kimi 两种界面由用户明确要求同时支持。
- CUA 检查 native-navigation-probe worktree 的实际 release 包：七类按钮都出现在面板，两行排列，未裁切。pi 点击后出现应用级降级标记与最初来源徽标；这只证明模拟导航路径。
- 实际设置窗口提供“回城”状态和重试入口，首次 Hold 显示“Ctrl+B 已注册”。初次自动化和实体按键未观察到状态变化。调整 Carbon 的注册与处理目标为 Event Dispatcher 后，用户实体按 Ctrl+B，来源图标消失；临时诊断同时收到真实 Carbon 回调并确认 Hold 结束。自动化按键仍不能送达，不能由注册成功或 mock dispatch 代替实体证据。诊断代码已移除。
- 交互式 `--demo` 的导航是模拟的，气泡不激活真实 Agent 应用。用户反馈“不跳转”发生在该模式，仍须使用正常运行路径核对真实目的地。
- 原生 Carbon 派发契约在旧实现上已通过，覆盖真实回调和 AppKit 事件队列。它没有复现实体键盘送达失败，不能作为该问题已修复的证据。

- 根目录正常包 `2b12530` 以隔离 Foundation HOME、私有测试事件流运行，没有 `--demo`/`--smoke`。七类提醒使用注入的元数据，均观察到用户点击后的应用降级状态，仍保持未查看；这证明正常导航路径，不是七客户端的原生信号证据。
- 用户批准发起 Tabbit Automation 授权，设置由 Permission needed 变成 Authorized。清空旧 Hold、重新生成气泡后，用户确认实体 Ctrl+B 回到原 Tabbit 标签且来源图标消失；同时反馈跳回前有明显 2–3 秒卡顿。原生计时复现轮询约 886–916 ms、回城本身 1062.2 ms。批量读取每窗口标签 ID 后，存在校验中位 435.3 → 46.8 ms（五次都匹配原标签），实体回城路径 276.4 ms；用户确认“优化了很多”。只改 ID 查询方式，没有读取正文。临时计时/probe 均已移除。

## pi 原生检测证据

实现者用本机 pi 1.0.0、临时配置与 localhost 服务端运行真实 CLI。扩展通过真实 `char-hook` 记录了 running → turnEnded → closed，以及 running → failure → closed。两个真实原生会话身份不同，tmux 信息均为空，转发流不含测试正文。没有使用真实账户、用户配置或现有 Agent 会话。

pi 需要显式安装被动扩展，普通会话 JSONL 不提供最终 settled 边界。其权限审批、限流、上下文耗尽及自定义扩展子进程身份不能由当前接口可靠分类；没有用错误文字补齐这些类别。详见 `integrations/pi/README.md`。

## 工程收口

- [x] DeepSeek/Kimi 集成已合并；原生协议与来源区分、根会话及延迟事件契约已检查。实际客户端生命周期仍需独立证据。
- [x] 实体 Ctrl+B 的真实回调、Tabbit 原标签回城及卡顿修复已通过；最终源代码为 `f2b5b4b`。
- [x] 正常运行的七类气泡均观察到应用级降级状态，包括 DeepSeek、Kimi App、Warp。
- [x] 七工作端最终组合检查、打包/签名/smoke 已通过；完整 PR 双轴审查及受影响修复检查已完成，见 `review.md`。
- [ ] 当前能力、明确安装步骤和剩余环境项同步到 PR。

`scripts/check.sh`、`scripts/build-app.sh`、`codesign --verify --deep --strict --verbose=2 build/Char.app`、实际包 `--smoke` 及 `git diff --check` 在最终实现 `f2b5b4b` 通过。Smoke 的七工作端/回城导航为 fixture，不是原生客户端证明。双轴审查发现 Kimi 在 SessionStart 绑定迟到时可能提前消费 wire 事件；回归已在原实现复现，修复已合并为 `1e5ac25`，根目录实际 poller/router 11 组契约通过。

使用者已单独批准三项本地集成安装；pi、Kimi CLI/App 与 DeepSeek Desktop 配置已写入并核对原配置保留、实际幂等、0600 权限和 native 配置/YAML 校验。备份及生效步骤见 `native-integration-activation.md`。Kimi CLI 和 Kimi App 的原生启动/轮次结束已有下面的独立证据；其完整交互/关闭及 DeepSeek Desktop 实际生命周期仍待独立证据，不能用 Hook fixture 或 Cordis 手动派发替代。VS Code 单实例、微信逐步回城、多屏/Spaces/全屏、VoiceOver、睡眠/唤醒、实际听音及登录周期仍需按前阶段计划取得证据。使用者已明确批准首版按已确认信号交付；#5 后续跟踪原生类别缺口，详见 `signal-feasibility.md`。此决定不把未运行的实机检查改写为通过。

## Kimi CLI 原生检查

主代理复跑实现者隔离脚本，使用本机 CLI 2.1.1、临时 `KIMI_CODE_HOME`、临时项目/空 skills 和 localhost OpenAI SSE stub，关闭 telemetry 与 auto-title。原生进程退出 0，stub 收到一次 `/v1/chat/completions`；stderr 为空。真实 `char-hook` 记录 SessionStart / kimiCLI，主会话 wire 记录 turn.prompt → step.begin → step.end → turn.ended(completed)。

脚本要求退出时还有 SessionEnd，实际没有发出，因此脚本返回 1（SessionEnd assertion）。保留该失败边界：上述证据只证明 CLI 原生启动和轮次结束来源，不证明关闭生命周期；CLI 退出不能自动等同于可恢复持久会话关闭。未改用户配置，也未把脚本人工写入的事件当成原生来源。

## 当前运行与启用边界

最终包已正常运行，实际源根与共享 Hook 流已接入；只隔离 Char 偏好（0 秒过滤、声音及登录项关闭），未继续注入演示事件。安装后使用者反馈“功能正常”。真实私有共享流随后出现 Kimi Desktop SessionStart（两条）及 pi running → turnEnded，文件为 0600；正常 Char 的 AX 实际显示 Kimi Code Desktop / pi 的 Turn ended 气泡与应用降级。没有注入新的演示数据。此证据证明两者安装后的实际提醒，不扩大为所有客户端、所有停顿类别与关闭序列通过。DeepSeek 暂无独立原生事件记录，实际生命周期继续保留为未确认；重载由用户安排。

完成的三个 managed implementer worktree 已归档，主 checkout 与最终运行包保留。私有集成备份保留；隔离偏好目录仍被最终实例使用，未删除。
