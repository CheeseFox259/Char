# Domain Docs

## 阅读规则

探索项目前，先阅读根目录 CONTEXT.md，
再阅读 docs/adr/ 中与当前工作相关的 ADR。

若文件不存在，直接继续；需要明确术语或记录决定时，
再通过 domain-modeling 创建。

## 文档布局

采用 single-context：

- CONTEXT.md：项目术语表
- docs/adr/：架构与产品决定

## 使用领域语言

输出中的领域概念沿用 CONTEXT.md 定义的名称，
避免使用其中明确不推荐的同义词。

## ADR 冲突

若方案与既有 ADR 冲突，明确指出冲突与重新讨论的理由，
不要静默覆盖已确定的决定。
