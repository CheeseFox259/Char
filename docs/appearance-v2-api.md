# Char 外观能力 API（schemaVersion 2）

适用 Char 0.3.0 起。v1包继续兼容；作者按本次需求使用可选能力，不必全部实现。此文与[基础格式](pet-skin-format.md)足以开发，无需阅读宿主源码。确定SDK版本后，在独立工作区制作资源，宿主源码保持只读。

## 清单与解析顺序

保留 `schemaVersion/id/name/canvasSize/anchor/clips/appIcon`，将版本设为2，新增可选 `features`。七个基础动作仍必需；可添加英文标识命名动作（字母开头，后续字母/数字，共1–40字符）。所有逐帧动作都匹配基础画布；每组2–120帧、1–60fps。

`features`字段：`variants`、`themes`、`defaultTheme`、`tracking`、`bubbles`、`sounds`、`bindings`、`behavior`、`hitRegions`、`script`、`loopingClips`。未知字段报错。路径均为安全相对路径；禁止绝对路径、反斜杠、空段、`.`、`..`及符号链接。

解析顺序：基础 → `features.variants[placement]` → 当前主题 → 主题的边缘变体。clips按动作名合并；anchor/rotation/mirrorX仅在显式出现时覆盖；tracking和bubbles整个对象替换。placement为desktop/left/right/top/bottom。变体中的anchor对idle、反馈和迁移全部有效；不要为了绕过宿主问题挤压所有姿态。

```json
{
  "variants": {
    "top": {"rotation": 0, "anchor": {"x": 0.5, "y": 0.25}, "clips": {"idle": {"fps": 12, "frames": ["top/a.png", "top/b.png"]}}},
    "left": {"mirrorX": true}
  },
  "themes": {
    "day": {"name": "日间"},
    "night": {"name": "夜间", "clips": {"idle": {"fps": 12, "frames": ["night/a.png", "night/b.png"]}}, "appIcon": "night/icon.png"}
  },
  "defaultTheme": "day"
}
```

上例是features片段；每条路径必须有真实资源。通用底边创作仍自动转向四边；独立上边缘造型用rotation=0保持作者方向，或指定−360…360度；mirrorX围绕anchor镜像。每边可分别覆盖七组及额外动作。theme ID小写字母开头，后续小写字母/数字/短横线，最多40字符；名称1–80字符，最多12主题。主题可提供clips、variants、tracking、bubbles、appIcon；选择及重启持久保存当前主题；“基础”使用无主题资源，setTheme的value空字符串可选基础。

## 鼠标跟随与分层

tracking使用透明PNG叠加在基础帧上。基础图需移除要独立移动的眼睛/头部，避免双影。所有rect与hitRegions均为**完整画布左上角归一化坐标**：x/y≥0，width/height>0，范围不超出1。shape可省略或为rect/ellipse。

```json
{"tracking": {
  "head": {"rect": {"x": 0.15, "y": 0.1, "width": 0.7, "height": 0.6}, "poses": {"center": "head/center.png", "e": "head/e.png", "w": "head/w.png"}},
  "eyes": [{"image": "eyes/pupils.png", "rect": {"x": 0.3, "y": 0.35, "width": 0.4, "height": 0.12}, "travelX": 0.025, "travelY": 0.02}]
}}
```

head最多9方向：center必需，n/ne/e/se/s/sw/w/nw可选；缺方向用center。方向阈值为归一化gaze的±0.25。eyes最多8层；travelX/travelY为画布比例，0…0.15，默认0.025。PNG叠加层独立尺寸32…1024，rect决定显示区域。宿主将屏幕方向转回当前边缘和镜像的作者坐标；平滑gaze并量化缓存，停住鼠标不重复重绘。Reduce Motion暂停帧动画，保持静态跟随，不做夸张缩放。

## 气泡皮肤

bubbles仅改变外观，Agent身份图标仍由集成插件提供。主题可替换bubbles。

