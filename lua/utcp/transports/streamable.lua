local http = require('utcp.transports.http')
local json = require('utcp.json')
local M = {}; local T = {}; T.__index = T

local function is_event_stream(headers)
  local content_type = headers and (headers['content-type'] or headers['Content-Type'])
  return type(content_type) == 'string' and content_type:lower():match('text/event%-stream') ~= nil
end

local function emit_sse(raw, on_event)
  local events = 0
  local data = {}
  local event = 'message'
  local id = nil

  local function flush()
    if #data == 0 then return true end
    local payload = table.concat(data, '\n')
    local value = json.decode(payload) or payload
    local ok, err = pcall(on_event, {event = event, id = id, data = value, raw = payload})
    if not ok then return nil, tostring(err) end
    events = events + 1
    data = {}; event = 'message'; id = nil
    return true
  end

  for line in (raw..'\n'):gmatch('(.-)\r?\n') do
    if line == '' then
      local ok, err = flush()
      if not ok then return nil, err end
    elseif line:sub(1, 5) == 'data:' then
      data[#data + 1] = line:sub(6):gsub('^ ', '')
    elseif line:sub(1, 6) == 'event:' then
      event = line:sub(7):gsub('^ ', '')
    elseif line:sub(1, 3) == 'id:' then
      id = line:sub(4):gsub('^ ', '')
    end
  end

  return events
end

function T.new(cfg) return setmetatable(cfg or {}, T) end

function T:call(template_cfg, args, on_event)
  local t = http.new(self)
  local headers = {}
  for k, v in pairs(template_cfg.headers or {}) do headers[k] = v end
  headers.accept = headers.accept or 'application/json, text/event-stream'
  headers['content-type'] = headers['content-type'] or 'application/json'

  local result, err, response_headers, raw = t:request(
    (template_cfg.http_method or 'POST'):upper(),
    template_cfg.url or self.url,
    template_cfg.body or args,
    headers
  )
  if err then return nil, err end

  if on_event and is_event_stream(response_headers) then
    local count, stream_err = emit_sse(raw or (type(result) == 'string' and result or ''), on_event)
    if not count then return nil, 'Streamable event callback error: '..stream_err end
    return nil, nil, response_headers
  end

  if on_event then
    local ok, callback_err = pcall(on_event, result)
    if not ok then return nil, 'Streamable event callback error: '..tostring(callback_err) end
  end

  return result, nil, response_headers
end

function M.new(cfg) return T.new(cfg) end
M.Transport = T
return M
