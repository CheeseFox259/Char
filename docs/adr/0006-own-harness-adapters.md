# char 拥有工作端适配层

char 自行定义并维护各工作端的状态与会话身份适配层，AgentHUD 的事件流只作为可选辅助信号。[AgentHUD 的实时事件流](https://github.com/neochoon/agenthud/blob/main/FEATURES.md#follow)已提供跨会话 ID 与 `working/waiting` 状态，但 char 还需要区分停顿原因、定位原窗口或 pane、管理注意力项与返回锚点；将 AgentHUD 设为必需底座或直接 fork 会把这些核心能力绑在它的较粗事件模型上。
