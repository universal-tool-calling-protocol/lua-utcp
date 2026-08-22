local http = require('utcp.transports.http')
local json = require('utcp.json')
local M={}; local T={}; T.__index=T
function T.new(cfg) return setmetatable(cfg or {},T) end
function T:listen(url, on_event)
  local ok = pcall(require,'socket.http')
  if not ok then return nil,'lua-socket is required' end
  local httpmod = require('socket.http'); local ltn12 = require('ltn12'); local chunks={}
  local headers=self.headers or {}; headers.accept='text/event-stream'
  local ok,code,rh,status=httpmod.request{url=url or self.url,method='GET',headers=headers,sink=ltn12.sink.table(chunks)}
  if not ok or tonumber(code)>=400 then return nil,'SSE HTTP error: '..tostring(code or status) end
  local text=table.concat(chunks); local data={}; local event='message'; local id=nil
  for line in (text..'\n'):gmatch('(.-)\r?\n') do
    if line=='' then
      if #data>0 then local payload=table.concat(data,'\n'); local value=json.decode(payload) or payload; on_event({event=event,id=id,data=value,raw=payload}); data={}; event='message'; id=nil end
    elseif line:sub(1,5)=='data:' then data[#data+1]=line:sub(6):gsub('^ ','')
    elseif line:sub(1,6)=='event:' then event=line:sub(7):gsub('^ ','')
    elseif line:sub(1,3)=='id:' then id=line:sub(4):gsub('^ ','') end
  end
  return true
end
function M.new(cfg) return T.new(cfg) end
M.Transport=T
return M
