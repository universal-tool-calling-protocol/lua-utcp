local json=require('utcp.json'); local template=require('utcp.template'); local M={}; local T={}; T.__index=T
function T.new(cfg) return setmetatable(cfg or {},T) end
function T:call(t,args)
  local socket=require('socket'); local host=self.host or t.host or '127.0.0.1'; local port=self.port or t.port; assert(port,'tcp port is required')
  local c,err=socket.tcp(); if not c then return nil,err end; c:settimeout(self.timeout or 10); local ok,e=c:connect(host,port); if not ok then c:close(); return nil,e end
  local payload=t.payload or t.body or args; local s=json.encode(payload); if not s then c:close(); return nil,'cannot encode JSON' end
  local frame=t.frame or self.frame or 'line'; if frame=='line' then c:send(s..'\n') else c:send(s) end
  local out,er=c:receive(frame=='line' and '*l' or '*a'); c:close(); if not out then return nil,er end; local decoded=json.decode(out); if decoded~=nil then return decoded end; return out
end
function M.new(cfg) return T.new(cfg) end
M.Transport=T
return M
