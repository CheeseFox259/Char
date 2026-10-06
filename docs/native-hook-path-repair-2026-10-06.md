# Kimi CLI/App 与 DeepSeek Desktop 监控修复

日期：2026-10-06。使用者报告三个工作端不能正常监控。此前对三项本地集成的安装授权继续适用，本次只修复 Char 相关条目并保留其他配置。

## 原因与复现

Kimi 的四个 Char Hook 命令与 DeepSeek Desktop 的 Char observer 配置仍指向已不存在的 `build/Char.app/Contents/MacOS/char-hook`。正式 v0.1.2 Release 安装于 `/Applications/Char.app`；应用更新不会改写客户端的外部集成配置。

用实际安装的 Kimi SessionStart 命令，分别派发 CLI/App 元数据到临时事件目录，均返回 `ENOENT`，没有客户端绑定。用实际 Desktop patch 的 Hook 路径通过 canonical DeepSeek observer 派发 running/turn-ended，同样启动失败且没有事件。没有向真实观察流注入 fixture。

另一个可复现问题：旧 Kimi 安装器重装时仅检查新命令是否存在，产生八个 Char Hook（四个失效旧命令 + 四个新命令），而不是迁移原四个。

## 修复

- 私有 ZIP 备份保存在忽略目录 `build/native-hook-diagnosis/backups/`，权限 0600；包含修改前完整 Kimi TOML 与 Desktop patch。
- 本机 Kimi 的四个 Char 命令原位改为正式 Release Hook 路径。配置审计确认其他设置、Hook、顺序和事件参数保持不变。
- 本机 Desktop patch 仅替换唯一 Char entry 的 `hookBinary`；其他字节全部保留。没有重启用户的 Desktop 或改动长期会话。
- Kimi 安装器新增旧路径迁移：仅识别自己生成的三 token `CHAR_HOOK_EVENTS=… /absolute/char-hook --kimi` 命令，在对应事件表中替换 command；不改其他 Hook。重复运行保持字节幂等。
- 两项 README 说明稳定 Release 路径和重新加载步骤。DeepSeek 插件源码无变化，仍是 canonical `integrations/deepseek/index.js`，SHA256 `869e7e887b029aefebb3f36a907ee4241394a26cf94ba1168b0f09cd98ab3049`。

## 已验证

| 层级 | 实际证据 |
| --- | --- |
| L1 回归 | 旧安装器迁移产生 8 个 Hook 的检查失败；修复后保留 4 个 Char Hook，通过重复安装和同事件用户 Hook 保留检查 |
| L2 写入 | 同一实际配置复现脚本修复后通过：Kimi CLI/App 各写出正确工作端绑定；DeepSeek canonical observer 经正式 Release writer 写出事件 |
| 配置 | `kimi doctor config` 返回正常；本机 native YAML 解析器确认 Desktop patch 有且只有一个 Char entry、canonical source 有效 |
| 回归 | `python3 Tests/check_new_agent_hooks.py /Applications/Char.app/Contents/MacOS/char-hook`、DeepSeek 3 项插件检查、`bash scripts/check.sh`、`git diff --check` 通过 |
| 保留审计 | 修改前 ZIP 与修改后文件比对：仅四个 Kimi command 和一个 DeepSeek hookBinary 变化；用户其他配置完全保留 |

## 实际客户端验收

已请求使用者让 Kimi CLI 重新启动/恢复会话、Kimi App 新建/恢复会话，并由使用者安排 DeepSeek Desktop reload/restart，在现有工作自然结束一轮时确认气泡。修复后的静态配置和 writer 已通过，但运行中的客户端是否加载新配置、真实提醒是否出现，尚待使用者结果；不能把 fixture 写入当作实机全流程通过。

DeepSeek 当前运行的 Host entry 仍符合原插件所要求的 `@deepseek-ai/dsh-desktop-host/lib/index.js` 后缀。DSH 源码只读基线为 `00102833dfaee1da9f48a3a8eae9d34005a75218`，已有 62 个变更路径，本任务没有修改 DSH core。未把工作目录与已安装 app.asar 宣称为同一构建；本次没有更换插件 source 或 Host artifact。

浏览器 UI 为 N/A（此观察插件没有 UI）。未发起外部模型请求，未操作用户终端或退出工作会话。Char app 源码与已签名包未变，不需要重建、安装或发布新 app。当前状态：配置和本地验收通过，实际客户端重新加载及自然轮次验收为 USER_RUN_REQUIRED。

## 使用者确认

使用者测试后反馈已正常，并要求说明跳转与监控原理。本次三个工作端的基础监控恢复已获用户确认；不扩大为所有提问、审批、异常、限流、关闭类别都已逐项实机验收。前述 USER_RUN_REQUIRED 是该反馈到达前的状态。
