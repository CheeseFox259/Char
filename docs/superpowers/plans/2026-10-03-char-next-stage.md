# Char 下一阶段实施与验收计划

> **For agentic workers:** 本轮仅交付计划。实施时沿用已确定的 implement-spec 工作流，按依赖推进；本文不授权安装用户 Hook/扩展、授予权限、关闭用户应用、修改产品范围或发布。下列复选框记录未来执行结果。

**Goal:** 解决原生检测覆盖的首版决策，补齐当前承诺能力的实机证据，使 PR 与产品验收分别具备明确的完成标准。

**Architecture:** 保持本机旁路观察器、统一注意力流程及已批准的应用级图形降级。先证明原生信号，再决定适配器改动；实机验收使用当前正常应用，演示和测试 JSON 只证明对应测试路径。

**Tech Stack:** Swift 6.3.2、SwiftPM、AppKit/SwiftUI、官方可选 Hook、macOS Automation/Accessibility/ServiceManagement、可选 VS Code 扩展。

---

## 基线和顺序

基线提交 `905a0124131994f1fb53d7399cddd122fe7502b9`。依据：`docs/acceptance-2026-10-03.md` 为最新报告，`docs/verification.md` 保留历史证据。

已通过：自动化契约、打包/临时签名、实际面板输入、正常 Warp/Codex 应用激活、设置退出/重启保留及本地音频选择。保留这些证据；未改变相关实现时不重复整轮验收。

未完成不等同于失败：微信具体返回序列缺少证据；Tabbit 缺授权；VS Code 缺单实例集成条件。历史锁屏已经恢复，不能继续当作当前总阻塞。

任务依赖：

```text
任务 0 文档与 P3 修正 ────────────────────────┐
任务 1 原生信号查证 → 覆盖/范围决策 → 任务 2 生命周期验收 ┤
任务 3 返回实机验收 ─────────────────────────┤ → 任务 6 收口
任务 4 桌面/声音/登录验收 ────────────────────┤
任务 5 日志归因 ────────────────────────────┘
```

任务 1 是最高优先级。其他任务可独立推进，但不能替代信号覆盖门槛。#10、#11、#12 的精准 Warp/Codex/微信能力继续延期。

## 文件职责

| 文件 | 下一阶段用途 |
| --- | --- |
| `docs/verification.md` | 维护当前状态索引，标明已被续验替代的历史项 |
| `docs/acceptance-2026-10-03.md` | 保留本次验收事实，不改写成未来通过结果 |
| `docs/signal-feasibility.md` | 新建：每个缺失类别的原生来源、版本、会话身份、恢复信号及可行性结论 |
| `docs/acceptance-native-lifecycle.md` | 新建：真实三工作端生命周期、阈值及睡眠/唤醒证据 |
| `docs/acceptance-return-desktop.md` | 新建：返回序列、环境/权限、声音/登录和桌面验收结果 |
| `docs/runtime-log-investigation.md` | 新建：日志复现条件、影响与归因结论 |
| `Sources/CharObservations/ObservationClassifier.swift`、`LocalObservationPoller.swift` | 仅在任务 1 证明可用来源后修改观察逻辑 |
| `Sources/CharHook/main.swift`、`integrations/claude/install.py`、`integrations/codex/install.py` | 仅在官方 Hook 结构/生命周期证据要求变更时修改 |
| `Tests/CharObservationChecks/Checks.swift` | 从真实脱敏输入建立观察契约及行为回归 |
| `Sources/CharApp/SettingsView.swift` | 修复两个时间输入的重复标签折行 |
| `AGENTS.md`、`docs/spec.md` | 修复技能引用及测试现状描述；范围修改必须单独经过决定 |

## 任务 0：清理已确认的 P3 和报告时态

**优先级：P3，独立小改动。**

- [ ] 在 `docs/verification.md` 的当前状态中将正常 Warp/Codex 激活、界面输入、设置重启保留和音频选择列为已通过；保留锁屏历史，去掉当前“等待解锁”的误导。
- [ ] 将 `docs/spec.md` 的 Testing Decisions 首条更新为当前已有高层验收接缝、可执行 Swift 契约、Hook 安装器检查与原生应用 smoke；保留测试原则和检测要求。
- [ ] 修复 `AGENTS.md` 两个不存在的相对技能链接，改为从会话技能目录解析已安装的 `efficient-dev`、`verify-product`；保留原路由规则。执行该修改时使用 writing-for-agents。
- [ ] 将 `SettingsView.swift` 的两处时间行改为下列内容；外侧标签已含单位，输入框隐藏重复标签，辅助功能名称仍保留单位。

```swift
HStack {
    Text("Filter threshold (seconds)")
    Spacer()
    TextField("Seconds", value: $runtime.settings.filterSeconds, format: .number)
        .labelsHidden()
        .accessibilityLabel("Filter threshold in seconds")
        .frame(width: 90).onSubmit { runtime.saveSettings() }
}
HStack {
    Text("Hold grace (seconds)")
    Spacer()
    TextField("Seconds", value: $runtime.settings.graceSeconds, format: .number)
        .labelsHidden()
        .accessibilityLabel("Hold grace in seconds")
        .frame(width: 90).onSubmit { runtime.saveSettings() }
}
```

