# 旁路观察原生会话

char 观察既有 Agent 会话，可以读取本地会话数据，并可选用 harness 自身提供的 Hook 获取更准确的信号。char 不接管 Agent 的启动和运行：使用者希望继续在各自选择的原生 harness 中工作；改由 char 托管会改变这一工作方式，也会让跳转和会话归属依赖 char。
