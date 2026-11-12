vim.opt.rtp:append(vim.fn.getcwd())
vim.o.columns, vim.o.lines = 130, 50
local calls = 0
local original_system = vim.system
vim.system = function(...) calls = calls + 1; return original_system(...) end
require('merman_preview').setup({max_width=120,inline={enabled=true,mode="inline",debounce_ms=30}})
local buf=vim.api.nvim_get_current_buf()
local ns=vim.api.nvim_get_namespaces().merman_inline
local function marks()
 return vim.api.nvim_buf_get_extmarks(buf,ns,0,-1,{details=true})
end
local function wait_for(fn,message)
 assert(vim.wait(5000,fn,10),message)
end
local function text_of(mark)
 local lines={}
 for _,chunks in ipairs(mark[4].virt_lines) do
  local line={}
  for _,chunk in ipairs(chunks) do line[#line+1]=chunk[1] end
  lines[#lines+1]=table.concat(line)
 end
 return table.concat(lines,'\n')
end
local src={'# Test','```mermaid'}
vim.list_extend(src,vim.fn.readfile('examples/demo.mmd'))
src[#src+1]='```'
src[#src+1]='Paragraph'
src[#src+1]='~~~mermaid'
src[#src+1]='sequenceDiagram'
src[#src+1]='Alice->>Bob: 中文消息'
src[#src+1]='~~~'
local snapshot=vim.deepcopy(src)
vim.api.nvim_buf_set_lines(buf,0,-1,false,src)
vim.bo.filetype='markdown'
wait_for(function() return #marks()==2 end,'two diagrams missing')
local initial=marks()
assert(text_of(initial[1]):find('SourceSnapshot',1,true))
assert(not text_of(initial[1]):find('<br',1,true))
assert(text_of(initial[2]):find('中文消息',1,true))
assert(initial[1][2]==14 and initial[2][2]==19,'closing fence placement')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf,0,-1,false),snapshot),'source changed')
-- Cached results avoid renderer startup for unchanged text.
local initial_calls=calls
require('merman_preview.inline').render(buf)
assert(calls==initial_calls,'cache missed')
-- Text changes refresh automatically while unchanged blocks stay cached.
vim.api.nvim_buf_set_lines(buf,18,19,false,{'Alice->>Bob: 刷新结果'})
vim.api.nvim_exec_autocmds('TextChanged',{buffer=buf})
wait_for(function() local m=marks(); return #m==2 and text_of(m[2]):find('刷新结果',1,true) end,'auto refresh failed')
assert(calls==initial_calls+1,'unchanged diagram re-rendered')
-- Deleted diagrams disappear.
vim.api.nvim_buf_set_lines(buf,16,20,false,{})
vim.api.nvim_exec_autocmds('TextChanged',{buffer=buf})
wait_for(function() return #marks()==1 end,'deleted diagram retained')
-- Manual disable persists across entering the window and further edits.
vim.cmd('MermanClear')
assert(#marks()==0)
vim.api.nvim_exec_autocmds('BufWinEnter',{buffer=buf})
vim.api.nvim_exec_autocmds('TextChanged',{buffer=buf})
vim.wait(100,function() return false end,10)
assert(#marks()==0,'disabled overlay returned')
vim.cmd('MermanInline')
wait_for(function() return #marks()==1 end,'toggle enable failed')
-- A pending render cannot recreate marks after the user disables inline mode.
vim.cmd('MermanRender')
vim.cmd('MermanClear')
vim.wait(300,function() return false end,10)
assert(#marks()==0,'stale renderer committed after disable')
-- Mermaid examples inside an outer Markdown fence are not rendered.
vim.api.nvim_buf_set_lines(buf,0,-1,false,{'````markdown','```mermaid','flowchart LR','A-->B','```','````'})
vim.cmd('MermanInline')
assert(#marks()==0,'nested example rendered')
-- Parsing failures are local virtual messages and do not alter the file.
vim.api.nvim_buf_set_lines(buf,0,-1,false,{'```mermaid','flowchart LR','A[unfinished','```'})
vim.api.nvim_exec_autocmds('TextChanged',{buffer=buf})
wait_for(function() local m=marks(); return #m==1 and text_of(m[1]):find('Mermaid:',1,true) end,'missing parse error')
-- A valid edit recovers from an invalid diagram.
vim.api.nvim_buf_set_lines(buf,2,3,false,{'A[恢复]-->B[正常]'})
vim.api.nvim_exec_autocmds('TextChangedI',{buffer=buf})
wait_for(function() local m=marks(); return #m==1 and text_of(m[1]):find('恢复',1,true) end,'error recovery failed')
-- Deleting the buffer cancels rendering without deferred callback errors.
vim.cmd('MermanRender')
vim.api.nvim_buf_delete(buf,{force=true})
vim.wait(200,function() return false end,10)
print('PASS: colored virtual lines; multiple blocks; source preserved; cache; edit/delete refresh; toggle; stale cancellation; nested fences; errors/recovery; buffer cleanup')
vim.cmd('qa!')
