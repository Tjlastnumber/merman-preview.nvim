vim.opt.rtp:append(vim.fn.getcwd())
local screenshots,mode_history={},{}
local steps,index,done={},0,false
local buf,ns,source_ns,initial_calls
local calls=0
local system=vim.system
vim.system=function(...)calls=calls+1;return system(...)end
local function marks(namespace)return vim.api.nvim_buf_get_extmarks(buf,namespace,0,-1,{})end
local function capture(name)
 vim.cmd('redraw!')
 local lines={}
 for row=1,vim.o.lines-2 do
  local line=''
  for col=1,vim.o.columns do line=line..vim.fn.screenstring(row,col) end
  lines[#lines+1]=line
 end
 local text=table.concat(lines,'\n');screenshots[name]=text;return text
end
local function finish(ok,err)
 if done then return end;done=true
 vim.fn.writefile({vim.json.encode({success=ok,error=err,screens=screenshots,modes=mode_history})},'tests/hybrid-ui-result.json')
 if ok then vim.cmd('qa!')else vim.cmd('cquit 1')end
end
local advance
local function add(name,keys,expected,editing,before,after)
 steps[#steps+1]=function()
  if before then before()end
  if keys then vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys,true,false,true),'n',false)end
  vim.defer_fn(function()
   local ok,err=xpcall(function()
    local actual=vim.api.nvim_get_mode().mode;mode_history[name]=actual
    assert(actual==expected,name..': expected '..vim.inspect(expected)..' got '..vim.inspect(actual))
    local text=capture(name)
    if editing then
     assert(#marks(ns)==0 and #marks(source_ns)==0,name..': decorations still present')
     assert(text:find('flowchart LR',1,true) and text:find('classDiagram',1,true),name..': source not shown')
     assert(not text:find('╭',1,true),name..': graph still shown')
    else
     assert(#marks(ns)==2 and #marks(source_ns)>0,name..': diagrams missing')
     assert(not text:find('flowchart LR',1,true) and not text:find('classDiagram',1,true),name..': raw source leaked')
     assert(text:find('输入',1,true)or text:find('更新',1,true),name..': flowchart not visible')
    end
    if after then after(text)end
   end,debug.traceback)
   if not ok then finish(false,err)else advance()end
  end,120)
 end
end
advance=function()
 index=index+1
 if not steps[index]then finish(true);return end
 local ok,err=xpcall(steps[index],debug.traceback)
 if not ok then finish(false,err)end
end
vim.defer_fn(function()
 local ok,err=xpcall(function()
  require('merman_preview').setup({inline={enabled=true,mode='hybrid',debounce_ms=30}})
  buf=vim.api.nvim_get_current_buf();ns=vim.api.nvim_get_namespaces().merman_inline;source_ns=vim.api.nvim_get_namespaces().merman_source
  vim.api.nvim_buf_set_lines(buf,0,-1,false,{'BEFORE','```mermaid','flowchart LR','SOURCE_ID[输入]-->TARGET_ID[输出]','```','BETWEEN','```mermaid','classDiagram','class Person { +String 姓名; +save() void }','```','AFTER'})
  vim.bo.modified=false;vim.wo.conceallevel=0;vim.wo.concealcursor='v'
  vim.api.nvim_win_set_cursor(0,{4,0});vim.bo.filetype='markdown'
  assert(vim.wait(5000,function()return #marks(ns)==2 end,10),'render timeout')
  initial_calls=calls
  add('normal_inside',nil,'n',false)
  add('normal_anchor',nil,'n',false,function()vim.api.nvim_win_set_cursor(0,{3,0})end)
  add('insert','i','i',true)
  add('normal_after_insert','<Esc>','n',false)
  add('visual','v','v',true)
  add('normal_after_visual','<Esc>','n',false)
  add('visual_line','V','V',true)
  add('normal_after_visual_line','<Esc>','n',false)
  add('visual_block','<C-v>','\22',true)
  add('normal_after_visual_block','<Esc>','n',false)
  add('replace','R','R',true)
  add('normal_after_replace','<Esc>','n',false,nil,function()
   assert(calls==initial_calls,'mode switching spawned renderer processes')
   assert(not vim.bo.modified,'switching modes changed source')
  end)
  add('insert_outside','i','i',true,function()vim.api.nvim_win_set_cursor(0,{6,0})end)
  add('insert_refreshed',nil,'i',true,function()
   vim.api.nvim_buf_set_lines(buf,3,4,false,{'SOURCE_ID[更新]-->TARGET_ID[输出]'})
   vim.api.nvim_exec_autocmds('TextChangedI',{buffer=buf})
  end)
  add('normal_refreshed','<Esc>','n',false,nil,function(text)assert(text:find('更新',1,true),'fresh graph missing')end)
  -- Clear restores both conceal options and leaves ordinary readable source.
  steps[#steps+1]=function()
   vim.cmd('MermanClear')
   local text=capture('disabled')
   assert(text:find('flowchart LR',1,true)and text:find('classDiagram',1,true))
   assert(vim.wo.conceallevel==0 and vim.wo.concealcursor=='v','window options not restored')
   advance()
  end
  advance()
 end,debug.traceback)
 if not ok then finish(false,err)end
end,100)
