local http=require('utcp.transports.http'); local M={}; local T={}; T.__index=T
function T.new(cfg) return setmetatable(cfg or {},T) end
function T:call(template_cfg,args,on_event)
  local t=http.new(self); local headers={}; for k,v in pairs(template_cfg.headers or {}) do headers[k]=v end
  headers.accept=headers.accept or 'application/json, text/event-stream'; headers['content-type']=headers['content-type'] or 'application/json'
  local result,err,rh,raw=t:request((template_cfg.http_method or 'POST'):upper(), template_cfg.url or self.url, template_cfg.body or args, headers)
  if err then return nil,err end
  if on_event then on_event(result) end
  return result,nil,rh
end
function M.new(cfg) return T.new(cfg) end
M.Transport=T
return M
