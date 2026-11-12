vim.opt.rtp:append(vim.fn.getcwd())
vim.o.columns, vim.o.lines = 140, 60
require('merman_preview').setup({inline={enabled=true,mode="inline",debounce_ms=30}})
local buf=vim.api.nvim_get_current_buf()
local src={'```mermaid'}
vim.list_extend(src,vim.fn.readfile('examples/classes.mmd'))
src[#src+1]='```'
local snapshot=vim.deepcopy(src)
vim.api.nvim_buf_set_lines(buf,0,-1,false,src)
vim.bo.filetype='markdown'
vim.api.nvim_win_set_cursor(0,{4,0})
local ns=vim.api.nvim_get_namespaces().merman_inline
local function inline()
 local marks=vim.api.nvim_buf_get_extmarks(buf,ns,0,-1,{details=true})
 local text,has_title={},false
 for _,mark in ipairs(marks) do
  for _,chunks in ipairs(mark[4].virt_lines) do
   local row={}
   for _,c in ipairs(chunks) do row[#row+1]=c[1];if c[2]=='MermanClass' then has_title=true end end
   text[#text+1]=table.concat(row)
  end
 end
 return table.concat(text,'\n'),has_title
end
assert(vim.wait(5000,function() return inline():find('Repository<T>',1,true) end,10),'class inline failed')
local text,title=inline()
assert(title and text:find('◆',1,true) and text:find('+String 来源编号',1,true))
assert(vim.deep_equal(snapshot,vim.api.nvim_buf_get_lines(buf,0,-1,false)))
vim.api.nvim_buf_set_lines(buf,4,5,false,{'        +importData() bool'})
vim.api.nvim_exec_autocmds('TextChanged',{buffer=buf})
assert(vim.wait(5000,function() return inline():find('+importData() bool',1,true) end,10),'class refresh failed')
vim.cmd('MermanPreview')
assert(vim.wait(5000,function() return vim.bo.filetype=='mermanpreview' end,10),'class float failed')
assert(table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),'\n'):find('ProductionService',1,true))
require('merman_preview').close()
vim.cmd('MermanSplit')
assert(vim.wait(5000,function() return vim.bo.filetype=='mermanpreview' end,10),'class split failed')
assert(table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),'\n'):find('Repository<T>',1,true))
require('merman_preview').close()
print('PASS: classDiagram inline, bold class titles, members/generics/UML marker, auto refresh, float, split, source preserved')
vim.cmd('qa!')
