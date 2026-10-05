# Char v0.1.2 — macOS

## 更新

- 设置中的桌宠预览改为局部图层更新，避免动画每帧重新布局整个设置表单。
- Ctrl+B 状态文字只在变化时刷新，减少静止设置的重复布局；语言切换、注册失败与回城状态仍正常更新。
- 来源捕获与回城状态检查改用轻量前台应用身份查询，减少重复的 AX/CG 窗口几何读取。跨屏跟随仍使用原有几何查询与 150 ms 检查间隔。
- 预览不可见时跳过绘制，减少动态效果或关闭设置时停止预览时钟。

同一七气泡隔离演示中，静止设置的平均单核 CPU 从 37.79% 降至 2.65%，下降约 93%。这是设置场景的对照结果；真实观察模式的整体 CPU、内存和电池功耗尚无相同条件的优化后结论。方法与验证范围见 [性能报告](https://github.com/CheeseFox259/Char/blob/v0.1.2/docs/performance-optimization-2026-10-06.md)。

## 安装

支持 macOS 13+，Universal 包包含 Apple Silicon 与 Intel。下载 DMG 后将 Char 拖入 Applications，或解压 ZIP 安装到 `/Applications/Char.app`，更新前退出旧版。已有设置、插件与形象保留。

应用采用 ad hoc 签名，未做 Developer ID 签名或公证。更新后若辅助功能状态变为未授权，请在系统设置的辅助功能权限中移除旧 Char 记录，再通过 `/Applications/Char.app` 精确添加并开启；Tabbit 自动化以设置中的实际状态为准。

附件提供 ZIP、DMG 和 `SHA256SUMS`。
