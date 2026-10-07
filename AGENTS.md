# Working Agreements

Choose the smallest workflow that completes the requested deliverable. Follow user instructions, project rules, and settled decisions. Route while working; do not turn routing into an approval step.

- Software: use the relevant engineering method. Use `efficient-dev` from the session skill catalog only when a task spans multiple engineering activities.
- Research: investigate the question, prefer primary sources, and cite factual claims. Use the research skill only when the user requests a repository Markdown note with background delegation.
- Slides, documents, spreadsheets, PDFs, and visual assets: use the matching artifact skill and inspect the deliverable in its intended format.
- Other requests: act directly; load a specialist skill only when it improves the result.

For user-facing software or release readiness, use `verify-product` from the session skill catalog when runtime evidence matters. Report the work and checks actually completed. Routing grants no authority for unrelated edits, external writes, delegation, or publication.

## Agent skills

### 插件开发入口

为某个软件新增 Char 插件时，先读 `integrations/AGENTS.md`，按其中的工作目录和开发流程实施。仅制作已有能力的配置包时读 `Resources/Integrations/AGENTS.md`；制作自定义形象时读 `Resources/Skins/AGENTS.md`。这些任务以对应开发指南为 SDK 契约，不需要先遍历 Char 的 Sources 或历史文档。

### Issue tracker

使用 CheeseFox259/Char 的 GitHub Issues。
详见 docs/agents/issue-tracker.md。

### Triage labels

使用默认五种分诊标签。
详见 docs/agents/triage-labels.md。

### Domain docs

采用 single-context：根目录 CONTEXT.md 和 docs/adr/。
详见 docs/agents/domain.md。
