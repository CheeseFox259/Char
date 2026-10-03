# 原始停顿类别缺口查证（2026-10-04）

## 版本与证据

- 本机 Claude Code `2.1.263`，Codex CLI `0.156.1`。这些版本通过各自 `--version` 读取。
- 本机另有 Codex 源码 checkout `5c5308fc9a`；它不是已安装二进制的逐字构建来源，因此作为源码证据单列。
- 此次没有制造真实限流、耗尽或真实账户 API 失败，没有把测试 JSON 写成原生故障证据。

## 逐类别结论

| 要求 | 已查来源 | 当前结论 | 恢复与身份 |
| --- | --- | --- | --- |
| Claude 上下文耗尽 | 官方 StopFailure 枚举；现有项目 JSONL | 官方 Hook 未提供独立上下文耗尽码。`max_output_tokens` 代表输出上限，不能等同上下文耗尽；`invalid_request` 也不是上下文耗尽专用码。保留缺口。 | 现有 UserPromptSubmit/工具继续及 transcript 提交提供 running；不能由恢复信号反推之前发生了耗尽。 |
| Codex CLI/Desktop failure | 持久化 rollout 策略；官方 Hook | `EventMsg::Error` 是不持久化事件；现有 Hook 无独立失败回调。保留缺口。 | 必须先匹配本机根会话 session_meta 再区分 CLI/Desktop；现有 turn start 可清除停顿。 |
| Codex CLI/Desktop rate limit | 同上 | 不能从一般停止、任意错误文字或 token 计数推断限流。保留缺口。 | 无可靠停顿来源时不产生注意力项。 |
| Codex CLI/Desktop context exhaustion | 同上 | 协议内存在结构化错误不代表运行中的原生客户端把它提供给旁路观察器。未找到可被动读取的稳定来源。保留缺口。 | 新建独立 app-server 并不等于观察用户现有客户端会话，且不符合旁路架构。 |

上述结果保留 #5 和 #1 原有阻塞，不修改用户尚未批准的检测范围。新增 pi、Kimi、DeepSeek 的来源另见各集成能力文档；扩展工作端不补全原客户端缺失的事件。

## 可复查来源

[Claude 官方 Hook 参考](https://code.claude.com/docs/en/hooks#stopfailure) 定义 StopFailure 的错误类别，不提供独立 context exhaustion 枚举。

[Codex 官方 Hook 文档](https://learn.chatgpt.com/docs/hooks) 列出生命周期回调，说明 transcript 格式并非稳定接口；Interrupt 表示用户中断，不表示 API 故障。

[Codex rollout 持久化策略](https://github.com/openai/codex/blob/main/codex-rs/rollout/src/policy.rs) 将 Error 归入非持久化事件。本机 checkout 的 `codex-rs/rollout/src/policy.rs` 同样排除 Error。当前上游 main 与本机 checkout 的差异不作为已经安装版本的新能力。
