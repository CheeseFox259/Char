# Char 性能优化实测

日期：2026-10-06。本报告记录发布前的优化测量。优化基于 `e5d17ee` 工作树，应用源码与 v0.1.1 tag 相同；测量时修改尚未发布，正式安装为 `/Applications/Char.app` 的 GitHub Release v0.1.1 build 2。优化纳入 v0.1.2。

后续已发布并从 GitHub Release 安装 v0.1.2，实际安装后的真实观察 CPU/RSS 和权限状态见 [发布复验](release-verification-0.1.2.md)。

## 结果

同一隔离演示场景下，设置静止打开的平均单核 CPU 从 **37.79% 降至 2.65%**，相对下降 **92.99%**。只隔离预览时钟的中间版本为 10.19%；进一步去除无变化的快捷键状态发布后，静止设置采样中不再出现 `NSHostingView.layout`。

常规演示设置关闭时，优化前为 2.00%，最终版本为 2.50%；本轮没有证明该场景 CPU 降低。内存也未获得可复现的改善结论。上述收益仅针对已测的静止设置场景。

## 实现机制

1. **预览局部更新。** 将 SwiftUI `TimelineView` 换为 `NSViewRepresentable` 内的 `PetPreviewView`。12 Hz 时钟只更新已有 `GraphicButton` 的时间和图层内容，复用其位图缓存，不再每帧触发表单求尺寸和布局。使用单调时钟计算动画时间；主线程 common run-loop mode 保持预览在交互期间正常更新。
2. **时钟生命周期。** 预览隐藏、滚出可见区域或窗口不可见时跳过帧更新；再次可见后继续。Reduce Motion、窗口解绑和 representable 拆除时注销计时器。计时器闭包弱引用视图。关闭设置仍释放整个 hosting view。
3. **只发布变化。** `refreshHomeShortcutStatus()` 先计算当前语言的文字，文字变化才写入 `@Published` 属性。原先每 500 ms 观察轮询即使仍是“Ctrl+B 未启用”也会刷新设置；现有 Hold、注册失败、重试和语言切换仍能更新文字。
4. **前台身份与窗口几何分开。** `ApplicationRuntime.foregroundApplication()` 仅通过 NSWorkspace 读取前台 bundle ID 和 PID。来源捕获与 `focusContext` 使用此路径；准确回城继续由 Tabbit/VS Code 适配器取得 token。跨屏跟随继续使用 `foreground()`，保留 AX/CG 窗口几何和 150 ms 检查间隔。双屏周期几何查询的名义频率由约 8.7 次/秒降为 6.7 次/秒（不含激活通知及点击）；这是调用频率变化，不能换算为相同比例的 CPU 收益。

没有引入几何缓存或降低跟随频率；普通 idle、轮换、Space 和跨屏动画曲线未调整。

## 环境与方法

- macOS 26.5.1（25F80），Mac16,12，10 个逻辑 CPU，多屏环境。
- 正式版新基线：辅助功能与 Tabbit 均已授权，中文、右边缘、48 pt、18 pt 气泡距离、一个 Codex Desktop 气泡、无 Hold。设置采样时预览可见。
- 对照：唯一临时应用 `Char Performance Check.app`，独立 bundle ID `com.cheesefox.char.performancecheck`，使用 `--demo` 的随机临时数据目录。前后均为 English、Desktop、48 pt、20 pt、七个气泡、无 Hold、设置位于顶部。演示不运行真实观察与显示器焦点查询，所以对照只量化设置优化。
- 旧版来自已安装 Release 的 executable；优化版来自 `swift build -c release --product Char`，原生 arm64。资源相同。正式版在隔离采样期间退出，完成后恢复，未替换或重签正式安装。
- 每项测 20 秒进程累计 user+system CPU 时间与 RSS，随后执行 5 秒 `sample`。CPU 区间内没有代理界面操作；100% 表示一个逻辑核心。RSS 与 physical footprint 不混用。

```sh
python3 scripts/profile-char.py <PID> --seconds 20 --sample <sample-file>
```

## 实测数据

