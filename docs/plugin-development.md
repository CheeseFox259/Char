# 集成插件开发指南

适用于当前 macOS 实现。先选择扩展方式，再使用[完整开发提示词](development-prompts.md)。

## 1. 选择扩展方式

| 目标 | 当前可直接导入吗 | 实现入口 |
| --- | --- | --- |
| 换已有工作端的目标应用、名称或图标 | 可以，配置包 | .charintegration |
| 为已有 Tabbit / VS Code 准确适配器提供配置 | 可以，仍依赖原生授权/桥接 | .charintegration |
| 为任意应用添加应用级回城配置 | 可以，但未安装插件也支持这种回城 | .charintegration |
| 接入新的 Agent 事件协议 | 不可以只改 JSON，需要源码贡献 | WorkEnd、观察器、Hook、测试 |
| 新增浏览器/编辑器的准确返回能力 | 需要源码贡献及该应用可靠接口 | ReturnAdapter、平台适配器、生命周期测试 |

**配置插件不执行代码、不安装 Hook、不加载动态库。** Char 不支持把任意 JS/Python 放入包中获得新观察能力。Agent 自身的原生扩展（例如 pi、DeepSeek）与 Char 的配置包是两个不同安装环节。

插件列表中的铃铛表示提醒，准星表示已配置准确回城能力，窗口表示应用级回城。准星不表示当前已授权或目标必然可用；状态页和实际导航结果仍决定是否能准确返回。

## 2. 最小可用配置包

在仓库根目录执行，所有命令只写工作目录，不安装用户配置：

~~~sh
mkdir -p build/personal-safari.charintegration
cat > build/personal-safari.charintegration/manifest.json <<'JSON'
{
  "schemaVersion": 2,
  "id": "personal.safari",
  "name": "Safari",
  "bundleIdentifier": "com.apple.Safari",
  "returnAdapter": "application"
}
JSON
swift run char-package-check integration build/personal-safari.charintegration
~~~

预期输出包含 VALID integration: personal.safari，退出码0。这是完整有效的无图标包，不需要制造任何资源文件。从设置 → 插件 → 导入插件，选择该目录。应用级回城无需额外插件，示例用于学习导入与生命周期。

已有 Codex CLI 改用 Terminal 的完整清单如下：

~~~json
{
  "schemaVersion": 2,
  "id": "personal.codex-terminal",
  "name": "Codex CLI in Terminal",
  "workEnd": "codexCLI",
  "bundleIdentifier": "com.apple.Terminal"
}
~~~

将清单存为另一 .charintegration 目录中的 manifest.json 后校验。导入前关闭现有 Codex CLI 插件，或移除同工作端配置，否则“同一工作端只能有一个启用插件”的检查会拒绝导入。这只改变访问的目标应用；CLI 日志仍由原有 Codex 观察器处理，**不会获得 Terminal tab 的精准导航**。

应用 bundle ID 可在目标 .app 的 Contents/Info.plist 中查看 CFBundleIdentifier；不要从名称猜测。例如只读命令：

~~~sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /System/Applications/Utilities/Terminal.app/Contents/Info.plist
~~~

## 3. 清单与资源规则

完整字段见[格式契约](integration-plugin-format.md)，生产实现是 [IntegrationPlugins.swift](../Sources/CharCore/IntegrationPlugins.swift)。

- schemaVersion 使用2；id 为唯一的1–128位 ASCII 字母/数字/点/下划线/短横线，首位必须字母或数字；name 去空白后非空且不超过100字符。
- bundleIdentifier 必须是合法的点分应用标识；workEnd 只能为 claudeCode、codexCLI、codexDesktop、deepseekDesktop、kimiCLI、kimiDesktop、pi。
- 至少指定 workEnd 或 returnAdapter 一项。returnAdapter 仅支持 application、tabbit、vscode。
- tabbit 必须对应 com.tabbit-ai.Tabbit，vscode 必须对应 com.microsoft.VSCode；两者不能用来配置其他浏览器/编辑器。
- icon 可省略；如指定，文件必须存在于包内，是可解码的 PNG，宽高均不超过2048。使用 assets/icon.png 等相对路径，不用绝对路径或路径穿越；建议128/256像素正方形透明图标，保留官方图形比例。
- 整包不超过8 MiB，包根及任何内容不能是符号链接。开发说明、安装器和源码放在包外；运行时不加载包内代码。

