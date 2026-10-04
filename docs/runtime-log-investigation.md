# Char 运行日志调查（2026-10-04）

环境：macOS 26.5.1 / Apple Silicon / Swift 6.3.2。最终实现 `f2b5b4b`，仅记录本轮自建实例的限时窗口；未扩大权限或抑制日志。

## 窗口与结果

- 正常隔离实例 PID 68420：启动、设置及七工作端应用级激活期间，5 分钟 error/fault 窗口看到了 AppIntents/linkd 4097 和 libxpc assertion。窗口未观察到崩溃，正常路径继续工作；原因尚未归因。
- 计时版本 PID 71459（生产代码相同，另有临时纯耗时诊断）：10 分钟窗口包含 7 条 AppIntents/linkd 4097、1 条 libxpc assertion、13 条其他未归类 Char error/fault。这些计数不是去重后的故障次数。Tabbit 原路径在此实例准确返回，用户反馈延迟明显改善；没有证据将这些系统消息归因为此前卡顿。
- 最终无诊断实例 PID 80279：启动后再次采集 5 分钟限定 error/fault 窗口；统计为 7 条 AppIntents/linkd 4097、2 条其他未归类 error/fault；该窗口没有统计到 libxpc assertion。使用实际观察根/共享流、隔离声音和登录偏好，没有模拟导航。

采集命令按各实例实际 PID 限定：

```sh
/usr/bin/log show --last 5m --style compact \
  --predicate 'process == "Char" AND processID == 80279 AND (messageType == error OR messageType == fault)'
```

## 用户影响

**已修复：** Tabbit 回城 2–3 秒卡顿。纯耗时日志实际复现主线程每轮两次标签校验约 886–916 ms，加回城约 1062.2 ms。批量读取窗口 tab IDs 后，五次原生校验全部匹配且中位 46.8 ms，完整实体回城 276.4 ms，用户确认改善。临时诊断和只读 probe 全部移除。

**尚未归因：** AppIntents 4097 / libxpc assertion 和其他限定窗口消息。实例存活及成功操作不能证明这些消息永远无影响；当前没有建立它们与崩溃或返回失败的因果关系。保留在环境验收后续项，不改系统权限来制造干净输出。IMK/TSM 在此次统计中未出现，不等同以后永不发生。

## 网络检查边界

`lsof -a -p <PID> -i` 对本轮正常实例采样未发现开放 Internet socket。它只证明采样瞬间，不是完整抓包/流量审计，也不升级为完整本地隐私验收。没有保存或上传抓包。
