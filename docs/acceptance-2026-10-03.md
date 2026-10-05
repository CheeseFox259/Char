# 当前完成部分的产品验收

验收日期：2026-10-03。源代码提交：`905a0124131994f1fb53d7399cddd122fe7502b9`，分支 `feat/char-v1`。环境：macOS 26.5.1（25F80）、Apple Silicon、Swift 6.3.2。本次使用 `verify-product`，覆盖当前实现、构建产物及可操作的用户路径。

结论：已检查的自动化契约、打包、基础交互和正常设置重启保留通过；使用者补充实机反馈“可以正常使用”。完整首版尚未通过验收：原生状态信号缺口仍未解决，部分返回实机路径缺少逐项证据或授权、集成条件。两次锁定是前两轮的历史中断；最新续验已恢复桌面输入并完成临时运行数据清理。本次没有修改实现、安装用户 Hook/扩展、授权新权限或变更 issue 状态。

## Verified

### 自动化与构建

- `scripts/check.sh` 返回 0：4 项设置检查、16 项注意力/返回检查、7 组观察契约、8 组平台契约和 4 项 VS Code 扩展测试通过。
- 同一命令执行真实 Python Hook 安装器的隔离检查：保留原设置、重复安装幂等、共享被动事件流、无 harness 输出及原文泄露检查通过。用户 harness 配置没有被安装器改写。
- `scripts/build-app.sh` 返回 0，重新生成 release `build/Char.app`。
- `codesign --verify --deep --strict --verbose=2 build/Char.app` 返回 0，包含 `char-hook` 的临时签名验证通过。
- `build/Char.app/Contents/MacOS/Char --smoke` 返回 0：三种工作端、已恢复项、降级保留未查看、最初锚点、单项忽略、返回、至少 44 点点击区域和静默来源图标淡出通过。导航仍是合成路径，不能据此认定原生应用切换通过。
- 开始验收时 `git status --short --branch` 无未提交修改；`git diff --check` 返回 0。

### CUA 原生界面与实际输入

使用绝对路径 `/Users/superhacker/Codefield/char/build/Char.app` 绑定应用，避免绑定其他 checkout 的同名产物。旧实例已确认为本目录的 `--demo`，本次构建后重新启动了新的演示实例。

- 三个工作端分别显示一个气泡，初始未查看数都是 2；Claude 显示提问、Codex Desktop 显示审批、Codex CLI 显示已恢复标记及运行计数。日常界面只有图形和数字。
- 单击 Claude 气泡，未查看数仍为 2，出现降级反馈和来源标记；再单击 Desktop 气泡，首次来源标记保留。
- 右键 Claude 气泡，仅当前首项被忽略：数量从 2 变为 1，原因变为轮次结束，其他工作端数量不变。
- 点击桌宠后，AX 标签从 `Return to saved source, application fallback` 变为 `Char companion, no return saved`，来源标记消失。另一次 Hold 通过右键菜单的 `End Hold` 解除；该菜单测试包含键盘确认。
- 普通状态菜单包含 Settings、Mute、禁用的 End Hold 和 Quit；Hold 时 End Hold 可用。
- Settings 可以打开、关闭和滚动至完整图例；测试实例中过滤阈值可从 0 改为 12，声音开关可关闭，菜单随后显示 Unmute。未点击登录项、授权或音频选择等禁用的演示控件。
- 拖动桌宠后仍可操作，演示实例写入了对应显示器的 `positions.json`。这证明当前拖动路径，不能替代多屏位置恢复验收。

以上操作检查了实际面板与输入，但来源、导航及声音在演示模式中仍为合成行为。没有把视觉检查算作用户对图形含义的理解测试。

### 正常应用入口与部分原生往返

启动前确认正常 Char 的 `settings.json` 和 `harness-hooks.jsonl` 均不存在。本次暂时创建设置：过滤 10 秒、宽限 300 秒、声音关闭、自启动关闭。通过本次打包的 `char-hook` 输入测试 JSON，未安装 Hook，未改写 Claude/Codex 配置。

- 在启动正常应用前写入一个历史测试事件；启动后只有桌宠，没有回放该事件的气泡。
- 正常应用启动后，通过 `char-hook` 写入 Claude 提问、Codex CLI 提问、Codex Desktop 审批。Codex 身份来自临时的本机根会话 metadata。三个 Hook 调用均返回 0，stdout/stderr 为空。
- 阈值前观察时没有新气泡；后续观察出现三个工作端，各 1 条未查看项。没有持续采样精确出现时刻，因此本次不宣称已证明“停顿到气泡在 10 秒内”的时间上限。
- 将已安装的 `/Applications/WeChat.app` 作为来源，点击正常 Char 的 Claude 气泡。真实平台层验证 Warp 成为前台后返回 fallback；气泡保留 1 条未查看，桌宠显示真实微信图标和应用级降级标记，形成 Hold。
- 接着尝试 Desktop 气泡时，CUA 返回“Mac is locked and automatic unlock could not unlock it”。未把这次尝试算作 Codex 激活成功，也未尝试替代 UI 控制路线。

