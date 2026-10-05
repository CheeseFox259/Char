# Windows 移植可行性评估

日期：2026-10-05。基于当前源码与官方文档的静态评估；本轮**没有Windows主机编译、Windows原生应用操作或性能测量**。

## 结论

可行，但需要重建桌面壳与平台适配层。注意力/首次回城/几何/配置代次等规则可以复用；当前Swift包直接构建Windows会遇到Apple框架、Darwin和macOS身份/路径依赖。Swift官方提供Windows工具链和SwiftPM，语言本身不是阻断点。[Swift官方Windows安装](https://www.swift.org/install/windows/)

建议先以Windows 11桌面原型确认“透明桌宠→点击Agent→Ctrl+B回原应用”闭环，再决定正式UI技术与目标系统版本。先交付应用级往返；每个桌面Agent的Windows发行/状态信号/精确导航需单独查证，不能从macOS支持推出Windows支持。

## 依赖清单

| 当前模块/位置 | 可保留部分 | 必须替换/拆分 |
| --- | --- | --- |
| CharCore / AttentionRouter、Models、CompanionGeometry、ObservationGeneration | 状态规则、排序、批次、Hold、数学几何 | bundleIdentifier语义拆为平台AppIdentity；CGRect/CGPoint及Foundation接口需Windows工具链实编译确认 |
| CharCore / IntegrationPlugins | JSON/注册表、启停、冲突规则 | ImageIO PNG校验移到平台服务；清单目标从bundle ID演进为平台特定exe/AUMID身份 |
| CharObservations | 原生事件语义、增量读取策略 | Darwin.stat、inode/时间字段、符号链接/目录revision、客户端日志路径和文件替换身份 |
| CharHook | 输入分类、元数据编码 | Darwin.open/flock/write、POSIX权限、跨进程写入锁；不能直接照搬到Windows |
| CharPlatform / WorkspaceRuntime | ApplicationRuntime抽象及exact/fallback/unavailable合同 | NSWorkspace、AX、CG窗口信息、应用激活、PID寿命与窗口绑定 |
| CharPlatform / PetSkins | 七动作JSON、帧预算、播放规则 | AppKit.NSImage、ImageIO验证/解码、缓存和路径规则 |
| CharApp | 布局/时序/状态规范 | AppKit/SwiftUI/QuartzCore、非激活Panel、托盘、设置、热键、声音、登录项 |
| TabbitAppleScript / VSCodeSocketBridge | opaque token生命周期与存活查询合同 | Apple Events无Windows等价；Darwin Unix socket和UID私有目录策略重做 |
| 原生pi/Kimi/DeepSeek集成 | 客户端事件合同和部分JS/Python逻辑 | Windows可用版本、宿主识别、进程启动、路径/安装与Hook二进制 |

源码可复用不等于无修改可编译；CharCore也导入ImageIO（IntegrationPlugins），并非现在就能作为纯Foundation跨平台库。当前PNG/manifest数据规范可作为兼容目标，但路径大小写、重名及用户目录迁移需要明确规则。

## 系统能力映射与主要风险

### 透明、非激活、穿透及托盘

Win32 layered window支持逐像素alpha；透明区域可以穿透。WS_EX_NOACTIVATE可避免点击时常规激活，通知区域可提供托盘菜单。气泡区域需要精确可交互命中，不能给整窗无条件WS_EX_TRANSPARENT后期望气泡仍能点击。候选实现需用实体鼠标证明穿透、滚轮、点击与焦点保留。[Layered windows](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features#layered-windows)、[扩展窗口样式](https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles)、[通知区域](https://learn.microsoft.com/en-us/windows/win32/shell/notification-area)

### 应用级往返

用GetForegroundWindow、窗口PID/应用身份记录起点，校验窗口与进程寿命后请求前台激活。SetForegroundWindow受系统前台策略约束，即使部分条件满足也可被拒绝；需检查实际前台结果并返回unavailable/fallback，不能默认为成功，也不能用伪造输入强抢焦点。[Microsoft SetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow)

Windows可保存HWND作为比当前macOS应用级更细的内部锚点，但同一窗口不等于同一聊天/标签；窗口句柄可能复用，须绑定进程身份并验证。是否形成独立window准确级别需另立合同，不能直接冒充现有exact会话语义。

### Ctrl+B和多屏

RegisterHotKey可以注册全局组合键，冲突会失败，应沿用“只在Hold中注册、冲突可见、结束释放”。多屏需Per-Monitor DPI策略和DPI变化后重算逻辑坐标/资源，不直接搬macOS的点与屏幕方向。[RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey)、[高DPI桌面开发](https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows)

### 虚拟桌面

已检查的公开IVirtualDesktopManager只有查询窗口所在桌面、判断当前桌面和移动窗口三项方法，没有当前macOS“加入所有Spaces”的同等入口，也不提供整屏转场曲线控制。Microsoft还建议由用户发起桌面切换。不能预先承诺所有桌面常驻或准确跨桌面回城；原型必须验证系统真实激活行为，必要时明确首版只在当前桌面可见。[IVirtualDesktopManager](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ivirtualdesktopmanager)

这不是断言Windows永远不可能实现；现阶段不采用依赖未公开COM接口/Explorer版本的方案作可靠产品合同。

### Warp、WSL与日志桥

Warp官方支持Windows x64/ARM64，并支持Windows shell和WSL，所以宿主可用；这不证明有精准pane控制接口。tmux路径通常置于WSL，需要与本机Windows工作端区分。[Warp平台安装](https://docs.warp.dev/getting-started/quickstart/installation-and-setup)、[Windows发行说明](https://www.warp.dev/blog/launching-warp-on-windows)

WSL与Windows共享文件路径有性能和访问语义差异，Microsoft建议按运行工具所在文件系统选择存储位置。建议WSL内运行小型事件桥，仅转出必要元数据，Windows侧由单一写入器管理自己的本地流；不要每500ms广泛遍历跨文件系统会话树，也不能假设Linux flock与Windows原生进程形成同一写锁。[WSL跨文件系统说明](https://learn.microsoft.com/en-us/windows/wsl/filesystems)

VS Code准确token协议有复用机会，传输/用户隔离改成Windows方案并实测；Tabbit AppleScript准确返回不能直接移植，需要Windows版本的正式接口或独立扩展，未查证则降级应用级。

## 实现路线比较（工程判断）

| 路线 | 收益 | 成本/验证 |
| --- | --- | --- |
| Swift共享内核 + Win32壳 | 保留现有规则/测试，一套业务核心 | 先拆ImageIO/Darwin；Swift/C互操作、渲染和Windows打包需原型 |
| Swift共享内核 + C# WPF壳，通过本地进程协议 | 保留核心，设置与桌面界面使用Windows成熟工具 | 多进程生命周期、协议和窗口互操作；透明窗性能必须实测 |
| C# WPF完整重写 | 单Windows进程和常规分发流程 | 重写路由/观察/校验，长期两套业务逻辑；必须以现有fixture作一致性合同 |

WPF支持Windows桌面窗口模型；透明窗应按其样式要求实现并实测，不能把“框架支持窗口”等同当前动效自动低功耗。[WPF窗口概览](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/windows/)

推荐先验证共享Swift内核能构建，再用最小Win32原型检验焦点/穿透/热键/DPI。原型结果决定Swift壳或C#壳，不先做跨平台UI大重写。没有Windows执行环境，不给出未经验证的工期或代码复用百分比。

## 分阶段验收门槛

1. **平台分离**：PNG验证与AppIdentity从核心隔离，Windows build通过；迁移旧macOS清单而不改变现有行为，核心fixture与macOS检查通过。
2. **桌面闭环原型**：透明窗、不抢焦点、托盘、真鼠标滚轮、目标激活、Ctrl+B成功/冲突/释放；源关闭/重启/窗口句柄复用后不误返回。
3. **观察与包**：先一个可靠工作端，不调用模型造数据；启动EOF、半行/替换/并发写/根身份/WSL桥/快启停测试。两类包复用规范，错误包不影响已安装包。
4. **动效与多屏**：同一放置模式跨100%/150%/200%DPI屏幕，44逻辑单位泡与命中一致；折叠正反/接续无错向，睡眠/锁定恢复不乱，虚拟桌面只宣称实测范围。
5. **性能与分发**：同场景CPU、工作集、GPU/桌面合成开销和输入→显示时延测量；原生/接收器/有线/触摸板分开。安装、卸载、登录启动及签名另验收。

只有应用级路线是可立即规划的候选；具体桌面Agent发行支持和准确标签导航属于后续每客户端查证，不在本次评估中记为通过。