| 场景 | 单核 CPU | CPU 时间 / 墙钟 | RSS 起 → 止 |
| --- | ---: | --- | --- |
| 正式 Release，授权后，设置关闭 | 6.60% | 1.32 / 20.015 秒 | 33.1 → 33.7 MiB |
| 正式 Release，授权后，设置静止打开 | 44.31% | 8.87 / 20.016 秒 | 66.0 → 65.9 MiB |
| 旧版演示，设置关闭 | 2.00% | 0.40 / 20.004 秒 | 52.9 → 51.8 MiB |
| 旧版演示，设置静止打开 | **37.79%** | 7.56 / 20.007 秒 | 101.1 → 100.8 MiB |
| 中间版演示，设置静止打开 | 10.19% | 2.04 / 20.012 秒 | 112.5 → 112.5 MiB |
| 最终版演示，设置关闭 | 2.50% | 0.50 / 20.012 秒 | 63.2 → 58.4 MiB |
| 最终版演示，设置静止打开 | **2.65%** | 0.53 / 20.014 秒 | 108.5 → 94.4 MiB |

正式版 PID 92416，旧演示 PID 5591，中间版 PID 7147，最终版 PID 8899。最终测试 executable SHA-256：`83f0923f24a7a31b9e84933abb3b55a5322809789dd60e2eb5d9c45314bee6ce`。

原始 JSON、stack sample 和 smoke 输出保存在被 Git 忽略的 `build/performance-optimization-2026-10-06/`。文件前缀分别为 `release-*`、`before-demo-*`、`after-demo-*`（中间版）、`final-demo-*`。早期被中断的空采样不计入结果。原始栈含进程信息，不纳入发布文档。

完成后已退出并注销隔离应用，将其归档为该目录中的 `Char-Performance-Check.zip` 后移除 `.app`，恢复正式安装运行。没有新增同名安装或修改正式包的权限记录。

RSS 受驻留页面、压缩与进程启动状态影响；每场景单个短样本不足以说明长期内存趋势。正式观察模式与演示的数据源、权限和放置方式不同，不能直接比较 44.31% 与 2.65% 来声称正式模式的下降比例。

## 验证

**已验证：**

- `bash scripts/check.sh`：Core、观察、平台、Hook、VS Code、pi、Kimi 与 DeepSeek 检查全部通过。
- `swift build -c release --product Char`：最终构建通过，无新增编译警告。平台检查补充计数断言，确认来源捕获、准确/应用级锚点和焦点状态读取不枚举窗口；显示器查询仍返回几何。
- 隔离应用 `--smoke --settings-preview-check`：无变化的状态不发布、语言变化发布；可见预览时钟推进，隐藏时不绘制，再可见恢复；实际 SwiftUI 设置中导入/选择形象改变像素、删除恢复默认像素；Reduce Motion 停表并显示静态帧，恢复动效重新启动；关闭设置后窗口与计时器释放。
- 隔离应用 `--smoke`：七个工作端、Ctrl+B 回城、首次锚点、点击破碎、轮换、插件拔插、五种放置方式和自定义形象检查通过。
- 实际设置截图确认默认预览、图标、滑块与插件列表正常；同场景 CPU 和 native stack 对照完成。

**未运行：** 优化版正式观察模式的授权后 CPU 对照、实体跨屏跟随复验、长时内存、WindowServer/GPU 和电池功耗。几何选择与跟随实现未变，已有平台几何契约仍通过。本轮不把未测部分记作验收成功。

**阻塞：** 无。本地优化完成；本报告的测量在发布和安装新 Release 前进行。

**不适用：** 云服务吞吐、模型调用延迟。Char 本轮没有发起模型请求或读取会话正文。

## 后续优化依据

下一次正式 Release 安装后，可在相同授权、气泡数量和前台应用条件下复测真实观察 CPU。若静止开销仍显著，再分别测量 150 ms 几何查询、动画/指针时钟和观察文件 IO；按实测决定是否使用 AX 事件、减少无变化的指针更新或文件事件提示。当前收益已由两次单变量修改确认，不需要在本轮引入新的事件框架。