这证明正常 Hook→观察器→气泡→Warp 应用激活与微信来源捕获的路径，事件输入仍为测试数据；不能据此宣称真实 Claude/Codex 生命周期或微信返回已经验收。

### 手动解锁后的续验

使用者报告已解锁后，重新建立临时正常实例，设置为过滤 0 秒、宽限 300 秒、声音和自启动关闭，重新通过打包的 `char-hook` 输入三种工作端的测试事件。沿用此前有效的构建与契约证据，没有因未改变实现而重复整套自动化检查。

- 点击 Claude 气泡后得到 Warp 应用级 fallback，1 条未查看保持不变。
- 点击 Codex Desktop 气泡后得到 Codex 应用级 fallback，1 条未查看保持不变；真实平台层只在目标应用已成为前台时返回该结果。因此补齐了正常应用的 Codex 激活路径，未验证精准聊天。
- 本轮将微信窗口 Raise 后没有建立 Hold；窗口抬高不等同于应用获得前台。没有把这次来源尝试算作已捕获微信。
- 为建立明确的微信前台来源，使用 Finder 的 Go to Folder 选中 `/Applications/WeChat.app`，再通过其公开 `open` 动作正常打开已安装应用。该动作返回 Mac 锁定、自动解锁失败，微信返回及设置重启测试再次中断。未尝试通过其他 UI 控制路线绕过锁定。
- 已请求使用者再次手动解锁并保持屏幕唤醒。停止本次启动的测试实例，删除临时设置和 3 条测试事件，恢复到开始续验时两份文件都不存在的状态。
- 解锁后的正常实例仍出现 AppIntents `com.apple.linkd.autoShortcut` 4097 和 libxpc assertion 日志；进程保持存活，Codex 激活没有表现失败。尚不能确定这些日志的原因或是否会影响其他路径。

### 文档与清理

- `gh issue view 1 --repo CheeseFox259/Char --json title,url,body,labels,state` 确认父规格开放并标为 `needs-info`。正文包含完整本地规格，额外附有分诊记录，没有本地/远端规格漂移。
- 检查了术语表、6 份 ADR、技能配置与当前降级范围。精准 Warp pane、Codex 聊天和微信聊天已延期，并未用降级结果冒充精准结果。
- 锁定后只停止本次启动的正常测试进程。删除本次创建的设置与 4 条测试事件，确认恢复到两份文件均不存在的初始状态；未停止用户的 Warp、Codex 或微信，未清理既有会话数据。

### 再次继续后的正常设置验收

使用者再次要求继续后，确认 Finder 可以接收键盘输入并打开 Applications。重新建立临时正常 Char 实例，自启动和声音初始关闭，使用原有验收 Hook 输入准备三个气泡。

- 通过正常 Settings 将过滤阈值改为 7 秒、Hold 宽限期改为 19 秒。
- 生成一个临时 100 毫秒单声道 WAV，使用真实 Choose Audio 文件选择器选中它；界面显示 `acceptance.wav`，没有出现加载失败提示。随后将声音开关改为开启。
- 通过桌宠 Quit 菜单正常退出，进程返回 0。读取实际 `settings.json`，确认阈值 7、宽限 19、声音开启、自启动关闭和所选 WAV 路径全部保存。
- 重新启动同一个正常包。启动时只有桌宠、没有旧测试气泡或 Hold；打开 Settings 后，实际界面恢复 7、19、声音开启和 `acceptance.wav`。设置的退出/重启路径通过，不再仅依赖存储契约检查。
- 测试后在界面中恢复本轮临时偏好：过滤 0、宽限 300、声音关闭、System Ping。准备了新气泡，暂留正常实例供手动微信来源检查；后续反馈和清理结果见下一节。
- Settings 显示 Accessibility 已授权，Tabbit Automation 为 `Permission needed for exact tab return`，ServiceManagement 未注册。没有点击任何授权或登录项启用按钮。
- 对微信窗口的实际坐标输入返回 `noWindowsAvailable`。可读取微信的窗口/菜单状态，但当前自动操作没有得到可靠的前台来源及 Hold 证据；没有把这些尝试算作微信返回失败或成功。已请求使用者在微信前台手动点击一次 Char 气泡、暂不点击桌宠，再继续检查返回。
- 检查发现用户已有 VS Code 进程运行。准备了独立的临时编辑器文件与 profile，但尚未启动扩展宿主；若再启动另一个实例，生产平台的唯一运行实例检查会拒绝准确来源，因此本轮没有冒充完整 VS Code 返回已验收，也没有关闭用户的编辑器。

