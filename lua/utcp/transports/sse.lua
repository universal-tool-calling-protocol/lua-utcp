local json = require('utcp.json')
local M = {}; local T = {}; T.__index = T

local function emit_event(on_event, event, id, data)
  if #data == 0 then return true end
  local payload = table.concat(data, '\n')
  local value = json.decode(payload) or payload
  local ok, err = pcall(on_event, {event = event, id = id, data = value, raw = payload})
  if not ok then return nil, tostring(err) end
  return true
end

function T.new(cfg) return setmetatable(cfg or {}, T) end

function T:listen(url, on_event)
  local ok, httpmod = pcall(require, 'socket.http')
  if not ok then return nil, 'lua-socket is required' end
  local ok_ltn12, ltn12 = pcall(require, 'ltn12')
  if not ok_ltn12 then return nil, 'ltn12 is required' end
  if type(on_event) ~= 'function' then return nil, 'SSE requires an event callback' end

  local chunks = {}
  local headers = {}
  for k, v in pairs(self.headers or {}) do headers[k] = v end
  headers.accept = headers.accept or 'text/event-stream'

  local previous_timeout = httpmod.TIMEOUT
  if self.timeout ~= nil then httpmod.TIMEOUT = self.timeout end

  local request_ok, ok_request, code, response_headers, status = pcall(httpmod.request, {
    url = url or self.url,
    method = 'GET',
    headers = headers,
    sink = ltn12.sink.table(chunks),
  })

  httpmod.TIMEOUT = previous_timeout

  if not request_ok then return nil, 'SSE request error: '..tostring(ok_request) end
  if not ok_request or (tonumber(code) and tonumber(code) >= 400) then
    return nil, 'SSE HTTP error: '..tostring(code or status)
  end

  local text = table.concat(chunks)
  local data = {}
  local event = 'message'
  local id = nil

  for line in (text..'\n'):gmatch('(.-)\r?\n') do
    if line == '' then
      local emitted, emit_err = emit_event(on_event, event, id, data)
      if not emitted then return nil, 'SSE event callback error: '..emit_err end
      data = {}; event = 'message'; id = nil
    elseif line:sub(1, 5) == 'data:' then
      data[#data + 1] = line:sub(6):gsub('^ ', '')
    elseif line:sub(1, 6) == 'event:' then
      event = line:sub(7):gsub('^ ', '')
    elseif line:sub(1, 3) == 'id:' then
      id = line:sub(4):gsub('^ ', '')
    end
  end

  return true
end

function M.new(cfg) return T.new(cfg) end
M.Transport = T
return M
