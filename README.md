# 在 Neovim 中使用 OpenCode 的 Mermaid 排版引擎

[English](README.en.md) | 简体中文

这个本地试用插件复用 OpenCode 的 merman 解析、布局和字符网格代码，另有新增的 classDiagram 适配层。默认按编辑模式切换源码和图表，也保留浮窗和分屏预览。iTerm2 只需显示 Unicode 文字，不需要图片协议。

本次已用你提供的完整图表验证。120 列目标宽度下的布局与第一张截图基本一致；80、100 列下会采用不同布局。更换窗口宽度、字体或 OpenCode 引擎版本后，结果可能变化。

## 安装

源码/图表切换模式需要 Neovim 0.11+、Node.js 20+。浮窗、分屏及旧的追加行内模式仍支持 Neovim 0.10；旧版本会回退到追加显示。ZIP 中已经包含编译后的 JavaScript，不需要 npm install、Bun、mmdc 或 ImageMagick。

下载并解压 `merman-preview.nvim.zip`，将其中整个 `merman-preview.nvim` 文件夹放到：

```text
<Neovim 配置目录>/local/merman-preview.nvim
```

在 Neovim 中运行 `:echo stdpath("config")` 可以查看配置目录。确认 `bin/render.mjs` 位于上述插件文件夹内，避免多套一层目录。

新建 `lua/plugins/merman-preview.lua`：

```lua
return {
  { "toboriak/ascii-mermaid.nvim", enabled = false },
  { "kais-radwan/ascii-mermaid", enabled = false },
  {
    dir = vim.fn.stdpath("config") .. "/local/merman-preview.nvim",
    name = "merman-preview.nvim",
    main = "merman_preview",
    ft = { "markdown" },
    cmd = { "MermanPreview", "MermanSplit", "MermanInline", "MermanRender", "MermanClear" },
    opts = {
      max_width = 120,
      timeout = 10000,
      inline = {
        enabled = true,
        mode = "hybrid",
        debounce_ms = 400,
      },
    },
    keys = {
      {
        "<leader>cM",
        "<cmd>MermanPreview<cr>",
        ft = { "markdown", "mermaid" },
        desc = "Mermaid Preview (Merman)",
      },
    },
  },
}
```

重启 Neovim 后，Markdown 中完整的 `mermaid` 代码块采用以下交互：

- Normal 模式：隐藏源码，显示彩色字符图，与光标是否位于代码块内无关。
- Insert 模式：显示源码，隐藏图表。
- Visual 模式：显示源码，隐藏图表，包括字符选择、行选择和块选择。
- 按 Esc 返回 Normal 模式后恢复图表。Replace 和 Select 模式也按编辑状态显示源码。
- 编辑后延迟 400ms 自动刷新；模式切换只使用缓存，不重复启动渲染器。
- 解析失败时保留源码并显示错误，避免隐藏无法渲染的内容。

模式切换同时作用于当前文档中的全部 Mermaid 代码块。源码始终保留在原文件里，显示切换不会修改文件内容。

已安装旧版时，用新版 ZIP 中的插件文件夹替换原目录，更新上面的插件配置后重启。尤其需要添加 `ft = { "markdown" }`，以便打开 Markdown 时自动加载。

行内控制命令：

```vim
:MermanInline
:MermanRender
:MermanClear
```

分别用于开关当前文档的行内显示、立即渲染、清除并关闭行内显示。关闭后，普通编辑不会自动重新启用。

如果只想手动启用行内显示，可设 `inline = { enabled = false }`，然后运行 `:MermanInline`。

若要保留之前“源码与下方图表同时显示”的方式，将 `inline.mode` 改为 `"inline"`。默认 `"hybrid"` 按编辑模式切换：Normal 显示图表，Insert/Visual 显示源码。

行内图表使用 Neovim 的虚拟行，不写入文件。超大图的横向显示和滚动受窗口限制，需要浏览完整细节时，使用浮窗或分屏。

将光标放进 Markdown 的 `mermaid` 代码块，执行浮窗预览：

```vim
:MermanPreview
```

分屏预览使用：

```vim
:MermanSplit
```

用 `q` 或 `<Esc>` 关闭。使用普通 Vim 移动键滚动，`zH` / `zL` 横向滚动。源码不会改动。浮窗和分屏预览需要在修改源码后重新执行命令；行内图表会自动刷新。