| 字段 | 类型 / 范围 / 默认 |
| --- | --- |
| shell | 透明PNG路径，完整44pt气泡底层；中间留透明空间给Agent图标 |
| cliBadge | PNG路径，替换终端标记图案（标准小角标区域） |
| statusColors | pending/running/issue/interaction/ended → `#RRGGBB`或`#RRGGBBAA`；缺项用宿主默认 |
| fontName / fontSize | 已安装字体PostScript名≤80字符；不存在时回退系统字体；字号8…14，默认10 |
| hoverColor / hoverGlow | 轮廓色 / 白色边缘光透明度0…0.5，默认0.16；光仅沿边缘 |
| hoverAmplitude / hoverDuration | 0…0.2 / 0.4…4秒；默认压缩拉伸0.075、周期1.6s；普通气泡和高亮区别明确 |
| shatterDivisions | 1…4；默认3，生成N×N块 |
| shatterDuration / shatterTravel | 0.15…1秒 / 0…40pt；默认0.4s、17pt |
| orbitDuration / orbitCurve | 0.12…0.7秒 / smooth或spring；默认0.24s、smooth；位置/大小/折叠泡同步 |

图片有效不代表图标清晰；在黑白背景、大小气泡、CLI/Desktop和每种状态实际预览。host的裁切、状态语义及Agent图标不会被主题替换。

## 音效与事件

sounds是音效ID→对象。`file`为wav/aiff/m4a，单文件≤8MiB、可解码且0–30秒；volume=0…1（默认1），cooldown=0.1…60秒（默认0.3）。音效ID与事件名一致时自动播放；其他ID用playSound。全局静音优先，切换形象停止旧音效，不允许播放包外文件。

```json
{"sounds":{"click":{"file":"audio/click.wav","volume":0.4,"cooldown":0.3}},
 "bindings":{"hoverEnter":[{"type":"playClip","value":"greet"}], "return":[{"type":"playSound","value":"click"}]}}
```

事件：select、theme、hoverEnter、hoverLeave、dragStart、dragEnd、click、attention、return、placement。鼠标进入/离开只各发一次，不按动画帧触发。事件对象：name、placement、theme、hold（字符串true/false）；可选workEnd（插件工作端标识）、state。click/hover中的state=pet或bubble（气泡悬停带workEnd）；attention的state为running、pending或原生StopReason标识（如turnEnded、approval、failure等，仅对监控确实提供的状态）。不含消息正文、网页内容、凭证或来源token。

bindings按事件名提供动作数组，每次最多16动作。playClip可播放额外命名动作；idle以及loopingClips中的动作循环，其他播放一次后恢复idle。迁移中宿主动作优先；新playClip替换旧动作，playClip idle可结束表情循环；当前姿态未声明的额外动作忽略。

## 脚本接口

`script`是包内UTF-8 .js，≤128KiB。导入时用户确认启用；选中时启动一个随应用打包的JavaScriptCore helper，无Node依赖。切换/删除停止旧helper。只支持同步`onEvent(event)`，返回动作数组；可在JS中保留状态。没有require、fetch、process、ObjC、文件、网络或命令接口。进程隔离不是OS权限沙箱；不加载第三方原生动态库。

```js
let lastState = "";
function onEvent(event) {
  if (event.name === "attention" && event.state !== lastState) {
    lastState = event.state;
    return [{type: "playClip", value: "react"}];
  }
  return [];
}
```

react要在本包声明。不要用异步Promise、setTimeout或忙循环。每次请求含初始化最多0.5秒，超时/异常/无效动作会停止脚本并显示设置错误；不阻塞UI。单个事件从开始处理到结束（含首次初始化）≤0.5秒；事件回包≤32KiB、≤16动作，队列≤32条；过载停止脚本并显示错误。脚本引发的主题/位置等动作不递归重新发给脚本或bindings，避免反馈循环。没有逐帧脚本回调，跟随和高频动画通过原生字段实现。

| 动作 | 参数 | 实际效果 |
| --- | --- | --- |
| playClip | value=本包动作名 | 播放表情/动作 |
| setTheme | value=本包主题ID或空字符串（基础） | 热切资源/图标，持久保存主题 |
| playSound | value=本包音效ID | 遵守静音和冷却 |
| setPlacement | value=五种placement | 使用宿主弹性迁移 |
| returnHome / endHold | 无参数 | 执行已保存回城 / 清除锚点 |
| showSettings | 无参数 | 打开设置 |
| visitAgent / ignoreAgent | value=已有workEnd | 查看 / 忽略该工作端的当前项目 |
| cycleBubbles | steps=-1或1 | 有折叠时轮换，否则无操作 |

