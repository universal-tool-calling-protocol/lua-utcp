local json=require('utcp.json'); local M={}; local T={}; T.__index=T
function T.new(cfg) return setmetatable(cfg or {},T) end
function T:call(t,args)
  local path=t.path or t.file or self.path; assert(path,'text path is required'); local f,err=io.open(path,'r'); if not f then return nil,err end; local s=f:read('*a'); f:close(); return json.decode(s) or s
end
function M.new(cfg) return T.new(cfg) end
M.Transport=T
return M
