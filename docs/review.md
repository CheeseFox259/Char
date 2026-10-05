# Whole-branch review

Reviewed `f5960d4` against `origin/main` (`f5d7d46`). Commands: `git diff origin/main...HEAD` and `git log origin/main..HEAD --oneline`. Standards and Spec were reviewed by separate agents; review was read-only. Fixes were implemented on one branch and merged as `b5a79a7`.

## Standards

No actionable findings. No breaches of AGENTS.md, domain-document rules or settled ADR decisions were found. The implementation preserves domain language, local processing, native-session ownership, the first return anchor and the approved application fallback behavior. No heuristic smell justified a required change.

## Spec

1. **P1 — Missing stop categories.** The spec requests question, approval, turn end, failure, rate limit and context exhaustion. Codex failure/rate/context and Claude context exhaustion currently have no reliable observation path. The capability matrix labels them unavailable; no stop is guessed from text or inactivity. **Open:** the explicit first-release scope question is pending.
2. **P2 — Failed return discarded a valid source.** The spec ends Hold after accurate return, or approved WeChat activation. `completeReturn` previously ended it for unavailable or failed exact returns. **Fixed:** unavailable returns and Tabbit/VS Code fallback preserve the original anchor for retry; exact success and degraded WeChat activation finish Hold. Core acceptance checks cover retry behavior.
3. **P3 — Missing expiry fade.** The spec says the source icon fades quickly and quietly on grace expiry. Previously it disappeared immediately. **Fixed:** the graphical badge fades over 180 ms after actual Hold clears; actions remain available and no sound is emitted. Packaged smoke checks partial/completed fade and click availability.

Standards: 0 findings. Spec: 3 findings, 2 fixed and 1 open; the remaining issue is native signal coverage. Fixture checks do not establish native navigation, audio, login or desktop acceptance. See [verification](verification.md).

## Issue / PR follow-up, 2026-10-03

Reviewed PR #2's current local head `5d33027` against its base `f5d7d46`; the remote head matched the local checkout. Two independent read-only review agents checked Standards and Spec.

- **Standards:** no documented-rule breaches or justified heuristic refactors. A concrete P2 observation bug was found: an older delayed stop changed the poller's dedup state even though the router rejected its timestamp, causing the next valid stop to be discarded. **Fixed:** keep a per-session event timestamp watermark, including duplicate states. The poller/router regression failed with `a delayed old stop suppressed the new attention item` before the fix and passes after it.
- **Spec:** a P2 Hold bug was found: a transient Tabbit query failure or VS Code bridge timeout was treated as confirmed source closure. **Fixed:** source validity is true / false / unknown; only confirmed invalidity clears Hold. Unknown validity refuses return without discarding the source. The platform regression failed with `Temporary Tabbit query failure invalidated a live source` before the fix and checks query recovery for both integrations.
- **Still open:** P1 native signal coverage (Codex failure/rate/context and Claude context exhaustion). No approved scope reduction is recorded. Issues #1 and #5 remain open for that decision or a supported observation implementation.
- **Issue closure:** #6 has deterministic acceptance evidence; #7 has implementation/platform contracts with live paths assigned to #9. They may close when PR #2 merges. #4, #8 and #9 remain open for their actual login/settings/input/desktop acceptance. #10–12 remain deferred exact-navigation work.

PR #2 remains a draft. Its closing references cover #6 and #7 only; implementation, controlled checks and remaining release acceptance are stated separately.

## 扩展工作端双轴审查，2026-10-04

固定比较点：PR base `f5d7d46` → `2b12530`，Standards / Spec 两个只读审查代理分别检查整条 PR 分支。

- **Standards：** 没有项目规则硬性违规。P3：Kimi wire 与 Hook 三处重复构造工作端身份和目标；单一修复代理复用现有 `makeEvent`，增加可选原生时间参数，已在 `1e5ac25` 合并。
- **Spec：** P2：未取得 SessionStart 绑定时先读取 wire，游标前移导致新停顿永久丢失；绑定收取时间晚于原生事件时也会丢弃它。回归在旧实现报 `fresh Kimi wire stop was lost before late binding`。修复保留未绑定新字节、保持实际启动 EOF 基线，使用已知 SessionEnd 作为关闭代际边界，跨 CLI/Desktop 重新绑定不重放旧记录。实际 poller → router 的新文件、启动时未绑定文件、较早原生时间、子会话、旧事件、重新绑定及复制历史文件回归通过。根目录 `swift run char-observation-checks`：11 contract checks passed。
- **仍开放：** P1 #5 原必需信号缺口，没有得到检测范围缩减批准；实际客户端和桌面验收边界见本轮报告。

修复代理完成上述代码后，合并代理和后续代理均遇到账户用量限制；主代理接手合并与受影响差异检查。Tabbit 用户复测暴露的 2–3 秒卡顿另行测量，尚未以注册成功或回城一次成功视作收口。

### 收口补充

`f2b5b4b` 的 Tabbit 改动只批量读取每窗口的 opaque tab IDs，再在本地比较；保留仍存活来源校验、准确焦点复核与失败重试规则。实际只读原生五次查询全部匹配；中位校验耗时 435.3 → 46.8 ms，用户实体 Ctrl+B 回城计时 1062.2 → 276.4 ms，并确认改善。主代理检查该受影响差异，组合检查、最终签名和包 smoke 通过。临时诊断全部移除；没有用 mock 计时宣称性能修复。

2026-10-04 使用者明确批准按已确认信号交付，将缺失类别另行跟踪。当前 Spec/矩阵已同步；#5 不再是批准后首版实现的范围阻塞，仍是开放的后续能力事项。原生客户端与桌面环境未运行项继续保留。
