local M = {}
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
local ns = vim.api.nvim_create_namespace("merman_preview")
local opts = {
  node = "node", max_width = 120, timeout = 10000,
  inline = { enabled = true, mode = "hybrid", debounce_ms = 400 },
}
local requests = {}
local current

local function define_highlights()
  local dark = vim.o.background == "dark"
  vim.api.nvim_set_hl(0, "MermanText", { default = true, fg = dark and "#d0cec4" or "#303030" })
  vim.api.nvim_set_hl(0, "MermanClass", { default = true, fg = dark and "#d0cec4" or "#303030", bold = true })
  vim.api.nvim_set_hl(0, "MermanBorder", { default = true, fg = dark and "#999b96" or "#666666" })
  vim.api.nvim_set_hl(0, "MermanGroup", { default = true, fg = dark and "#c4ad60" or "#806c20" })
  vim.api.nvim_set_hl(0, "MermanLabel", { default = true, fg = dark and "#d0cec4" or "#303030", bg = dark and "#242424" or "#e6e6e6" })
end

local function group(style)
  if style == "classTitle" then return "MermanClass" end
  if style == "group" or style == "groupLabel" or style == "section" then return "MermanGroup" end
  if style == "label" or style == "fragmentLabel" then return "MermanLabel" end
  if style:find("Border") or style:find("Fade") or style == "edge" or style == "lifeline" or style == "axis" then
    return "MermanBorder"
  end
  return "MermanText"
end

local function source_at_cursor(buf, first, last)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if first then return table.concat(vim.list_slice(lines, first, last), "\n") end
  if vim.bo[buf].filetype == "mermaid" or vim.api.nvim_buf_get_name(buf):match("%.mmd$") then
    return table.concat(lines, "\n")
  end
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local opening, fence, lang
  for n, line in ipairs(lines) do
    local chars, info = line:match("^%s*([`~]+)%s*(.-)%s*$")
    if chars and #chars >= 3 and (chars:match("^`+$") or chars:match("^~+$")) then
      if not opening then
        opening, fence, lang = n, chars, info:match("^(%S+)")
      elseif chars:sub(1, 1) == fence:sub(1, 1) and #chars >= #fence and info == "" then
        if lang == "mermaid" and cursor >= opening and cursor <= n then
          return table.concat(vim.list_slice(lines, opening + 1, n - 1), "\n")
        end
        opening, fence, lang = nil, nil, nil
      end
    end
  end
  if opening and lang == "mermaid" and cursor >= opening then
    return table.concat(vim.list_slice(lines, opening + 1), "\n")
  end
  return nil, "请将光标移到 mermaid 代码块内，或选中图表源码后执行 :MermanPreview"
end

function M.close()
  if current and vim.api.nvim_buf_is_valid(current) then
    vim.api.nvim_buf_delete(current, { force = true })
  end
  current = nil
end

local function show(result, split, width)
  M.close()
  local buf = vim.api.nvim_create_buf(false, true)
  current = buf
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "mermanpreview"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, result.lines)
  local win
  if split then
    vim.cmd("botright split")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  else
    local height = math.max(1, math.min(#result.lines, vim.o.lines - 6))
    win = vim.api.nvim_open_win(buf, true, {
      relative = "editor", width = width, height = height,
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
      style = "minimal", border = "rounded", title = " Mermaid · merman ", title_pos = "center",
    })
  end
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].spell = false
  vim.wo[win].list = false
  vim.wo[win].cursorline = false
  vim.wo[win].conceallevel = 0
  vim.wo[win].scrolloff = 0
  vim.wo[win].sidescrolloff = 0
  vim.wo[win].winhighlight = "Normal:MermanText"
  for _, hl in ipairs(result.highlights or {}) do
    if hl[3] > hl[2] then
      vim.api.nvim_buf_set_extmark(buf, ns, hl[1], hl[2], { end_col = hl[3], hl_group = group(hl[4]) })
    end
  end
  vim.bo[buf].modifiable = false
  vim.keymap.set("n", "q", M.close, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = buf, silent = true })
  -- Larger diagrams retain normal Vim horizontal scrolling (zh/zl, zH/zL).
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

function M.preview(command)
  command = command or {}
  if vim.fn.executable(opts.node) ~= 1 then
    vim.notify("merman-preview: 找不到 Node.js，请安装 Node.js 20+", vim.log.levels.ERROR)
    return
  end
  local source_buf = vim.api.nvim_get_current_buf()
  local source, err = source_at_cursor(source_buf,
    command.range and command.range > 0 and command.line1 or nil, command.line2)
  if not source then vim.notify(err, vim.log.levels.WARN); return end
  local width = math.max(20, math.min(opts.max_width, vim.o.columns - 4))
  if requests[source_buf] then requests[source_buf]:kill(15) end
  local process
  process = vim.system({ opts.node, root .. "/bin/render.mjs" }, {
    text = true, stdin = vim.json.encode({ source = source, width = width }), timeout = opts.timeout,
  }, function(result)
    vim.schedule(function()
      if requests[source_buf] ~= process then return end
      requests[source_buf] = nil
      if not vim.api.nvim_buf_is_valid(source_buf) then return end
      if result.code ~= 0 then
        vim.notify("merman-preview: " .. (result.stderr ~= "" and result.stderr or "渲染失败或超时"), vim.log.levels.ERROR)
        return
      end
      local ok, decoded = pcall(vim.json.decode, result.stdout)
      if not ok or type(decoded) ~= "table" or type(decoded.lines) ~= "table" then
        vim.notify("merman-preview: 无效的渲染结果", vim.log.levels.ERROR)
        return
      end
      show(decoded, command.split, width)
    end)
  end)
  requests[source_buf] = process
end

function M.setup(config)
  opts = vim.tbl_deep_extend("force", opts, config or {})
  define_highlights()
  local ag = vim.api.nvim_create_augroup("merman_preview", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = ag, callback = define_highlights })
  for name, split in pairs({ MermanPreview = false, MermanSplit = true }) do
    vim.api.nvim_create_user_command(name, function(command)
      command.split = split
      M.preview(command)
    end, { range = true, desc = "Preview Mermaid with OpenCode's merman renderer" })
  end
  require("merman_preview.inline").setup(opts, group)
end

return M
