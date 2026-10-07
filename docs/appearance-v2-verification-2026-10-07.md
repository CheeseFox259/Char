# 外观能力与边缘宿主修复验证

2026-10-07。v0.2.2修复已发布并从GitHub Release安装；本轮v0.3.0新增可选v2能力，旧v1兼容。自定义包真实使用验收仍交用户。

## 已验证

- 修复前：实际GraphicButton绘制路径在edgePeek→idle发生方向突变，左边缘36pt的相同帧比较失败。修复后：desktop/四边、36/48/88pt、peek/idle/press/return/hide相同像素一致；用户现有feibi包在四边迁移后保持边缘落位，未改原形象文件。命令：`CHAR_APPEARANCE_CHECK_PACKAGE=.../feibi.charpet .build/debug/Char --smoke --appearance-edge-check`。
- `bash scripts/check.sh`通过：核心/观察/平台/插件/Hook/native集成及新增JS helper协议组。后续核心方向参数调整用`swift run char-core-checks`复验通过。
- v2生产包检查：`scripts/make-appearance-fixture.py`生成的确定性包，导入/主题持久化/关闭行为偏好/资源缓存、非法动作/字段/主题/路径/参数拒绝、删除恢复。
- 临时签名App：真实ICNS生成、暂存副本重签、`codesign --verify --deep --strict`、默认图标恢复。未用Finder资源叉图标，未为此修改用户安装。
- 实际原生App隔离路径：`.build/debug/Char --smoke --appearance-v2-check`。跟随改变实际像素，主题替换帧，五种姿态可绘制，hitRegions命中换算，bindings播放额外动作，布局/行为开关，点击打开实际设置窗口；查看宠物、气泡与设置原生截图，主题选择和行为开关可见。
- 持久JS事件计数、无require/fetch/process/ObjC桥、异常及无限循环超时终止；导入确认、切换停止旧helper路径已实现。事件队列32、回包32KiB、动作16有界；不向脚本发送消息正文/token。

实际截图在本地 `build/appearance-v2-render/`，包括desktop/top/left/right/bottom、气泡与设置。测试图案是确定性中性机制样本，不是用户形象或美术验收。未将离线像素断言声称为用户可见动画流畅通过。

## 性能组成与控制

| 成本 | 控制方式 |
| --- | --- |
| 图片解码/缓存 | 路径与帧身份复用，唯一PNG总像素≤16,777,216（裸RGBA≤64MiB，非RSS） |
| 主题/姿态解析 | 按包/主题/placement缓存，切换形象清理；不逐帧合并清单 |
| 跟随/动画 | 原生平滑、量化gaze，纹理只在变化时重绘；图层承担轮换/高亮/破碎 |
| 脚本 | 无script不启动helper；有script仅响应状态/交互事件，无帧tick，串行协议/超时 |
| 音效 | 需要时加载、音量/冷却，静音和切换停止，最长30秒 |
| 安装图标 | 只在选择/主题变化时更新；150ms合并请求，后台串行事务，保留原Release |

单独helper轻量实测：Mac16,12 / macOS26.5.1，debug arm64，init后空闲20.25秒，RSS **9.27–9.28MiB**；ps累计CPU时间在该区间未显示增量。该结果不是绝对0% CPU，也不代表整个Char、眼睛绘制、WindowServer或功耗。原始20个采样见[JSON证据](evidence/appearance-script-idle-2026-10-07.json)。EOF后进程退出。此前宿主性能报告不直接外推到任意v2形象。

## 留给用户的使用验收

真实音效/静音、独立边缘美术裁切与动画、指针方向/双影、黑白背景气泡样式、多屏焦点跟随、Finder/Launchpad缓存呈现、系统AX授权及自制脚本行为。完整GUI步骤见[外观验收](plugin-user-acceptance.md#外观包应交付的完整步骤)。没有模拟真实模型请求或改用户插件配置。

## 版本与恢复

v0.2.2来自PR #21，GitHub CI通过Universal ZIP/DMG签名与SHA256，实际下载ZIP校验后安装到`/Applications/Char.app`；本机仅此安装，旧v0.2.1为数据目录中的ZIP归档。

v0.3.0发布后的CI、下载SHA256、安装签名、版本/唯一进程和实际设置检查记录在此文末。运行图标同步会生成本机ad hoc变体，保留原Release；不将变体的校验和声称为原下载包。签名变化可能需要重新添加Char辅助功能授权，当前Developer ID安装不自动改签。

## v0.3.0 发布与本机安装证据

- PR #22 已合并，main `91ad194`。GitHub CI [37580937681](https://github.com/CheeseFox259/Char/actions/runs/37580937681)通过完整项目检查及Universal ZIP/DMG验证，Release已公开。
- 实际下载ZIP SHA256：`8cf697996c5cdc79b7c545637c1e2131fc317ddaa3f83ab8c3a933113fad00e6`；严格签名与Char/char-hook/char-appearance-script双架构核对通过。下载包的原生`--smoke --appearance-v2-check`通过。
- 从实际下载包安装到`/Applications/Char.app`，plist版本0.3.0/build7；仅一个安装实例、一个正式进程。当前v1形象自动同步安装图标，`CharAppearanceIcon`为`c26a9675…`，严格签名通过。原始Release及旧安装保存在数据目录ReleaseBackups的ZIP中，构建目录不再留可发现的Char.app副本。
- 用户两次报告解锁后，界面工具仍返回Char连接超时/Finder窗口不可得；不能声称正式设置、AX权限或Finder缓存画面检查通过。已请用户在Char设置反馈权限与同步状态。实际隔离原生绘制证据有效。
- 最终源码检查发现状态栏缓存仅按形象ID更新，遗漏主题ID；增加真实状态栏图像切换/恢复检查，补丁v0.3.1统一图标切换行为。
