# macOS 安装与发布

Char v1.0.0 提供 macOS 13+ Universal 应用，包含 Apple Silicon 与 Intel 架构。日常安装直接使用 [GitHub Release](https://github.com/CheeseFox259/Char/releases/latest)，无需 Swift、Node 或本地构建。

## 安装

1. 下载 DMG，将 Char.app 拖到“应用程序”；或者解压 ZIP，将应用复制到 `/Applications/Char.app`。
2. 首次打开可能被系统拦截。macOS 版本目前未经过 Apple 公证，首次启动可能需要在 Finder 中右键应用并选择“打开”。若系统仍拦截，打开系统设置 → 隐私与安全性，在 Char 的提示旁选择“仍要打开”。[Apple 操作说明](https://support.apple.com/guide/mac-help/mh40616/mac)。
3. 从状态栏或桌宠右键菜单打开设置，选择语言、放置方式与提醒偏好。插件维护菜单按需安装客户端集成；安装 Char 不会自动改写客户端配置。
4. 更新前退出旧实例，用新应用替换 `/Applications/Char.app`。配置保存在用户 Application Support/Char，不在安装包内。

发行包采用 **ad hoc 签名，未 Developer ID 签名、未 Apple 公证**。严格签名校验用于检测打包完整性，不等于 Apple 已认可开发者。

## 权限与图标

- 辅助功能：在系统设置 → 隐私与安全性 → 辅助功能中添加 `/Applications/Char.app`。用于更可靠的焦点窗口识别；无权限时跨屏跟随使用窗口几何回退。
- Tabbit Automation：在 Char 设置中主动授权；应用级回城不要求自动化。精准返回仅读取对象标识、验证并聚焦，不读取网页正文。
- 形象安装图标同步会对可写的 ad hoc 安装包备份、重签并事务替换，可能影响辅助功能信任。若系统已授权但 Char 仍显示未授权，只移除并重新添加 Char 这一条记录。
- “登录时启动”显示实际 ServiceManagement 状态；应在应用程序目录内运行并从设置启用。

## 自定义示例

Release 的 `Char-1.0.0-examples.zip` 包含 MiniMax CLI、Desktop 与菲比；解压后从设置导入整个 `.charintegration` 或 `.charpet` 目录。示例也随 App 放在 `Contents/Resources/Examples`，源码见仓库对应目录。安装不会自动启用示例、运行其代码或安装客户端 Hook。

## 校验与重建

Release 同时提供 `SHA256SUMS`。开发者可以验证：

```sh
shasum -a 256 -c SHA256SUMS
```

构建需要 macOS、Swift 6 / Command Line Tools、Node 与 Python 3；Node 只用于开发检查与部分可选集成，并非 Char 核心运行依赖。

```sh
bash integrations/minimax-code/native-adapter/build.sh
node integrations/minimax-code/build-packages.mjs
bash scripts/check.sh
bash scripts/package-release.sh
```

产物在 `build/release/1.0.0/`。tag 触发 GitHub Actions，执行检查、Universal 构建、ZIP/DMG/示例校验后创建草稿；下载最终附件复验后才公开发布。Intel 架构构建与静态检查不替代 Intel 实机验收。