value和steps不用的字段不得提供。动作沿用宿主公共首次锚点、导航精度与失败处理，不自行实现监控协议或向外部应用发送消息。

## 交互、窗口与布局偏好

behavior可选字段：

| 字段 | 可用值 / 默认 |
| --- | --- |
| click | default、settings、return、none；默认原点击/回城 |
| bubbleClick | visit、ignore、none；默认visit |
| returnPolicy | user、original、latest、disabled；默认使用用户设置 |
| followFocus | true/false；默认跟随工作焦点 |
| edgeSnapDistance | 0…100pt；默认64，0禁用拖放吸边 |
| collision | clamp/free；默认free；clamp拖拽时角色保持在当前显示器可见区域，free允许拖越边界；落位仍遵循屏幕可见范围 |
| bubbleDistance | 8…72pt；默认用户距离 |
| bubbleCapacity | 3…20，进一步限制几何可容纳数量；不会强行塞入重叠气泡 |
| bubbleArcDegrees | 边缘弧跨度60…140度；默认140 |
| bubbleStartDegrees / bubbleClockwise | 桌面环起点−360…360度 / 顺序方向；默认90/false（保持旧版顺序） |

设置中的“使用形象行为偏好”可关闭这些默认行为并回到用户原偏好；不会改写用户距离、回城策略或位置偏好。脚本和事件绑定仍按包定义运行。自行用click事件执行导航或设置时，将对应click/bubbleClick设为none，避免同时执行默认点击动作。hitRegions最多16个rect/ellipse，决定宠物点击/拖拽区域；气泡采用标准圆形点击区，透明空白不会阻挡其他App。锚点、旋转和镜像应用于命中换算。当前不提供任意窗口层级、系统Space曲线或外部应用命令。

## 安装图标与预算

选中形象/切换主题时自动同步运行和安装图标。当前公开发行的ad hoc App在可写安装目录中：保留原Release备份→暂存副本→写ICNS与CFBundleIconFile→重新签名→严格验证→事务替换→注册LaunchServices。默认形象恢复原图标；只有一个安装App。失败时保留原安装并在设置显示原因。更新Release会替换本机图标变体，启动后重新应用选中形象。签名身份变化可能需要重新添加辅助功能授权；Developer ID安装不自动改签名。Finder/Launchpad缓存呈现还需用户实际确认。

不能用Finder资源叉图标修改signed App；[Apple QA1940](https://developer.apple.com/library/archive/qa/qa1940/_index.html)说明签名禁止这类扩展属性；本方案修改资源后重签，遵守[Apple TN2206](https://developer.apple.com/library/archive/technotes/tn2206/)的资源封存规则。

v2：manifest≤128KiB，包≤64MiB，目录项≤2200，动作引用总数≤2048；PNG≤4MiB，帧32…512，其他PNG32…1024；appIcon及主题图标正方形128/256/512/1024；所有**唯一PNG总像素仍≤16,777,216**。理论裸RGBA上限64MiB，不代表RSS。包仅含引用的PNG、音效、单个JS及manifest；小型Finder .DS_Store元数据忽略，作者导出仍应排除。v1预算不变。

性能：主题/姿态/图片缓存；眼睛量化重绘；无脚本帧事件；无能力无helper；单脚本常驻、串行有界消息；音效按需缓存并冷却；安装图标只在选择变化时事务更新。不要为一个角色新建完整监控或物理引擎。

## 可运行的机制样本

```sh
python3 /absolute/Char/scripts/make-appearance-fixture.py /absolute/work/sdk-demo.charpet
swift run --package-path /absolute/Char char-package-check skin /absolute/work/sdk-demo.charpet
```

此样本是中性形状的可运行API练习，含跟随、主题、边缘、皮肤、音效和脚本，不是用户的具体造型方案。开发时只借用契约；按用户素材创作，不把示范外形当交付。用户最终用设置导入，无需命令。
