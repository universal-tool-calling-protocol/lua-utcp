local http=require('utcp.transports.http'); local M={}; local T={}; T.__index=T
function T.new(cfg) return setmetatable(cfg or {},T) end
function T:call(t,args)
  local body={query=t.query or t.document, variables=t.variables or args, operationName=t.operation_name}; return http.new(self):request('POST',t.url or self.url,body,t.headers or self.headers)
end
function M.new(cfg) return T.new(cfg) end
M.Transport=T
return M
