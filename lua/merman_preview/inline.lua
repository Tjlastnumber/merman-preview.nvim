local M = {}
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
local ns = vim.api.nvim_create_namespace("merman_inline")
local source_ns = vim.api.nvim_create_namespace("merman_source")
local states = {}
local managed_windows = {}
local config, highlight

local function cancel(state)
  state.generation = state.generation + 1
  if state.timer then
    state.timer:stop()
    if not state.timer:is_closing() then state.timer:close() end
    state.timer = nil
  end
  if state.process then state.process:kill(15); state.process = nil end
end

local function is_markdown(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == ""
    and (vim.bo[buf].filetype == "markdown" or vim.bo[buf].filetype == "markdown.mdx")
end

local function blocks(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ret, opening, fence, lang = {}, nil, nil, nil
  for row, line in ipairs(lines) do
    local chars, info = line:match("^%s*([`~]+)%s*(.-)%s*$")
    if chars and #chars >= 3 and (chars:match("^`+$") or chars:match("^~+$")) then
      if not opening then
        opening, fence, lang = row, chars, info:match("^(%S+)")
      elseif chars:sub(1, 1) == fence:sub(1, 1) and #chars >= #fence and info == "" then
        if lang == "mermaid" then
          ret[#ret + 1] = { start = opening - 1, row = row - 1, source = table.concat(vim.list_slice(lines, opening + 1, row - 1), "\n") }
        end
        opening, fence, lang = nil, nil, nil
      end
    end
  end
  -- Render only closed blocks. Incomplete fences remain ordinary editable source.
  return ret
end

local function layout_width(buf)
  local width = config.max_width
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local info = vim.fn.getwininfo(win)[1]
    if info then width = math.min(width, vim.api.nvim_win_get_width(win) - info.textoff - 2) end
  end
  return math.max(20, width)
end

local function virtual_lines(result)
  local by_row = {}
  for _, h in ipairs(result.highlights or {}) do
    by_row[h[1]] = by_row[h[1]] or {}
    by_row[h[1]][#by_row[h[1]] + 1] = h
  end
  local ret = { { { "", "MermanText" } } }
  for row, line in ipairs(result.lines) do
    local chunks, offset = {}, 0
    for _, h in ipairs(by_row[row - 1] or {}) do
      if h[2] > offset then chunks[#chunks + 1] = { line:sub(offset + 1, h[2]), "MermanText" } end
      if h[3] > h[2] then chunks[#chunks + 1] = { line:sub(h[2] + 1, h[3]), highlight(h[4]) } end
      offset = h[3]
    end
    if offset < #line then chunks[#chunks + 1] = { line:sub(offset + 1), "MermanText" } end
    if #chunks == 0 then chunks = { { "", "MermanText" } } end
    ret[#ret + 1] = chunks
  end
  ret[#ret + 1] = { { "", "MermanText" } }
  return ret
end

local function sync_windows()
  for win, saved in pairs(managed_windows) do
    if not vim.api.nvim_win_is_valid(win) then
      managed_windows[win] = nil
    else
      local buf = vim.api.nvim_win_get_buf(win)
      local state = states[buf]
      if buf ~= saved.buf or not state or not state.enabled or not state.replacing then
        if vim.wo[win].conceallevel == saved.applied then vim.wo[win].conceallevel = saved.original end
        if vim.wo[win].concealcursor == saved.applied_cursor then vim.wo[win].concealcursor = saved.original_cursor end
        managed_windows[win] = nil
      end
    end
  end
  for buf, state in pairs(states) do
    if state.enabled and state.replacing then
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if not managed_windows[win] then
          local original = vim.wo[win].conceallevel
          local original_cursor = vim.wo[win].concealcursor
          local applied_cursor = original_cursor
          for mode in ("nc"):gmatch(".") do
            if not applied_cursor:find(mode, 1, true) then applied_cursor = applied_cursor .. mode end
          end
          managed_windows[win] = {
            buf = buf, original = original, applied = math.max(2, original),
            original_cursor = original_cursor, applied_cursor = applied_cursor,
          }
          vim.wo[win].conceallevel = math.max(2, original)
          vim.wo[win].concealcursor = applied_cursor
        end
      end
    end
  end
end

local function source_mode(mode)
  local first = mode:sub(1, 1)
  return first == "i" or first == "R" or first == "v" or first == "V" or first == "\22"
    or first == "s" or first == "S" or first == "\19" or mode:match("^ni") ~= nil
end

local function repaint(buf, force, mode)
  local state = states[buf]
  if not state or not state.enabled or not is_markdown(buf) then return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if state.rendered_tick ~= tick then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(buf, source_ns, 0, -1)
    state.presentation, state.replacing = nil, false
    sync_windows()
    return
  end
  local hybrid = config.inline.mode == "hybrid" and vim.fn.has("nvim-0.11") == 1
  local editing = hybrid and vim.api.nvim_get_current_buf() == buf
    and source_mode(mode or vim.api.nvim_get_mode().mode)
  local presentation = tostring(hybrid) .. ":" .. tostring(editing)
  if not force and state.presentation == presentation then sync_windows(); return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, source_ns, 0, -1)
  state.replacing = false
  for _, entry in ipairs(state.entries or {}) do
    if not hybrid or not entry.success then
      vim.api.nvim_buf_set_extmark(buf, ns, entry.row, 0, {
        virt_lines = entry.lines, virt_lines_above = false, right_gravity = false,
      })
    elseif not editing then
      -- Anchor to the first content line, since Markdown plugins may conceal
      -- fence lines independently. Keeping this anchor also handles EOF.
      local anchor = entry.start + 1
      local text = vim.api.nvim_buf_get_lines(buf, anchor, anchor + 1, false)[1] or ""
      for row = entry.start, entry.row do
        if row == anchor then
          vim.api.nvim_buf_set_extmark(buf, source_ns, row, 0, { end_col = #text, conceal = "" })
        else
          vim.api.nvim_buf_set_extmark(buf, source_ns, row, 0, { conceal_lines = "" })
        end
      end
      vim.api.nvim_buf_set_extmark(buf, ns, anchor, 0, {
        virt_lines = vim.list_slice(entry.lines, 2), virt_lines_above = false, right_gravity = false,
      })
      state.replacing = true
    end
  end
  state.presentation = presentation
  sync_windows()
end

function M.render(buf, force)
  buf = buf or vim.api.nvim_get_current_buf()
  if not is_markdown(buf) then return end
  local state = states[buf]
  if not state or not state.enabled then return end
  cancel(state)
  local generation, tick = state.generation, vim.api.nvim_buf_get_changedtick(buf)
  local found, width = blocks(buf), layout_width(buf)
  local rendered, cache = {}, {}
  local function valid()
    return states[buf] == state and state.enabled and state.generation == generation
      and is_markdown(buf) and vim.api.nvim_buf_get_changedtick(buf) == tick
  end
  local function commit()
    if not valid() then return end
    state.cache, state.entries, state.rendered_tick = cache, rendered, tick
    repaint(buf, true)
  end
  if #found == 0 then commit(); return end
  if vim.fn.executable(config.node) ~= 1 then
    vim.notify("merman-preview: 行内渲染需要 Node.js 20+", vim.log.levels.ERROR)
    return
  end
  local index = 0
  local next_block
  next_block = function()
    if not valid() then return end
    index = index + 1
    local block = found[index]
    if not block then commit(); return end
    local key = tostring(width) .. "\0" .. block.source
    local function add(result)
      cache[key] = result
      rendered[#rendered + 1] = { start = block.start, row = block.row, lines = virtual_lines(result), success = true }
      next_block()
    end
    if not force and state.cache[key] then add(state.cache[key]); return end
    state.process = vim.system({ config.node, root .. "/bin/render.mjs" }, {
      text = true, stdin = vim.json.encode({ source = block.source, width = width }), timeout = config.timeout,
    }, function(response)
      vim.schedule(function()
        if not valid() then return end
        state.process = nil
        local ok, result = pcall(vim.json.decode, response.stdout or "")
        if response.code == 0 and ok and type(result) == "table" and type(result.lines) == "table" then
          add(result)
        else
          local err = response.stderr or ""
          err = err:match("[^\r\n]+") or "渲染失败或超时"
          rendered[#rendered + 1] = { start = block.start, row = block.row, lines = { { { "Mermaid: " .. err, "DiagnosticError" } } }, success = false }
          next_block()
        end
      end)
    end)
  end
  next_block()
end

local function schedule(buf)
  local state = states[buf]
  if not state or not state.enabled then return end
  cancel(state)
  repaint(buf)
  state.timer = vim.defer_fn(function()
    state.timer = nil
    if states[buf] == state and state.enabled then M.render(buf) end
  end, config.inline.debounce_ms)
end

function M.enable(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not is_markdown(buf) then return end
  if not states[buf] then states[buf] = { generation = 0, cache = {} } end
  states[buf].enabled = true
  M.render(buf)
end

function M.disable(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local state = states[buf]
  if state then
    cancel(state)
    state.enabled, state.replacing, state.cache, state.entries, state.presentation = false, false, {}, {}, nil
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(buf, source_ns, 0, -1)
  end
  sync_windows()
end

function M.toggle(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if states[buf] and states[buf].enabled then M.disable(buf) else M.enable(buf) end
end

function M.setup(options, group)
  config, highlight = options, group
  if config.inline.mode ~= "hybrid" and config.inline.mode ~= "inline" then
    error("merman-preview: inline.mode must be 'hybrid' or 'inline'")
  end
  local ag = vim.api.nvim_create_augroup("merman_inline", { clear = true })
  local function attach(buf)
    if config.inline.enabled and is_markdown(buf) then
      if states[buf] then schedule(buf) else M.enable(buf) end
    end
  end
  vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, { group = ag, callback = function(ev) attach(ev.buf) end })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = ag, callback = function(ev) schedule(ev.buf) end,
  })
  vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    group = ag, callback = function() repaint(vim.api.nvim_get_current_buf()) end,
  })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = ag, pattern = "*", callback = function()
      repaint(vim.api.nvim_get_current_buf(), false, vim.v.event.new_mode)
    end,
  })
  vim.api.nvim_create_autocmd("BufLeave", { group = ag, callback = function(ev)
    vim.schedule(function() repaint(ev.buf, true); sync_windows() end)
  end })
  vim.api.nvim_create_autocmd("VimResized", { group = ag, callback = function()
    for buf in pairs(states) do schedule(buf) end
  end })
  vim.api.nvim_create_autocmd("BufWipeout", { group = ag, callback = function(ev)
    if states[ev.buf] then cancel(states[ev.buf]); states[ev.buf] = nil end
    sync_windows()
  end })
  vim.api.nvim_create_autocmd("FileType", { group = ag, callback = function(ev)
    if states[ev.buf] and not is_markdown(ev.buf) then M.disable(ev.buf) end
  end })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = ag, callback = function()
    for _, state in pairs(states) do cancel(state) end
  end })
  vim.api.nvim_create_user_command("MermanInline", function() M.toggle() end, { desc = "Toggle inline Mermaid diagrams" })
  vim.api.nvim_create_user_command("MermanRender", function()
    local buf = vim.api.nvim_get_current_buf()
    if states[buf] and states[buf].enabled then M.render(buf, true) else M.enable(buf) end
  end, { desc = "Render inline Mermaid diagrams" })
  vim.api.nvim_create_user_command("MermanClear", function() M.disable() end, { desc = "Clear and disable inline Mermaid diagrams" })
  -- lazy.nvim may load the plugin after the current FileType event.
  attach(vim.api.nvim_get_current_buf())
end

return M
