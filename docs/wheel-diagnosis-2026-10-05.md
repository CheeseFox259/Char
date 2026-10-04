# 实体鼠标滚轮滞后与反向运动诊断

本轮沿用用户要求：先以问题说明采集时间与步骤，用户回复完成后才分析；App 操作提前说明。最后更新：用户更正此前采集为有线连接，并确认改用USB接收器后无滞后。连接模式是新确认的区分变量；有线链路的具体原因尚未确定。

## 实际反馈与输入证据

- 新的独立图层版本仍被用户确认：滚动滞后、移开鼠标补滚，反向时有一泡仍向原方向走。
- 第二次受控采集：96 个平滑事件、8 次接受切换，平均输入延迟7.91 ms；被跟踪图层在5–22 ms开始、180–194 ms到位。用户仍看到滞后与移开补滚。没有多接受一步的记录。该证据只证明客户端图层进度，不证明屏幕及时显示。
- 所有平滑事件源PID对应正在运行的BetterMouse。用户临时关闭平滑后仍反馈相同问题；日志切为系统源PID0，11个单事件刻度均接受一次，输入延迟平均9.6 ms、最高17.52 ms。图层开始4–22 ms、到位184–193 ms。平滑尾巴不能解释整体显示滞后。
- 本轮采集日志为`/tmp/char-wheel-deep-second-capture.log`与`/tmp/char-wheel-deep-raw-ab.log`，只含事件、时间及图层几何；未记录对话或网页内容。

## 两项已确认原因与修正

### 开放边缘弧的折叠跨越

真实平滑采集sequence682接受`+1`，普通相邻大泡的角移动为约`-0.8145 rad`，但从首槽退入折叠区的大泡走了`+2.4435 rad`。最短弧算法不知道边缘是开放弧，于是大泡跨过整段140°弧、与邻泡方向相反。

可重复红灯命令：

```sh
python3 scripts/analyze-wheel-trace.py /tmp/char-wheel-deep-second-capture.log --check-orbit-direction
build/Char.app/Contents/MacOS/Char --smoke --orbit-path-check
```

修正前真实图层fixture在四个边缘完整循环中稳定失败。修正对长边界跨越先就地缩小/淡出，缩到小泡以下后转移，最后在入口/折叠位置展开；相邻主要气泡仍180 ms线性移动。接续从当前呈现位置、缩放、透明度开始，旧隐藏完成回调仍由代次取消。

### 小泡接续读取三维平均缩放

模型使用二维affine缩放，z保持1；读取`transform.scale`得到的是聚合值。18/44的实际XY缩放是0.40909，聚合值却是0.60606；下一次接续误将18 pt小泡当成26.67 pt。只改折叠路径后的实际fixture仍失败，并显示这个错误起始尺寸。

独立真实CALayer实验先报红（18 pt→26.67 pt），改用`hypot(m11,m12)`读取实际平面缩放。复用同一生产辅助函数的检查覆盖15个普通/旋转XY缩放情况：

```sh
swiftc Sources/CharApp/LayerGeometry.swift scripts/check-planar-layer-scale.swift -o /tmp/char-planar-scale-check
/tmp/char-planar-scale-check
```

`45821dc` release包的实际五放置、每端完整正反循环与40 ms反向接续fixture通过。日志：`/tmp/char-wheel-path-planar-after.log`。该通过证明上述图层路径/尺寸合同，不能作为整体屏幕滞后解决的结论。

## 整体滞后的当前试验

