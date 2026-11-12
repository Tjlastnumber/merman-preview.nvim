vim.opt.rtp:append(vim.fn.getcwd())
vim.o.columns, vim.o.lines = 120, 50
local calls=0
local system=vim.system
vim.system=function(...)calls=calls+1;return system(...)end
require('merman_preview').setup({inline={enabled=true,mode='hybrid',debounce_ms=30}})
local buf=vim.api.nvim_get_current_buf()
local graph=vim.api.nvim_get_namespaces().merman_inline
local source=vim.api.nvim_get_namespaces().merman_source
local function marks(ns)return vim.api.nvim_buf_get_extmarks(buf,ns,0,-1,{details=true})end
local function wait_for(fn,message)assert(vim.wait(5000,fn,10),message)end
local function move(row)
 vim.api.nvim_win_set_cursor(0,{row,0})
 vim.api.nvim_exec_autocmds('CursorMoved',{buffer=buf})
end
local original={'Before','```mermaid','flowchart LR','ALPHA[源]-->BETA[图]','```','After'}
vim.api.nvim_buf_set_lines(buf,0,-1,false,original)
vim.bo.modified=false
vim.wo.conceallevel=0
vim.wo.concealcursor="v"
move(1)
vim.bo.filetype='markdown'
wait_for(function()return #marks(graph)==1 end,'initial graph missing')
assert(#marks(source)==4 and marks(graph)[1][2]==2,'source not concealed')
assert(vim.wo.conceallevel==2 and vim.wo.concealcursor:find('n',1,true))
local count=calls
for _=1,3 do
 move(3)
 assert(#marks(graph)==1 and #marks(source)==4,'Normal-mode cursor position changed presentation')
 move(6)
 assert(#marks(graph)==1 and #marks(source)==4,'leave did not replace source')
end
assert(calls==count,'cursor movement re-rendered the engine')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf,0,-1,false),original) and not vim.bo.modified,'presentation changed source')
-- Source changes refresh the graph in Normal mode.
move(4)
vim.api.nvim_buf_set_lines(buf,3,4,false,{'ALPHA[刷新]-->BETA[完成]'})
vim.api.nvim_exec_autocmds('TextChangedI',{buffer=buf})
wait_for(function()return calls>count end,'edit did not render')
wait_for(function()return #marks(graph)==1 and vim.inspect(marks(graph)):find('刷新',1,true) end,'Normal-mode edit did not refresh graph')
move(6)
wait_for(function()local m=marks(graph);return #m==1 and vim.inspect(m):find('刷新',1,true)end,'fresh graph missing')
-- Parse errors retain their source and show a local diagnostic.
move(4)
vim.api.nvim_buf_set_lines(buf,3,4,false,{'ALPHA[unfinished'})
vim.api.nvim_exec_autocmds('TextChangedI',{buffer=buf})
move(6)
wait_for(function()return vim.inspect(marks(graph)):find('Mermaid:',1,true)end,'parse error missing')
assert(#marks(source)==0,'invalid source concealed')
-- Restore a valid diagram at EOF.
vim.api.nvim_buf_set_lines(buf,0,-1,false,{'Before','```mermaid','classDiagram','class User { +String 姓名; +save() void }','```'})
move(1)
vim.api.nvim_exec_autocmds('TextChanged',{buffer=buf})
wait_for(function()return #marks(graph)==1 and vim.inspect(marks(graph)):find('姓名',1,true)end,'EOF class graph missing')
assert(#marks(source)==4)
vim.cmd('MermanClear')
assert(#marks(graph)==0 and #marks(source)==0 and vim.wo.conceallevel==0 and vim.wo.concealcursor=='v','clear did not restore source/options')
-- Normal mode renders every block regardless of cursor location.
vim.api.nvim_buf_set_lines(buf,0,-1,false,{'Before','```mermaid','flowchart LR','A-->B','```','Between','```mermaid','classDiagram','class Foo','```','After'})
vim.cmd('MermanInline')
wait_for(function()return #marks(graph)==2 end,'two diagrams missing')
move(4)
assert(#marks(graph)==2,'Normal mode hid graph under cursor')
move(9)
assert(#marks(graph)==2,'Normal mode hid class graph under cursor')
move(11)
assert(#marks(graph)==2)
vim.cmd('MermanClear')
print('PASS: Normal-mode preview independent of cursor, no extra rendering, source preserved, refresh/error/EOF, multi-block/class display, window options restored')
vim.cmd('qa!')
