# Char v0.1.2 发布、安装与性能复验

日期：2026-10-06。用户明确要求发布新版本并从 GitHub Release 安装，随后要求重写 README 并展示当前性能占用。

## 发布来源

- tag `v0.1.2` 指向 `a83ee9ffe5e0f0135f80f52418a5900dea494f34`，版本 0.1.2、build 3。
- [GitHub Actions 37354637465](https://github.com/CheeseFox259/Char/actions/runs/37354637465) 于 `2026-10-05T18:18:06Z` 完成：版本检查、全部项目检查、双架构打包、附件验证及草稿上传均成功。
- [Release v0.1.2](https://github.com/CheeseFox259/Char/releases/tag/v0.1.2) 于 `2026-10-05T18:21:58Z` 公开发布，即上海时间 2026-10-06 02:21:58。`isDraft: false`，已设为 Latest。
- 附件为 Universal ZIP、DMG、SHA256SUMS；两个 executable `Char` 与 `char-hook` 都含 arm64/x86_64。

| 附件 | SHA-256 |
| --- | --- |
| Char-0.1.2-macos-universal.zip | `72fbc7086f9bbf20be7414e0de00d838eec438ab6cc1e07450a1a4c79255c62d` |
| Char-0.1.2-macos-universal.dmg | `c0c35bef101cab5f0b7e810c5de129b4d6671130d9e7b285b62c91ce3c11bbea` |

## 下载与安装

使用 `gh release download v0.1.2 --repo CheeseFox259/Char` 下载实际附件到 `build/downloaded-releases/v0.1.2/`。在本机通过 SHA256SUMS、ZIP 解压、严格 deep codesign、Info.plist 版本和双架构检查，`hdiutil verify` 确认 DMG 有效。

旧应用与数据归档保存在 `build/installation-backups/v0.1.2-2026-10-06/` 的 `Char-before-v0.1.2.zip` 和 `Char-user-data-before-v0.1.2.zip`。退出旧进程，将下载的 bundle 安装到 `/Applications/Char.app`，`diff -qr` 与下载 bundle 一致，codesign 校验通过。没有安装本地构建。安装后删除下载解压目录，保留压缩包；只运行一个正式实例。

## 已验证

- 安装后的实际 bundle 执行 `--smoke --settings-preview-check` 成功：无变化的快捷键文字不发布，语言切换正常；预览可见/隐藏时钟、形象选择/恢复、Reduce Motion、关闭计时器释放均通过。
- 同一 bundle 的完整 `--smoke` 通过：七个工作端、Ctrl+B、首次锚点、成功访问与气泡破碎、轮换、插件拔插、五种放置、形象包均通过；使用随机临时数据，无真实模型请求。
- 用户解锁后通过 CUA 检查真实实例，实际设置画面正常。中文、右边缘、48 pt、18 pt 气泡距离和默认 Char 形象保留，内置集成仍开启，过滤 10 秒、回城宽限 300 秒。
- 登录启动开关为开启，状态为“已启用”，没有 ServiceManagement 错误。Tabbit 自动化仍为“已授权”。辅助功能显示“未授权（可选）”，本轮未重置或修改系统授权；已告知用户通过 `/Applications/Char.app` 重建授权。当前显示器查询使用 CG 回退。
- 最后关闭设置，实例继续从 `/Applications/Char.app/Contents/MacOS/Char` 运行；真实观察出现一个 Codex Desktop 运行气泡。

## 当前 Release 性能

原始数据在被 Git 忽略的 `build/release-verification-0.1.2/`。实际 Release 实例 PID 36257；macOS 26.5.1（25F80）、Mac16,12、10 个逻辑 CPU、多屏、内置观察开启、一个 Codex Desktop 运行气泡、无 Hold。Tabbit 已授权，辅助功能未授权。CPU 区间开始与结束检查均解锁，界面状态无变化；代理在区间内没有操作 App。

每项测 20 秒累计 user+system CPU / 墙钟，再执行 5 秒 stack sample。100% 为一个逻辑核心；RSS 不是 physical footprint，不包含 WindowServer/GPU。

| 场景 | 单核 CPU 平均 | CPU 时间 / 墙钟 | RSS 起 → 止 |
| --- | ---: | --- | --- |
| 设置静止打开，预览可见 | 6.69% | 1.34 / 20.017 秒 | 110.7 → 110.7 MiB |
| 常驻观察，设置关闭 | 8.04% | 1.61 / 20.016 秒 | 78.8 → 78.7 MiB |

设置打开和关闭会改变前台应用，几何回退的输入不同；短时样本亦存在波动，不能据此声称打开设置更省 CPU。两个数字展示各场景本身的占用，不与 v0.1.1 已授权样本直接计算收益。七气泡隔离演示的 37.79% → 2.65% 是独立的设置优化对照，详见 [性能优化报告](performance-optimization-2026-10-06.md)。

## 未运行与边界

- 未执行 Intel 实机、真实注销/登录、完整 VoiceOver、长时内存、电池/GPU、授权恢复后的相同条件 CPU 对照。
- 全部原生烟测使用临时数据，不代表每个真实 Agent 已重新产生事件并验收。没有读取聊天正文或发起模型请求。
- 应用仍为 ad hoc 签名，未 Developer ID 签名或公证。发布后实际辅助功能状态说明更新可能需要重新授权；未将这一状态记作“授权通过”。

发布与安装完成，没有构建或安装阻塞。