独立 `.mmd` 文件可直接预览。也可以只选择图表源码，再执行 `:'<,'>MermanPreview`。选区不应包含 Markdown 代码围栏。

Markdown 中的代码围栏需要写成 `mermaid`；聊天消息中的 `less` 标签如果也出现在实际文档里，应改为 `mermaid`。

## 本次差异的原因

- 原插件把标签的引号和 `<br/>` 原样输出，节点因此变得很宽。
- `ACL --> DEMO` 指向子图，但原插件创建了多余的普通节点 `DEMO`。
- 中文宽度、子图和回边的排版由不同引擎处理；调整 padding 无法补齐这些语法与布局差异。
- 截图里的橙色 `MD013/line-length` 来自 Markdown lint 的诊断虚拟文本，不属于图表本身。行内图表显示在代码块下方；浮窗和分屏在独立预览 buffer 中显示。

## 范围与验证

这是本次生成的本地适配插件，不是公开发布的成熟插件。它使用固定的 OpenCode 源码版本：

https://github.com/anomalyco/opencode/tree/d7ae4f2e3ccdbdbb1a7cb6be660713aae44a6713/packages/merman

包含 flowchart、classDiagram、sequenceDiagram、stateDiagram-v2、gantt、gitGraph、timeline 的引擎入口；其他图类型会提示不支持。

0.3.0 新增 classDiagram。类图支持名称/属性/方法分栏、可见性标记、类注解、泛型、中文标签、命名空间，以及继承、组合、聚合、关联、依赖、实现和普通连线。双向关系也保留两端的 UML 标记。

类图的解析与分栏是本插件新增代码，布局和路由仍使用 merman。基数与关系标签合并显示在连线中间，例如 `1 / 生产 / *`；暂未实现 note 和 lollipop 接口语法，classDef/style/click 语句不改变预览样式。

已通过：你的图表在 80、100、120 列下的渲染检查、六类图的基本渲染、语法错误处理，以及真实 Neovim 的浮窗、分屏、中文高亮字节位置、选区和 `.mmd` 预览检查。

0.2.0 新增行内模式，已验证多图表彩色虚拟行、源码保留、编辑/删除刷新、缓存、手动开关、关闭后的异步任务取消、嵌套围栏示例跳过，以及错误恢复。

预览颜色由 Neovim 高亮组映射，未完整复刻 OpenCode 的主题、渐变和交互。0.5.0 默认在 Normal 模式以图表替代源码，进入 Insert/Visual 后展开源码；隐藏仅影响显示，不改动 buffer 内容。浮窗和分屏仍按命令渲染。

类图应放在 `mermaid` 代码围栏里，并以 `classDiagram` 开头。附带的 `examples/classes.mmd` 可直接预览。

0.3.0 已验证：类成员、中文、泛型、八类 UML 关系、双向关系、自引用、循环、命名空间、解析错误与 UTF-8 高亮，以及真实 Neovim 的行内自动刷新、浮窗和分屏。原始流程图样例的文本输出保持一致。

0.5.0 已通过真实终端按键和屏幕检查：Normal（含光标在代码块内）、Insert、Visual 字符/行/块选择、Replace，以及 Esc 返回 Normal。另已验证在编辑模式完成异步渲染后仍保持源码、切回 Normal 显示更新结果、缓存不增加渲染进程，以及关闭后恢复 conceallevel / concealcursor。

切换模式以当前活动窗口的编辑模式为准；同一个 buffer 在多个窗口中共享图表显示状态。

## 源码和重新构建

ZIP 保留了 `source/`、`build.mjs`、依赖版本与第三方许可证，便于审查。仅在修改 JavaScript 引擎后，才需要在插件目录中运行：

```sh
npm install
npm run build
```

## 本地验证

在插件目录中运行（不需要安装 npm 依赖）：

```sh
nvim --headless -u NONE -i NONE -l tests/test-inline.lua
nvim --headless -u NONE -i NONE -l tests/test-nvim.lua
node tests/test-class.mjs
nvim --headless -u NONE -i NONE -l tests/test-class-nvim.lua
nvim --headless -u NONE -i NONE -l tests/test-hybrid.lua
```