- [ ] 执行 `swift build`，预期返回 0；在实际设置窗口的默认宽度检查不再出现 `Sec-onds`，数值仍可输入。不为这一排版改动新增镜像单元测试。
- [ ] 执行 `git diff --check`，仅提交本任务修改，不包含用户尚未提交的验收报告。

**完成标准：** 三个 P3 问题修复；当前状态与最新续验一致，历史事实仍可追溯。

## 任务 1：证明缺失原生信号并作首版决策

**优先级：P1，首版主门槛；沿用 #5。**

缺口：Codex CLI/Desktop 的 failure、rate limit、context exhaustion，以及 Claude Code 的 context exhaustion。

- [ ] 记录 `claude --version`、`codex --version`、Codex Desktop 版本及对应官方事件/Hook 文档版本。
- [ ] 逐项核对支持的本机记录、官方 Hook 或可接入的本地事件接口。每个候选必须同时证明停顿、根会话身份、CLI/Desktop 区分及恢复；不从回答文字或空闲时长推断。
- [ ] 在 `docs/signal-feasibility.md` 为每个类别记录：实际来源、脱敏结构、触发/恢复顺序、是否能旁路读取、运行时证据、不可用原因。测试 JSON 与真实事件分列。
- [ ] 对可用来源，先用采集到的脱敏输入在 `Tests/CharObservationChecks/Checks.swift` 建立会失败的行为回归，运行 `swift run char-observation-checks` 确认暴露缺口；再实现最小映射并复跑。不预设尚未证明存在的事件名或接口。
- [ ] 对找不到可靠来源的类别，给出查证结论并停止该类别的适配器扩展。不得为了制造限流/耗尽而执行没有预算约束的长循环。
- [ ] 根据证据提交首版选择：继续完整检测要求，或由使用者明确批准首版只覆盖已确认信号、剩余类别另行跟踪。批准前保持完整要求和开放阻塞；此前应用级跳转批准不等于检测范围批准。
- [ ] 若范围获批准，再同步 `docs/spec.md`、`docs/observation-integration.md`、相关 Issue/PR 的能力说明。若没有批准或仍有未实现的必需信号，不宣称完整首版验收通过。

**完成标准：** 每个缺口都有可行来源与回归，或明确不可行证据及经批准的范围决定。只有确认停顿但原因未知时才能使用 unclassified；缺少停顿信号不能当作 unclassified。

## 任务 2：真实三工作端生命周期与时间验收

**依赖：任务 1 的能力边界明确；只测试已确认的来源。**

- [ ] 在隔离配置/一次性会话中准备官方 Hook。写入用户配置、Hook 信任审核需要使用者明确授权；未授权则保持该路径未运行。
- [ ] 对 Claude Code、Codex CLI、Codex Desktop 各记录真实“提问→回答→继续→轮次结束”和“审批→响应→继续”序列。核对恢复发生时机，避免把已经执行的工具继续误报为待审批。
- [ ] 各覆盖一个早于 Char 启动的根会话和一个之后创建的根会话：旧等待不回放，之后的新停顿能提醒，子会话不独立提醒。
- [ ] 记录实际事件时间和气泡首次出现时间，验证过滤阈值；分别检查阈值前恢复不提醒、阈值后恢复保留已过去项。先定义采样间隔和允许的观察误差，不把稀疏观察写成精确时间上限。
- [ ] 真实睡眠/唤醒一次，检查仍有效的新停顿与睡眠期间已恢复的停顿；整批最终状态先于提醒时钟生效。
- [ ] 核对应用级激活始终不自动清除提醒；缺少准确会话焦点证据时，不据应用前台状态认定已查看。
- [ ] 将逐项结果写入 `docs/acceptance-native-lifecycle.md`，发现实际误报/漏报时从该输入建立回归，再修复并重跑受影响路径。

**完成标准：** 当前宣称支持的生命周期有真实会话证据，测试输入与实际 harness 行为清楚分开。

## 任务 3：补齐返回路径证据

