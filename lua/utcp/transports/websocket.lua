local auth = require('utcp.auth')
local json = require('utcp.json')
local template = require('utcp.template')

local M, T = {}, {}
T.__index = T

local function websocket_url(url)
  if type(url) ~= 'string' then return nil, 'websocket url is required' end
  local scheme, authority = url:match('^([%a][%w+.-]*)://([^/]+)')
  if not scheme or not authority then return nil, 'invalid WebSocket URL: ' .. url end
  scheme = scheme:lower()
  if scheme == 'wss' then return url end
  if scheme ~= 'ws' then return nil, 'WebSocket URL must use ws:// or wss://' end

  local host = authority:match('@(.+)$') or authority
  if host:sub(1, 1) == '[' then
    host = host:match('^(%b[])')
  else
    host = host:match('^([^:]+)')
  end
  host = host and host:lower()
  if host ~= 'localhost' and host ~= '127.0.0.1' and host ~= '[::1]' then
    return nil, 'plain ws:// is restricted to a literal loopback host'
  end
  return url
end

local function load_websocket(self)
  if self.websocket_module then return self.websocket_module end
  local ok, module = pcall(require, 'http.websocket')
  if not ok then
    return nil, 'lua-http >= 0.4 is required for WebSocket (use Lua 5.3 or 5.4): ' .. tostring(module)
  end
  return module
end

local function decode(value, format)
  if format == 'raw' or format == 'text' then return value end
  local decoded = json.decode(value)
  if decoded ~= nil then return decoded end
  if format == 'json' then return nil, 'WebSocket response is not valid JSON' end
  return value
end

function T.new(config)
  return setmetatable(config or {}, T)
end

function T:auth_metadata()
  return auth.metadata(self.auth)
end

function T:_connect(call_template, args)
  if self._socket and self._socket.readyState ~= 3 then return self._socket end
  local config = call_template or self
  local url = template.render(config.url or self.url, args)
  local valid, url_err = websocket_url(url)
  if not valid then return nil, url_err end

  local module, load_err = load_websocket(self)
  if not module then return nil, load_err end
  local selected_protocol = config.protocol or self.protocol
  local protocols = selected_protocol and {selected_protocol} or nil
  local ok, socket = pcall(module.new_from_uri, url, protocols)
  if not ok or not socket then return nil, 'failed to create WebSocket: ' .. tostring(socket) end

  local headers = {}
  for key, value in pairs(config.headers or self.headers or {}) do
    headers[key] = template.render(value, args)
  end
  for _, key in ipairs(config.header_fields or self.header_fields or {}) do
    if args[key] ~= nil then headers[key] = tostring(args[key]) end
  end
  headers = auth.apply(headers, config.auth or self.auth)
  if socket.request and socket.request.headers then
    for key, value in pairs(headers) do socket.request.headers:upsert(key, tostring(value)) end
  end

  local connected, connect_err = socket:connect(config.timeout or self.timeout or 30)
  if not connected then return nil, 'WebSocket connection failed: ' .. tostring(connect_err) end
  if config.keep_alive ~= false and self.keep_alive ~= false then self._socket = socket end
  return socket
end

function T:_payload(call_template, args)
  local value = call_template.message
  if value == nil then value = call_template.request_data_template end
  if value == nil then value = args end
  value = template.render_utcp(template.render_value(value, args), args)
  if type(value) == 'table' then
    local encoded, err = json.encode(value)
    if not encoded then return nil, err end
    return encoded
  end
  return tostring(value)
end

function T:_finish(socket, call_template)
  if call_template.keep_alive == false or self.keep_alive == false then
    pcall(socket.close, socket)
    if self._socket == socket then self._socket = nil end
  end
end

function T:call(call_template, args)
  call_template, args = call_template or {}, args or {}
  local socket, connect_err = self:_connect(call_template, args)
  if not socket then return nil, connect_err end
  local payload, payload_err = self:_payload(call_template, args)
  if not payload then self:_finish(socket, call_template); return nil, payload_err end
  local sent, send_err = socket:send(payload)
  if not sent then self:_finish(socket, call_template); return nil, tostring(send_err) end
  local response, receive_err = socket:receive(call_template.timeout or self.timeout or 30)
  if response == nil then self:_finish(socket, call_template); return nil, tostring(receive_err) end
  local value, decode_err = decode(response, call_template.response_format or self.response_format)
  self:_finish(socket, call_template)
  return value, decode_err
end

function T:call_stream(call_template, args, on_event)
  if type(on_event) ~= 'function' then return nil, 'WebSocket streaming requires an event callback' end
  call_template, args = call_template or {}, args or {}
  local socket, connect_err = self:_connect(call_template, args)
  if not socket then return nil, connect_err end
  local payload, payload_err = self:_payload(call_template, args)
  if not payload then self:_finish(socket, call_template); return nil, payload_err end
  local sent, send_err = socket:send(payload)
  if not sent then self:_finish(socket, call_template); return nil, tostring(send_err) end

  while true do
    local response, receive_err = socket:receive(call_template.timeout or self.timeout or 30)
    if response == nil then
      self:_finish(socket, call_template)
      if receive_err == nil or tostring(receive_err):match('closed') then return true end
      return nil, tostring(receive_err)
    end
    local value, decode_err = decode(response, call_template.response_format or self.response_format)
    if decode_err then self:_finish(socket, call_template); return nil, decode_err end
    local ok, keep_going = pcall(on_event, value)
    if not ok then
      self:_finish(socket, call_template)
      return nil, 'WebSocket event callback error: ' .. tostring(keep_going)
    end
    if keep_going == false then self:_finish(socket, call_template); return true end
  end
end

function T:register_manual(call_template)
  call_template = call_template or self
  if call_template.manual_request ~= nil then
    local copy = {}
    for key, value in pairs(call_template) do copy[key] = value end
    copy.message = call_template.manual_request
    return self:call(copy, call_template.manual_args or {})
  end
  local socket, err = self:_connect(call_template, {})
  if not socket then return nil, err end
  local response, receive_err = socket:receive(call_template.timeout or self.timeout or 30)
  if not response then return nil, tostring(receive_err) end
  return decode(response, call_template.response_format or 'json')
end

function T:close()
  if self._socket then pcall(self._socket.close, self._socket); self._socket = nil end
  return true
end

M.validate_url = websocket_url
function M.new(config) return T.new(config) end
M.Transport = T
return M
