# merman-preview.nvim

English | [简体中文](README.md)

Preview Mermaid diagrams in Neovim using OpenCode's merman parser, layout engine, and character-grid renderer, with an additional `classDiagram` adapter.

By default, Markdown diagrams replace their source in Normal mode and reveal the source while you edit. Floating-window and split previews are also available. Diagrams use colored Unicode text, so terminals such as iTerm2 do not need an image protocol.

## Requirements

- Node.js 20 or later.
- Neovim 0.11 or later for switching between source and diagrams in place.
- Neovim 0.10 is supported for floating windows, splits, and appended inline diagrams. Hybrid mode falls back to appended diagrams on older versions.

The compiled renderer, `bin/render.mjs`, is included. Installation does not require `npm install`, Bun, `mmdc`, or ImageMagick.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim), add the following plugin specification, for example in `lua/plugins/merman-preview.lua`:

```lua
return {
  "Tjlastnumber/merman-preview.nvim",
  main = "merman_preview",
  ft = { "markdown", "mermaid" },
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
}
```

For a local installation, place the entire plugin directory at `<Neovim config directory>/local/merman-preview.nvim` and replace the repository string above with:

```lua
dir = vim.fn.stdpath("config") .. "/local/merman-preview.nvim",
name = "merman-preview.nvim",
```

Run `:echo stdpath("config")` to find your configuration directory. Make sure `bin/render.mjs` is directly inside the plugin directory rather than an extra nested copy. Disable other Mermaid preview plugins if they conflict with this one.

If you use another plugin manager, load the plugin and call:

```lua
require("merman_preview").setup({
  max_width = 120,
  timeout = 10000,
  inline = { enabled = true, mode = "hybrid", debounce_ms = 400 },
})
```

## Inline previews

Write a complete fenced code block with the language set to `mermaid`:

````markdown
```mermaid
flowchart LR
  A[Edit source] --> B[Preview diagram]
```
````

The default `hybrid` mode behaves as follows:

- **Normal mode:** hides the source and displays the colored diagram, even when the cursor is inside the code block.
- **Insert and Visual modes:** reveals the source and hides the diagram. Characterwise, linewise, and blockwise Visual selections are supported. Replace and Select modes also reveal the source.
- **Return to Normal mode:** restores the diagram.
- **After editing:** refreshes automatically after a 400 ms debounce. Mode changes reuse cached results without starting another renderer process.
- **Render errors:** keeps the source visible and displays an error.

Mode changes affect all Mermaid blocks in the current document. The source remains in the buffer and saved file; switching the display does not edit it. When the same buffer is open in multiple windows, those windows share the diagram display state, determined by the active window's editing mode.

Use these commands to control inline previews:

| Command | Action |
| --- | --- |
| `:MermanInline` | Toggle inline previews for the current document. |
| `:MermanRender` | Render immediately. |
| `:MermanClear` | Clear diagrams and disable inline previews. |

After inline previews are disabled, ordinary editing does not enable them again. To enable them only on demand, set `inline.enabled = false` and run `:MermanInline` when needed.

Set `inline.mode = "inline"` to keep the source visible and append diagrams below it. Inline diagrams use Neovim virtual lines and are never written to the file. Window width limits horizontal viewing; use a floating window or split for large diagrams.

## Floating-window and split previews

Place the cursor inside a Markdown `mermaid` code block and run:

```vim
:MermanPreview
```

For a split preview, run:

```vim
:MermanSplit
```

Close the preview with `q` or `<Esc>`. Use normal Vim movement keys to navigate and `zH` / `zL` to scroll horizontally. Floating-window and split previews render on command; run the command again after editing the source.

Standalone `.mmd` files can be previewed directly. You can also select diagram source and run `:'<,'>MermanPreview`; exclude the Markdown fences from the selection.

## Supported diagrams and limitations

The renderer includes entry points for `flowchart`, `classDiagram`, `sequenceDiagram`, `stateDiagram-v2`, `gantt`, `gitGraph`, and `timeline`. Other diagram types report an unsupported-type error.

Sequence diagrams support nested `rect rgb(...)` / `rect rgba(...)` regions. Character previews show a frame labeled `rect` instead of reproducing RGB background fills. See [examples/batch-transfer.mmd](examples/batch-transfer.mmd) for a complete example. Use a `mermaid` Markdown fence and start the diagram source with `sequenceDiagram`.

Class diagrams support separate name, attribute, and method sections; visibility markers; class annotations; generics; Chinese labels; namespaces; and inheritance, composition, aggregation, association, dependency, realization, and plain links. Bidirectional relations preserve UML markers at both ends.

The class parser and compartment rendering are additions in this plugin; layout and routing still use merman. Cardinalities and relation labels appear together in the middle of a link, for example `1 / produces / *`. Class diagram notes and lollipop interfaces are not implemented. `classDef`, `style`, and `click` statements do not change the preview's appearance. See [examples/classes.mmd](examples/classes.mmd) for a class diagram example.

Layout depends on the target width, font, and engine version. The default target width is 120 columns; narrower widths can produce different layouts. Preview colors map to Neovim highlight groups and do not fully reproduce OpenCode themes, gradients, or interactions. Markdown lint messages such as `MD013/line-length` are editor diagnostics rather than part of the diagram.

This is an experimental adaptation using a pinned [OpenCode merman source revision](https://github.com/anomalyco/opencode/tree/d7ae4f2e3ccdbdbb1a7cb6be660713aae44a6713/packages/merman). The source and third-party license notices are included for review; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Version notes

- **0.5.0:** hybrid display by default, showing diagrams in Normal mode and source in Insert/Visual modes. Hiding source only affects display. Floating windows and splits remain command-driven.
- **0.3.0:** added the `classDiagram` adapter.
- **0.2.0:** added inline previews, automatic refresh, caching, and manual controls.

## Building from source

Rebuild only when changing the JavaScript/TypeScript renderer. From the plugin directory, run:

```sh
npm install
npm run build
```

The repository includes `source/`, `build.mjs`, dependency versions, and third-party license notices.

## Local verification

Run the following from the plugin directory. These checks use the bundled renderer and do not require installing npm dependencies:

```sh
nvim --headless -u NONE -i NONE -l tests/test-inline.lua
nvim --headless -u NONE -i NONE -l tests/test-nvim.lua
node tests/test-class.mjs
node tests/test-sequence.mjs
nvim --headless -u NONE -i NONE -l tests/test-sequence-nvim.lua
nvim --headless -u NONE -i NONE -l tests/test-class-nvim.lua
nvim --headless -u NONE -i NONE -l tests/test-hybrid.lua
```

The Chinese README records previous checks for rendering at 80, 100, and 120 columns; supported diagram types and parse errors; floating-window, split, selection, and `.mmd` previews; UTF-8 highlighting; inline refresh, caching, cancellation, and error recovery; and hybrid mode behavior in a real Neovim terminal, including restoring conceal settings when disabled.
