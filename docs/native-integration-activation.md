# 原生集成启用清单

当前实现与实际包：`f2b5b4b`，`/Users/superhacker/Codefield/char/build/Char.app`。2026-10-04 使用者已批准三项本地配置写入，并已按下列清单执行；未调用外部模型，未退出用户应用。

## 配置写入

使用 `build/Char.app/Contents/MacOS/char-hook`，共享事件流为 `/Users/superhacker/Library/Application Support/Char/harness-hooks.jsonl`，只保存会话身份、阶段、时间和状态，不保存提示词、正文、工具参数或错误文字。现有配置保留，修改前做私有备份。

### pi

```sh
python3 integrations/pi/install.py \
  --extension-dir /Users/superhacker/.pi/agent/extensions/char \
  --hook-binary /Users/superhacker/Codefield/char/build/Char.app/Contents/MacOS/char-hook \
  --events-file '/Users/superhacker/Library/Application Support/Char/harness-hooks.jsonl'
```

只创建/更新 Char 所属扩展目录；非 Char 非空目录会拒绝覆盖。下一次 pi 启动或用户主动扩展 reload 后生效。

### Kimi CLI 和 Kimi Code App

```sh
python3 integrations/kimi/install.py \
  --settings /Users/superhacker/.kimi-code/config.toml \
  --hook-binary /Users/superhacker/Codefield/char/build/Char.app/Contents/MacOS/char-hook \
  --events-file '/Users/superhacker/Library/Application Support/Char/harness-hooks.jsonl'
```

同一原生配置服务两种工作端，由 SessionStart 的 client_type 区分。保留已有 TOML/Hook；开始或恢复会话后得到绑定，未绑定旧会话不猜工作端。

### DeepSeek Harness Desktop

在 `/Users/superhacker/.dsh/profiles/desktop/cordis.patch.yml` 的现有 patch 数组追加以下条目，其他 patch 不变：

```yaml
- insert:
    - id: char-desktop-observer
      name: /Users/superhacker/Codefield/char/integrations/deepseek/index.js
      config:
        hookBinary: /Users/superhacker/Codefield/char/build/Char.app/Contents/MacOS/char-hook
        eventsFile: /Users/superhacker/Library/Application Support/Char/harness-hooks.jsonl
```

源代码为本仓库 canonical plugin，运行时要求 Desktop native host + Electron IPC，CLI/Web/TUI 被拒绝。只写 Desktop profile，不改 DSH core 或其他 profile；需要用户安排 Desktop reload/restart 后检查实际 Host 是否加载。

## 可复查结果与剩余动作

配置验证、fixture 与 native seam 检查已经完成，详见 `acceptance-2026-10-04.md`。安装后核对三个落点、权限和幂等；运行一个用户选定的无敏感内容会话，核对恢复/轮次结束。Kimi App / DeepSeek 的实际客户端生命周期不能由配置安装替代。付费/外部模型测试仍须另行明确授权；安装本身不触发调用。

回退：从私有备份恢复 Kimi TOML 与 DSH patch；pi 仅移除 Char 所属目录（保留用户其他扩展）。安装位置与插件指纹、实际加载结果记录到验收报告。

## 安装结果

- 私有备份：`/Users/superhacker/Library/Application Support/Char/integration-backups/20261004-qpayf52v`，目录 0700、文件 0600，包含 Kimi TOML、原 DSH patch 与原路径存在性 manifest（pi Char 目录原不存在）。
- Kimi 原配置递归保留、0600；`kimi doctor config` 返回 0、stderr 为空。pi 的三文件均 0600。实际 pi/Kimi 重复安装字节无变化。
- DSH 原 patch 字节保留为前缀，Char entry 唯一；本机已安装 YAML 解析器验证追加数组与 canonical plugin 路径。源码 SHA256：`869e7e887b029aefebb3f36a907ee4241394a26cf94ba1168b0f09cd98ab3049`。实际 Host 加载仍需 Desktop reload 后的运行证据。
- 最终 Char 正常观察路径已接入实际 Claude/Codex/Kimi 数据根与共享事件流，但偏好仍在 `/tmp/char-native-profile.26pG3d` 中隔离，过滤阈值 0、声音/登录项关闭。未写正常 Char 用户偏好，也未变更登录项。临时偏好目录因运行实例依赖而保留。
- 安装刚完成时共享流尚不存在，表示没有已确认的新原生事件；不制造事件填充。下次 pi 会话/扩展 reload、Kimi 新建或恢复会话、DeepSeek Desktop reload 后才能检查实际气泡。

## 安装后用户验证

使用者随后反馈“功能正常”。共享原生流实际产生 Kimi Desktop 的 SessionStart 和 pi 的 running → turnEnded（0600）；正常 Char 的 AX 状态显示 Kimi Code Desktop 与 pi 的 Turn ended 气泡，并有应用级降级。没有注入测试元数据。Codex Desktop 的已恢复 Question 同时可见。DeepSeek 当前未获得独立原生事件记录，不能把总体反馈扩大为该客户端全生命周期通过。
