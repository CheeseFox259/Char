# Issue tracker: GitHub

项目的 issue 和规格发布到：
https://github.com/CheeseFox259/Char/issues

使用 gh CLI，所有操作显式指定 --repo CheeseFox259/Char。

- 创建：gh issue create --repo CheeseFox259/Char --title "..." --body-file <文件>
- 阅读：gh issue view <编号> --repo CheeseFox259/Char --comments
- 列表：gh issue list --repo CheeseFox259/Char，按需过滤状态和标签
- 评论：gh issue comment <编号> --repo CheeseFox259/Char --body-file <文件>
- 标签：gh issue edit <编号> --repo CheeseFox259/Char --add-label "..."
- 关闭：gh issue close <编号> --repo CheeseFox259/Char

技能要求“发布到 issue tracker”时，创建 GitHub issue。
技能要求“获取相关 ticket”时，读取对应 issue 及评论。
多行正文使用文件传入，保留实际换行。

## Pull requests as a triage surface

PRs as a request surface: no.
