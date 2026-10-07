# 菲比 · 可导入的形象开发示例

ID `feibi.pet`，v1 图片形象包；128×128 RGBA，24 fps，七种动作、独立 512×512 软件图标。

![闲置动作](../../../docs/assets/feibi-idle.webp)

## 使用

在 Char **设置 → 桌宠与动效 → 导入形象…** 选择整个 [packages/feibi.charpet](packages/feibi.charpet) 目录。无需构建或安装依赖。默认方块形象仍可随时选择；同 ID 形象更新先删除旧包再导入。

四边落位由宿主保持正确朝向。此示例采用预设眨眼和弹性动作，不声明实时独立眼睛跟随、脚本、音效或气泡主题；更完整的能力见 [v2 API](../../../docs/appearance-v2-api.md)。

## 重建

需要 Python 3、Pillow、NumPy。在仓库根运行：

```sh
python3 -m pip install Pillow numpy
sh examples/appearance/feibi/generator/make.sh
```

`reference/` 保存制作输入，`art/` 是绘画层与 rig，`generator/` 依次生成七组动作、图标与可导入包，并调用生产校验器。生成预览与本地审计放在忽略目录；发布仅包含运行资源。

105 个唯一 128×128 帧与 512×512 图标约需 7.56 MiB 原始 RGBA 像素空间；该估算不等于 Char 的 RSS。

## 资源来源

参考形象由项目使用者提供，示例通过抠像、表情图层与仿射动画制作。角色形象与相关权利归原权利人；项目 MIT 许可证适用于代码，不授予角色或第三方商标的权利。替换成自己的素材后可以复用生成流程。
