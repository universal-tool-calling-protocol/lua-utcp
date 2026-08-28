local json=require('utcp.json'); local M={}; local T={}; T.__index=T
function T.new(cfg) return setmetatable(cfg or {},T) end
function T:call(t,args)
  local socket=require('socket'); local u=socket.udp(); u:settimeout(self.timeout or 5); local host=t.host or self.host or '127.0.0.1'; local port=t.port or self.port; local s=json.encode(t.payload or t.body or args); if not s then return nil,'cannot encode JSON' end
  local ok,e=u:sendto(s,host,port); if not ok then u:close(); return nil,e end; local out,er=u:receive(); u:close(); if not out then return nil,er end; local decoded=json.decode(out); if decoded~=nil then return decoded end; return out
end
function M.new(cfg) return T.new(cfg) end
M.Transport=T
return M
