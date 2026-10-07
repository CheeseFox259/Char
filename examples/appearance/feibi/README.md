# 菲比 · 可导入的形象开发示例

ID `feibi.pet`，v2 形象包，适用本次更新后的 Char 1.0.0（早期 1.0.0 安装尚不接受 MP3 形象资源）；128×128 RGBA，24 fps，七种动作、独立 512×512 软件图标与点击音效。

![闲置动作](../../../docs/assets/feibi-idle.webp)

## 使用

在 Char **设置 → 桌宠与动效 → 导入形象…** 选择整个 [packages/feibi.charpet](packages/feibi.charpet) 目录。无需构建或安装依赖。默认方块形象仍可随时选择；同 ID 形象更新先删除旧包再导入。

四边落位由宿主保持正确朝向。此示例采用预设眨眼和弹性动作，不声明实时独立眼睛跟随、脚本或气泡主题；更完整的能力见 [v2 API](../../../docs/appearance-v2-api.md)。

点击桌宠或气泡时播放菲比音效，音量 55%，同一音效冷却 4 秒；关闭 Char 音效后不播放，切换形象会停止旧音效。已有旧菲比包需先删除，再导入本包；重装 Char 不会覆盖用户已导入的私有副本。仅更新这项时可按 [音效使用步骤](USER-ACCEPTANCE.md)操作。

## 重建

需要 Python 3、Pillow、NumPy，依赖安装在独立环境。从任意目录调用生成脚本均可；以下在仓库根运行：

```sh
python3 -m venv build/feibi-venv
build/feibi-venv/bin/pip install -r examples/appearance/feibi/requirements.txt
PYTHON="$PWD/build/feibi-venv/bin/python" sh examples/appearance/feibi/generator/make.sh
```

`reference/` 保存制作输入，`art/` 是绘画层与 rig，`audio/` 保存原 MP3 和上游许可。`generator/` 依次生成七组动作、图标与可导入包，并调用生产校验器。生成预览与本地审计放在忽略目录；发布仅包含运行资源及相邻素材许可说明。重建直接复制原 MP3，不额外转码。

105 个唯一 128×128 帧与 512×512 图标约需 7.56 MiB 原始 RGBA 像素空间；该估算不等于 Char 的 RSS。

## 资源来源

参考形象由项目使用者提供，示例通过抠像、表情图层与仿射动画制作。音效来自 [Genius-Society/phoebe_chubby](https://github.com/Genius-Society/phoebe_chubby)，保留 CC BY-NC-SA 4.0 许可，原样提供 MP3，未剪辑或转码声音。角色形象与相关权利归原权利人；项目 MIT 许可证适用于代码，不授予角色、音效或第三方商标的权利。详见 [素材说明](ASSET-NOTICES.md)。