- [ ] **微信：** 由使用者确认微信真正处于前台；记录微信→Claude→Desktop→桌宠返回，核对最初应用图标不变、同一 PID 被激活、fallback、未查看项保留及 Hold 结束。另测手动回微信；来源退出由使用者操作，核对旧实例失效。
- [ ] 微信的 `noWindowsAvailable` 若再次阻碍 CUA，改由使用者执行明确序列，记录每一步 Char 状态与前台应用身份。总体“可以使用”的反馈不替代逐项结果；不读取聊天原文。
- [ ] **Tabbit：** 使用者批准 Automation 后，用一次性标签检查跨窗口移动、同标签导航、桌宠返回、手动返回、标签关闭、查询暂时失败与恢复重试；无权限时确认不建立 Hold。
- [ ] **VS Code：** 在使用者可安排的单实例窗口期运行隔离 Extension Development Host，使用 `integrations/vscode` 与一次性编辑器/终端；检查返回、手动返回、关闭、桥接暂时失败后重试及歧义拒绝。
- [ ] 用户原实例仍在时，只记录多实例守卫正确拒绝准确捕获；不关闭其编辑器，不放宽守卫取得通过结果。
- [ ] 核对 Warp 来源不建立 Hold。结果记录到 `docs/acceptance-return-desktop.md`，包括 PID/锚点、权限、exact/fallback/unavailable、Hold 前后状态与证据来源。

**完成标准：** 所有首版宣称可用的来源都有正向返回、手动返回、关闭和失败恢复证据；环境未就绪项保留为阻塞，不写成产品故障或通过。

## 任务 4：桌面、声音与登录环境验收

- [ ] 多显示器：移动实际焦点窗口，核对唯一桌宠跟随、每屏位置恢复、鼠标单纯跨屏不触发、传送过程中按钮可用。
- [ ] 检查多 Space、全屏可见性，以及开启系统 Reduce Motion 后的简化动效。
- [ ] 用 VoiceOver 执行访问、忽略、设置、静音和结束 Hold；让使用者按图例识别原因、已过去、降级和来源标记，记录误解而非只检查图标存在。
- [ ] 实际听取 System Ping 和所选本地音频；核对多事件合并一次、静音不响、Hold 到期不响。音量由使用者确认，音频“选中成功”不算“播放成功”。
- [ ] 在稳定应用路径执行登录项启用/禁用、实际批准状态和一次登出/登录；由使用者安排权限及中断窗口，恢复最终偏好。
- [ ] 在正常观察/提醒/返回期间进行本机网络连接/流量审计，仅保存归因和脱敏结果，不上传抓包。结果写入 `docs/acceptance-return-desktop.md`。

**完成标准：** 桌面和声音行为有实机结果，登录偏好与系统实际状态一致，已测试的本地数据路径有运行时证据。

## 任务 5：日志归因，不以进程存活代替无影响

- [ ] 对同一构建分别记录启动、空闲、设置、Warp/Codex 激活和返回后的时间窗口。
- [ ] 使用报告已有命令收集相关日志：

```sh
/usr/bin/log show --last 10m --style compact \
  --predicate 'process == "Char" AND (messageType == error OR messageType == fault)'
```

- [ ] 核对 AppIntents 4097、libxpc assertion、IMK/TSM 消息是否可重现，并与崩溃、卡住、焦点失败或功能失败关联。
- [ ] 有用户影响时先固定复现，使用 diagnosing-bugs 排查和修复；仅系统消息且未观察到影响时，记录版本、复现条件与结论。不加权限、不抑制日志来制造“干净”结果。

**完成标准：** 每类日志得到“已修复影响 / 已知且未观察到影响 / 尚未归因”的明确状态；未归因项列入收口判断。

## 任务 6：一次收口与 PR 决策

- [ ] 更新当前验收索引，按 Verified / Not run / Blocked / Not applicable 保留证据和范围决定。
- [ ] 对实际实现变更执行一次最终组合检查：

```sh
scripts/check.sh
scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 build/Char.app
build/Char.app/Contents/MacOS/Char --smoke
git diff --check
```

预期各命令返回 0。完整组合检查留在实现收口时；其间只重跑受影响的契约或用户路径。

- [ ] 审查新增差异并修复发现；未解决的必需检测缺口继续阻止完整规格通过。
- [ ] **PR 可评审：** 检测范围明确、实现与规格一致、代码问题修复且所需检查通过；剩余环境检查明确列出。
- [ ] **产品完整验收：** 当前承诺的原生生命周期、返回与桌面/声音/登录路径均有证据，没有未批准的范围缺口。不能用 PR 可评审代替这个结论。
- [ ] 仅在对应门槛满足并有授权时推进 PR 状态、关闭 Issue 或发布；Developer ID、公证和精准导航新能力不自动纳入本阶段。

## 下一次启动建议

先执行任务 1 的信号可行性查证，交付逐类别矩阵和首版决策材料。任务 0 可同时独立完成。Tabbit 授权、VS Code 单实例窗口、登录验收窗口和微信手动序列在对应实机任务开始前安排，不把整个计划变成一次批量授权。

## 2026-10-04 执行续记

任务 0 的文档/时间标签修正已完成；任务 1 逐类别查证与首版决定已完成（使用者明确批准已确认信号交付，#5 后续跟踪）。三项新增本地原生集成已由使用者单独批准并安装；Tabbit Automation 获批准，实体回城及卡顿修复有证据。其余完整生命周期/返回异常/桌面声音登录项尚未完成，继续按本计划保留；最新证据和 PR 状态以 2026-10-04 报告为准。