本轮未验证所选音频是否实际被扬声器播放。正常退出时 stderr 有 IMK mach port 和 CapsLock/TSM 系统消息；进程仍正常返回 0，不能将日志记为完全干净。

### 使用者反馈与最终收尾

- 在请求使用者从微信前台手动点击气泡后，使用者回复“可以正常使用”。记录为手动使用反馈；回复没有逐项描述来源捕获、连续访问与返回操作，不能据此把每条路径都标为通过。
- 随后读取实际 Char 界面：桌宠为 `Char companion, no return saved`；三个气泡均显示 application fallback，Claude 和 CLI 各 1 条未查看、Desktop 2 条未查看。当前无 Hold，不能由此推断先前是否完成过返回。
- 通过本轮实例的 Quit Char 菜单退出，CUA 确认 `App quit`，对应终端会话结束。
- 退出后确认设置仍是本轮临时值，事件流只有 6 条 `char-acceptance-` 测试记录。仅删除这些设置与事件，移除本轮创建的空 Char 数据目录，恢复到开始时目录不存在的状态。没有停止用户的其他应用或改写真实会话文件。

## Not run

- 微信连续访问后返回、手动返回及来源关闭的逐项实机验收。已有来源捕获证据和使用者“可以正常使用”的总体反馈，具体返回序列没有独立记录。正常 Codex 应用级激活已在续验中补齐。
- 真实 Claude/Codex 会话的审批→响应→恢复生命周期、CLI rollout、真实睡眠/唤醒和准确前台会话识别。测试 JSON 和契约 fixture 不能替代这些路径。
- 已授权 Tabbit 原标签移动、导航、关闭、临时集成故障及恢复；隔离 VS Code Extension Development Host 中编辑器/终端的实际返回。
- 真实音频播放、登录项授权和登出/登录。正常设置退出/重启保留与本地音频选择已在最新续验中补齐。
- 多显示器位置恢复、跨 Space、全屏可见性、系统 Reduce Motion、VoiceOver 操作和用户对图形图例的理解。
- 运行时网络抓包；源代码与本地流检查不能当作抓包结果。

## Blocked

- **完整状态覆盖尚不满足规格。** Codex 的 failure/rate/context 和 Claude 的 context-exhaustion 没有可靠观察信号。没有收到停顿信号时不会产生未分类提醒。这一缺口仍由 [#5](https://github.com/CheeseFox259/Char/issues/5) 跟踪，尚无批准的首版范围缩减。
- **CUA 无法补齐微信逐项操作证据。** 前两轮曾遇到锁定，最新微信实际鼠标输入返回 `noWindowsAvailable`。使用者已反馈可以正常使用，手动检查请求已结束；自动化限制仍使具体返回序列缺少证据，并非已证实产品故障。
- **Tabbit 精准返回缺少 Automation 授权。** 当前界面明确提示需要权限；未通过新的权限授权绕过该前置条件。
- **VS Code 实机条件未就绪。** 可选集成尚未在隔离扩展宿主中运行；当前另有用户实例，Char 的唯一实例守卫会拒绝多实例准确捕获。没有关闭用户实例以取得通过结果。

## Not applicable

- 精准 Warp pane/关闭标签重接、Codex 精准聊天和微信精准聊天返回不在当前批准的首版范围，分别由 #10、#11、#12 跟踪。
- 云端/SSH 会话、跨设备同步、遥测、Agent 托管、Linux/Windows 和在桌宠中直接回复/审批不在范围。
- Developer ID 签名和公证不属于本次本机构建验收；验证通过的是临时签名。

## 其他发现

- **P3，设置排版：** 默认窗口宽度下两个时间输入框重复显示的 `Seconds` 标签断成 `Sec-onds`。数值输入可用，但排版需要修正。对应 `Sources/CharApp/SettingsView.swift` 的两处 90 点 TextField。
- **P3，指令链接：** `AGENTS.md` 的 `skills/efficient-dev/SKILL.md` 和 `skills/verify-product/SKILL.md` 两个相对链接在仓库内不存在；技能仍可通过当前会话的已安装目录读取。
- **P3，规格时态：** Testing Decisions 首条仍写“仓库尚无实现和测试”，与当前实现不符；后续规格维护应更新测试先例。
- **运行日志未完全干净：** `/usr/bin/log show --last 10m --style compact --predicate 'process == "Char" AND (messageType == error OR messageType == fault)'` 检出 AppIntents 的 `com.apple.linkd.autoShortcut` 连接错误（4097）及 libxpc assertion。测试进程当时仍存活，已经完成的 Warp 路径未表现失败；这些日志的原因尚未确定，不能记为无运行时错误。解锁后的验收应检查是否重现并与失败行为关联。

仅完成本报告记录的验收与清理，未据此关闭 issue、发布、合并或修改产品范围。
