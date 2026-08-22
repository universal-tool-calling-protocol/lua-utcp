local json=require('utcp.json'); local M={}; local T={}; T.__index=T
function T.new(cfg) return setmetatable(cfg or {},T) end
local function shellquote(s) return "'"..tostring(s):gsub("'","'\\''").."'" end
function T:call(t,args)
  local cmd=t.command or self.command; assert(cmd,'cli command is required'); local parts={cmd}
  for _,v in ipairs(t.args or self.args or {}) do parts[#parts+1]=shellquote(type(v)=='string' and v or json.encode(v)) end
  if t.pass_args or self.pass_args then for k,v in pairs(args or {}) do parts[#parts+1]=shellquote('--'..k); parts[#parts+1]=shellquote(v) end end
  local p=assert(io.popen(table.concat(parts,' ')..' 2>&1','r')); local out=p:read('*a'); local ok,_,code=p:close(); if code and code~=0 then return nil,out end; return json.decode(out) or out
end
function M.new(cfg) return T.new(cfg) end
M.Transport=T
return M
