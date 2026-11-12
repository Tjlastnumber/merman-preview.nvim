vim.opt.rtp:append(vim.fn.getcwd())
vim.o.columns, vim.o.lines = 160, 60
require('merman_preview').setup({inline={enabled=true,mode='hybrid',debounce_ms=30}})
local buf = vim.api.nvim_get_current_buf()
local src = {'```mermaid'}
vim.list_extend(src, vim.fn.readfile('examples/batch-transfer.mmd'))
src[#src + 1] = '```'
vim.api.nvim_buf_set_lines(buf, 0, -1, false, src)
vim.bo.filetype = 'markdown'
local ns = vim.api.nvim_get_namespaces().merman_inline
assert(vim.wait(5000, function()
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {details=true})
  return vim.inspect(marks):find('保存首次估值', 1, true)
end, 10), 'sequence hybrid preview missing')
local function assert_preview()
  assert(vim.wait(5000, function() return vim.bo.filetype == 'mermanpreview' end, 10), 'sequence preview timed out')
  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  for _, label in ipairs({'用户', 'Kafka Broker', 'rect', 'REPEATABLE_READ', '保存首次估值'}) do
    assert(text:find(label, 1, true), label)
  end
  require('merman_preview').close()
  assert(vim.api.nvim_get_current_buf() == buf)
  assert(vim.deep_equal(src, vim.api.nvim_buf_get_lines(buf, 0, -1, false)), 'preview modified source')
end
vim.api.nvim_win_set_cursor(0, {10, 0})
vim.cmd('MermanPreview')
assert_preview()
vim.cmd('MermanSplit')
assert_preview()
vim.cmd('MermanClear')
print('PASS: sequence rect/CJK hybrid, float, split, source preserved')
vim.cmd('qa!')
