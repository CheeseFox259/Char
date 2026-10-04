# 实体鼠标滚轮滞后与反向运动诊断

本轮沿用用户要求：先以问题说明采集时间与步骤，用户回复完成后才分析；App 操作提前说明。当前仍在诊断，未将整体滞后标为解决。

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