同一工作端不能有两个启用配置，同一应用不能有两个启用的准确适配器。多个 CLI 配置可以共享同一 Terminal/Warp 应用。id 重复时，即使旧包停用也不能再次导入；更新请删除旧包后重新导入。应用级起点不按插件列表划分 Agent/普通应用。

## 4. 校验、安装和回退

~~~sh
swift run char-package-check integration build/personal-safari.charintegration
bash scripts/check.sh
bash scripts/build-app.sh
~~~

char-package-check 通过**生产导入器**将包复制到临时注册表，退出时清理，只关闭这个临时目录内的默认插件；不访问用户注册表。退出码：0有效、1包无效、2命令格式不正确。用户实际目录的重名与能力冲突仍由设置导入检查。校验通过不证明原生 Hook 已启用、应用存在或准确返回获授权。

设置导入会复制包，热更新启用观察集合并清空已停用工作端的提醒。重新启用以新活动为起点，不重播停用期间旧事件。更改已安装 manifest 不受支持：移除后重新导入。删除内置插件的记录会保留，重启不复活；“恢复已删除的内置插件”是显式操作，冲突能力恢复为停用。

停用提醒不取消仍存活的应用级返回锚点；移除其依赖的准确适配器会结束准确 Hold。删除 Char 配置**不卸载原生客户端 Hook**，按 [pi](../integrations/pi/README.md)、[Kimi](../integrations/kimi/README.md)、[DeepSeek](../integrations/deepseek/README.md) 的独立文档回退。

## 5. 新增 Agent 协议的源码路径

1. 确认客户端提供可靠的原生状态事件/追加日志，查证根会话和桌面/CLI身份。列出支持与缺失的原因，不能用回答文本或沉默时间猜测失败/轮次结束。
2. 在 [Models.swift](../Sources/CharCore/Models.swift) 增加工作端及 [CompanionPanel.swift 中的 WorkEnd 展示分支](../Sources/CharApp/CompanionPanel.swift) 等所有穷举分支；检索 WorkEnd.allCases 和 switch，处理默认配置、图标、CLI角标、几何容量、fixture。
3. 在 [CharObservations](../Sources/CharObservations) 加分类器与本地读取路径，或在 [CharHook](../Sources/CharHook/main.swift) 增加明确模式与原生扩展。不要用现有工作端冒充新协议。
4. 转成 ObservationEvent：稳定 SessionKey、原生时间、running/stopped/closed、target、isChild。由 Swift JSONEncoder 写日期/枚举；Date 默认是自2001-01-01起秒数，不能把 Unix 秒直接填入现有 Hook 流。现有 Kimi 元数据是另一个 typed envelope，勿混写格式。
5. 以 EOF 建立启动/重新启用基线；只处理完整追加行，覆盖半行、截短、文件替换、乱序、重复、旧关闭水位、子会话和配置代次。
6. 原生脚本独立安装、明确保存备份和卸载步骤。发出的记录只携带必要状态元数据，不复制 prompt/消息正文，不调用模型完成“测试”。
7. 在 [Tests](../Tests) 与该集成目录加入能抓住实际协议错误的检查。新增停顿类别同时更新信号矩阵；运行 scripts/check.sh，再在用户批准的原生客户端做对应事件验收。

## 6. 新增准确回城适配器

参考 [Platform.swift](../Sources/CharPlatform/Platform.swift)、[TabbitAppleScript.swift](../Sources/CharPlatform/TabbitAppleScript.swift)、[VSCodeSocketBridge.swift](../Sources/CharPlatform/VSCodeSocketBridge.swift)。

需要捕获不可歧义的原窗口/标签 token、验证存活、聚焦并确认当前 token。区分“确定关闭”与“查询失败”：前者使锚点失效，后者保留重试。绑定原进程，保留首次锚点；只激活应用必须返回 fallback，不能标为 exact 或清除未查看项。新增枚举值、清单校验、平台捕获/返回/匹配和删除适配器行为必须一起完成。权限请求必须通过显式用户操作。
