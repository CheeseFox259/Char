# 设置图标、开发文档与Windows评估验收

比较点 fec48bd。范围：插件能力图标、删除旧工作端图例、开发指南/完整提示词、包校验工具、当前机制/性能索引、Windows静态可行性评估。沿用feat/char-v1与PR #2。

## Verified

- 插件列表将“提醒·应用级回城 / 准确回城”行文本改成bell.fill、macwindow、scope。固定图标槽位对齐，保留help和accessibilityLabel。准确能力说明明确依赖集成与授权。
- CUA实际打开release包的隔离演示设置，滚动检查完整插件列表：七观察工作端显示铃铛+窗口；Tabbit/VS Code显示准星；WeChat显示窗口。行中没有能力文字，AX树有每个图标的语义说明。开关和删除按钮保持可见。
- 继续滚动到Graphical legend，确认旧Claude/Codex/Kimi/pi工作端符号表已删除，当前三组状态、CLI标记、已恢复和导航反馈说明保留。
- bash scripts/check.sh exit0：现有核心、观察、平台、Hook、VS Code、pi、Kimi、DeepSeek检查。
- bash scripts/build-app.sh release构建及本地签名成功；codesign --verify --deep --strict --verbose=2 build/Char.app通过；git diff --check通过。
- 新char-package-check调用生产校验：版本2Safari包、Codex CLI in Terminal包、仓库Safari包与完整七动画example.charpet均exit0。未知workEnd和fps61形象拒绝exit1，错误命令参数exit2。全部写入临时目录，不修改用户插件/皮肤数据。
- 两份格式页与README的来源/导入行为按当前源码修正。新增指南、三份完整提示词、架构/性能摘要、文档索引；本地Markdown链接经脚本检查。
- Windows评估检查了Swift、Win32窗口/焦点/热键/虚拟桌面/DPI/托盘、WSL和Warp官方资料，列出源码阻断与原型路线。源码事实与工程建议分开，包含直接来源链接。

日志：/tmp/char-developer-docs-check.log、/tmp/char-developer-docs-build.log。GUI检查通过CUA，仅操作Char隔离演示，不修改其他App或系统设置。

## Failed

完整原生 --smoke 两次exit1，均为“Space notification arrival feedback”，第一次日志 /tmp/char-developer-docs-smoke.log，确认设置可见/解锁后复跑日志 /tmp/char-developer-docs-smoke-retry.log。本轮没有修改Space生命周期、动画或相应断言；不能据此宣称原因已知，也不能以其他检查替代这个完整smoke。按用户先前接受的Space范围，本轮保留失败记录，不扩大到Space重做，PR保留草稿。

## Not run / Not applicable

- Windows编译、实机、Windows性能、客户端发行兼容性与精确返回：未运行；当前交付是可行性评估。
- 本次图标修改后的新CPU/GPU采样：未运行；性能摘要引用有明确版本/场景的历史实测，不冒充当前新基准。
- 完整VoiceOver与深色主题：未运行；AX语义、当前主题实图已检查。
- 提示词制作出的新自定义角色与新增Agent：不适用。本次交付指南和可执行验收路径，未请求制作新角色/新协议。
- 用户Hook安装、系统授权、模型调用、远端合并/发布安装器：不适用。已有安装与历史未运行项保留在原报告。

## Delivery

开发者从 docs/README.md 进入，配置包与数据形象包格式仍保持兼容。新增Agent或准确返回需要源码扩展，不声称任意代码插件已实现。推送目标为CheeseFox259/Char的feat/char-v1，现有PR #2继续承载当前版本；没有合并默认分支或发布正式二进制。


云端状态：本地实现提交428b1ea已完成；推送失败，Git无法获取有效凭据，gh auth status确认当前凭据无效，API返回401。已请求用户重新登录后继续推送/更新PR；在确认远端成功前不记为云端已交付。