Apple区分AppKit管理的backing layer与自主管理的hosting layer；后者要求先指定layer再启用wantsLayer，host内不添加NSView子视图。[Apple说明](https://developer.apple.com/documentation/appkit/nsview/wantslayer)

当前根场景直接修改AppKit管理的层，同时改变多个事件视图frame。准备了同二进制的`CHAR_HOSTED_SCENE=1`单变量对照：独立host只管理绘制图层，事件/无障碍视图作为兄弟保留；原显示路径仍是默认。未加入强制flush、改变鼠标驱动配置或降低动画速度。此试验尚未证明原因，不作为交付修正。

`27b27a8`构建通过。默认显示路径的完整smoke运行在Space可见性检查失败，随后CUA明确报告Mac锁定；不计为通过。此前解锁完成的图层路径及缩放检查有效。

第一组已准备在隔离正常模式：右边缘、48 pt桌宠、20 pt距离、七个私有合成观察，应用激活为真实平台。用户实际日志未注入，无模型请求。待手动解锁确认可见后，先测试两项修正但保留原显示路径，再只切换hosting flag重复。期间不重做用户已接受的Space方案。

### 第一组：两项修正＋原显示路径

用户完成采集后反馈：“首格滞后，反向先走错一步，移开补滚”，声明 BetterMouse 平滑滚动开启。采集边界后的7个实际事件均被接受，事件源PID0；平均输入延迟8.23 ms，最高14.16 ms。普通图层14–18 ms开始、181–185 ms到位；折叠跨越的早期压缩按设计保持位置，67–69 ms开始转移。日志`/tmp/char-wheel-fixed-baseline-capture.log`。两项修正没有解决整体可见滞后。

### 第二组：仅切换hosting

同一`27b27a8`二进制的hosted完整smoke在解锁状态通过（`/tmp/char-wheel-hosted-smoke.log`），包含无视图子项的hosting归属检查及原有产品路径。随后启动正常私有fixture，保留第一组48 pt/right/20 pt与七个气泡，仅启用`CHAR_HOSTED_SCENE=1`，CUA确认气泡可见。已发起相同步骤的实体采集问题，等待用户完成后才读取并分析采集段。日志`/tmp/char-wheel-hosted.log`，边界`/tmp/char-wheel-hosted.capture-start.json`。

第二组用户完成后反馈“问题没有任何变化”。边界后的16个输入均接受为16次切换，输入延迟平均11.33 ms、最高22.90 ms；普通图层起动约7–23 ms、约178–194 ms到位。折叠压缩有预期的约60 ms位置保持。实际方向检查没有发现新的可见反向路径，但用户仍看到旧方向一步及整体滞后。日志`/tmp/char-wheel-hosted-capture.log`。此次hosting变体没有解决问题，不能据此选为交付修正。

接下来收紧到单格静止鼠标：先保存画面，要求用户只滚一格并用键盘回复，再核对这一段实际事件、呈现位置与CUA截图。输入计数/屏幕像素之间尚缺少能自动判红的完整闭环，已有CALayer检查不能替代用户所见的滞后。

### 单格停住与只移开：输入边界红灯

用户按约定只滚一格并停住，回复“单格已停”后，采集段无任何`input`或`accepted`；CUA画面保留offset0的Claude/Codex排列。对该实际采集执行“单格应收到一次input”断言，输出`expected=1 received=0`并exit1。日志`/tmp/char-wheel-held-capture.log`。随后单独要求只移开、不滚轮；用户确认有补滚，日志此时才收到sequence17、dy=-30并接受-1，输入到handler约10.5 ms，动画约187 ms到位（`/tmp/char-wheel-exit-capture.log`）。事件时间也接近移开阶段。这次直接证据把调查边界提前到输入送达，不能继续将全部延迟解释为绘制。

临时增加不消费、不重发事件的NSEvent local/global scroll monitors，比较App入口、气泡入口和`ignoresMouseEvents`/指针目标转换；全局观察仅记录指针位于Char画布时的滚轮数值和坐标，没有键盘/内容监控。按[Apple事件监控说明](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)，local对应本App派发前，global对应其他App。当前保留相同hosting路径以隔离诊断改动，未修改滚动策略。release编译/打包通过；七个私有气泡经CUA确认，入口采集问题已发出，等待完成回复后分析。

入口采集用户说明第一遍误滚两格、第二遍正确且问题不变。日志合计3个App入口输入，均在约0.2–1.2 ms内到达surface，并各接受一步；不存在App入口已收到但surface等待下一格的证据。global入口未收到这一段Char画布内的滚轮。最后一次事件点`[270.8125,230.082]`随后连续变为移开路径，说明输入需继续向App入口前追查；没有独立HID时序，暂不能把原因归给某个工具。

按顺序验证鼠标转换工具、透明窗口穿透切换、非激活面板派发三项。尝试CUA连接BetterMouse超时，未声称已经退出，改由用户从菜单正常退出并做一格停住/只移开对照；不是更改其设置。问题已发出，待完成回复后核对进程并分析。

用户随后要求先重采精准数据。退出BetterMouse的采集暂停，进程确认BetterMouse3094和Char51025仍运行，未退出或改设置。新采集按两段独立问题进行：第一段在当前中间Kimi Desktop泡中心悬停3秒、下滚一个刻度、完全停住5秒、键盘回复；收到回复后才分析，然后另行采集不滚轮只移开。CUA已保存当前offset4的画面对照，第一段边界`/tmp/char-wheel-precise-held.capture-start.json`。

精准第一段用户回复“第一段已停”。仅记录进入KimiDesktop目标时从accepts=false到true的两帧转换，此后无panel local/global入口或surface输入；目标稳定时窗口已允许接收。CUA画面保持offset4，当前日志`/tmp/char-wheel-precise-held-capture.log`。第二段单独要求不再滚、只移开，等待回复后核对。注意local探针目前仅记录event.window为panel的事件，仍需考虑App收到不同/空window事件的情况，不能仅凭此排除App派发前的窗口关联问题。

精准第二段用户确认“第二段已移开，补滚”。此时才出现sequence4、dy=-30，panel local入口与surface入口相差0.815 ms，接受step=-1、offset4→3。两次严格分段均复现首格未送达、只移动后送达；日志`/tmp/char-wheel-precise-exit-capture.log`。下一项仍是完全退出BetterMouse的同二进制对照，未把它预先认定为原因。

退出工具对照：用户说明第一遍意外移开、第二遍停住成功。回复后进程确认BetterMouse完全退出。第一遍移开路径附近收到sequence5，改为precise=false、continuous0、dy=0.100006、CGline1，立即接受一步；第二遍进入KimiDesktop并静止后无新的panel入口/surface输入。等待第二段只移开确认，不更改鼠标设置。准备下一反事实`CHAR_STATIC_MOUSE_ROUTING=1`固定原生窗口接收，关闭60Hz指针穿透开关，默认仍OFF；local探针扩至全部本App滚轮，避免空/不同window事件漏观测。当前运行包未替换，等待采集完成后才启用反事实。

退出工具第二段用户确认只移开后补滚；sequence6在此阶段才到达，仍为普通非连续鼠标事件，App入口到surface约0.888 ms。退出BetterMouse没有解决送达滞后。通过CUA重新打开BetterMouse（初始AX超时，但进程66582确认恢复），未改其配置。

下一组打包并启用`CHAR_STATIC_MOUSE_ROUTING=1`（其余hosted/诊断/私有fixture配置保持），进程71420；CUA确认七泡可见，启动日志accepts=true且始终不切换穿透。已说明透明画布暂接收鼠标并发出单格停住采集；边界`/tmp/char-wheel-static-route-held.capture-start.json`，等待完成回复。

固定路由组用户回复“首格没有立刻切换”。采集段只出现accepts=true且target=codexCLI，全部本App local探针、global探针及surface输入均无事件。这组也失败。无需重复已有的移开复现，改验证`CHAR_ACTIVATING_WINDOW=1`：初始化为带标题栏、可成为key/main的激活面板；固定原生接收、hosted绘制、策略与七泡fixture保持。启动可激活，要求用户采集前点击标题栏；入口日志增加panelKey以核对该反事实实际成立。未将此诊断窗口形态选作产品方案。

激活窗口组用户确认首格未立即切换，但为回复移动了鼠标。日志验证appActive=true、panelKey=true；两条入口各在移动附近出现，surface在1.3 ms以内处理。因采集段实际有两次事件，不能声称“一条唯一事件”，也不能将回复前移动后的输入算作及时首格。该反事实没有消除用户症状。

准备下一边界：仅scrollWheel的被动CGEvent taps，分别位于HID head与session tail；坐标位于Char画布时才写数值/时间，不监听键盘，不重发/改写事件。启动先调用CGPreflightListenEventAccess，只在现有权限允许且显式diagnostic flag开启时创建tap；拒绝/缺失权限不发起请求。新建权限须先取得用户明确授权。

新普通面板实例77548读取现有listen权限为true，HID/session两个被动tap均成功建立；无新授权请求。前述hosting/static/activating flags全部关闭以恢复普通基线。CUA两次自动化scroll（AX索引与坐标）均返回AXError.notImplemented，日志无滚轮事件；不计作校准成功。七泡布局保持offset0。用户说明不能保持鼠标静止回复，下一采集改为明确3秒悬停→一格→完整5秒静止→只移开→回复，允许鼠标回复，用不同边界时间辨别送达。边界`/tmp/char-wheel-raw-held.capture-start.json`。等待完成回复前不读取采集段。

系统流采集用户补充：鼠标不必移出气泡，只要轻动就会切换。该段实际记录4个HID→session→App→surface输入链（并非约定单格），链内派发很快，不能将每条对应到单格/后续试探。HID层native timestamp与session层单位不同；此机mach timebase为125/3，现改只存nativeTimestamp整数与同一systemUptime callback时钟，避免把HID原值直接当ns解释。没有把该单位差异宣称为病因。

准备明确实验边界的两个临时Carbon标记Ctrl+Shift+9(begin)/Ctrl+Shift+0(heldEnd)，仅注册这两组合，无键盘事件监控；只在raw诊断模式启用，停止/退出即解除。普通诊断实例88090，existing listen=true，两个tap安装，两个标记注册status0，七泡可见。已通知采集：一格后静止5秒打结束标记，再静止10秒；期间只读标记触发并由CUA采集一张Char截图，不进行滚轮数据分析、不输入/移动，等待用户完成回复再分析。当前边界`/tmp/char-wheel-marked.capture-start.json`。

标记采集完成，用户确认静止不切换、轻动补滚。begin662336.130376→heldEnd662348.480403，12.350秒内CG HID/session、App/surface/accepted全为0；结束后约15.093秒才出现唯一完整滚轮链，静止CUA截图保持offset0。可重复红灯命令：`python3 scripts/analyze-marked-wheel.py /tmp/char-wheel-marked-capture.log`，输出FIRST_DETENT_MISSING、exit1。脚本只证明标记区间输入，没有把客户端图层clear当作产品pass。设备报告层此前未启用，输出null，不能误报设备没有报告。

用户提供连接方式USB接收器，型号未提供。准备更早的IOHIDManager非独占观察：只匹配鼠标、只接收GenericDesktop Wheel值，现有listen权限允许才启用；没有设备写入/抢占，无键盘报告。CG探针改同时检查实时鼠标位置，避免轮包携带旧坐标时漏记。release构建/打包通过，普通面板诊断96816启动status0、matchedDevices3，raw taps2、marker注册0，七泡CUA可见。新标记采集边界`/tmp/char-wheel-device.capture-start.json`，仅等结束标记采集静止截图，等完成回复再分析。


## 设备报告采集与连接方式更正

最后一组标记为 begin663082.397036→heldEnd663096.013536，13.617秒内CG HID/session、App/surface/accepted均为0。非独占IOHID观察只有一个值为0的回调，没有非零Wheel值；不能把该零值计作有效刻度。设备观察匹配三个接口，未对单一物理接口身份和完整报告覆盖作验证，因此该证据不足以断言鼠标硬件故障。采集后的非零回调属于未约定操作，只用于确认探针确实能看到Wheel值，不计作这一格的及时送达。

本组结束标记被处理时用户已完成移动，未获得有效静止截图；没有把随后画面算作静止证据。上一组已捕获的标记结束后静止截图仍有效。

用户随后明确更正：之前测试实际使用**有线连接**，改为**USB接收器后没有滞后**。因此，历史采集中的连接方式应按有线解释，早先“USB接收器”回答被本次更正取代。两种方式没有严格交替复测，也未取得接收器模式的受控日志，结论为用户报告的连接模式差异，不能声称已查明固件、USB线、驱动或系统的具体责任。

当前有线模式的证据指向App滚轮入口以前的输入送达阶段。退出BetterMouse、固定鼠标路由、激活面板与独立hosting均未消除有线症状。接收器模式恢复正常不是新App补丁造成；不为有线模式添加预测滚动或重放旧事件。

## 收尾

- 移除运行时WheelDiagnostics、IOHIDManager观察、CG taps、NSEvent监控、Ctrl+Shift+9/0标记与三项窗口/绘制实验flag，恢复原非激活面板与原显示路径。
- 保留开放边缘折叠路径及二维缩放修正，以及真实图层回归 --smoke --orbit-path-check。该回归检验路径/尺寸，不冒充物理输入验收。
- 保留两个离线日志分析脚本，仅用于复查历史采集；已不附带实时采集启动脚本。analyze-marked-wheel.py区分设备零值与非零值。
- 不继续要求有线反复采集。正常包的接收器模式还需一次首格/连续/反向/轻动验证；完成后追加实机结果。有线兼容问题仍记录为未解决。


### 正常包检查

去掉探针后的源码完成 release 构建和 ad hoc 签名；严格签名验证通过。完整原生 smoke exit0，覆盖七工作端、回城、图层到达/点击、插件热插拔、五种放置与内置形象，导航仍为合成。五种放置、完整正反循环及40 ms反向接续的实际图层路径回归 exit0；二维缩放和检查器缺失/不完整动画的拒绝测试通过。日志分别为 /tmp/char-wheel-final-smoke.log、/tmp/char-wheel-final-path.log。

正常隔离实例已打开，CUA确认右边缘三个大泡及含三个小泡的折叠区、合计七工作端；无实时诊断flag，Ctrl+Shift+9/0不再注册。已按问题说明接收器复验步骤，等待用户反馈后才整理结果。未重跑无关集成和历史未运行项目，也未把图层检查当作物理滚轮通过。
