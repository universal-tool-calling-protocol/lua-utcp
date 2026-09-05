local auth = require('utcp.auth')
local json = require('utcp.json')
local template = require('utcp.template')

local M, T = {}, {}
T.__index = T

local function invoke(object, names, ...)
  for _, name in ipairs(names) do
    if type(object[name]) == 'function' then return object[name](object, ...) end
  end
  return nil, 'WebRTC adapter does not implement ' .. table.concat(names, ' or ')
end

local function decode(value, format)
  if format == 'raw' or format == 'text' then return value end
  local decoded = json.decode(value)
  if decoded ~= nil then return decoded end
  if format == 'json' then return nil, 'WebRTC response is not valid JSON' end
  return value
end

function T.new(config) return setmetatable(config or {}, T) end

function T:auth_metadata()
  return auth.metadata(self.auth)
end

function T:_connect(config)
  if self._peer then return self._peer end
  local peer = config.data_channel or config.peer or self.data_channel or self.peer
  local factory = config.peer_factory or self.peer_factory
  if not peer and factory then peer = factory(config) end
  if not peer then
    local module_name = config.webrtc_module or self.webrtc_module
    if type(module_name) == 'string' then
      local ok, module = pcall(require, module_name)
      if not ok then return nil, 'cannot load WebRTC binding: ' .. tostring(module) end
      if type(module.new) == 'function' then peer = module.new(config) end
    elseif type(module_name) == 'table' and type(module_name.new) == 'function' then
      peer = module_name.new(config)
    end
  end
  if not peer then
    return nil, 'WebRTC requires data_channel, peer_factory, or a webrtc_module binding'
  end
  if type(peer.connect) == 'function' then
    local connected, err = peer:connect(config)
    if connected == nil or connected == false then return nil, err or 'WebRTC connection failed' end
  end
  self._peer = peer
  return peer
end

function T:_payload(config, args)
  local value = config.message or config.request_data_template or args
  value = template.render_utcp(template.render_value(value, args), args)
  if type(value) == 'table' then return json.encode(value) end
  return tostring(value)
end

function T:call(call_template, args)
  local config = call_template or self
  args = args or {}
  local peer, connect_err = self:_connect(config)
  if not peer then return nil, connect_err end
  local payload, payload_err = self:_payload(config, args)
  if not payload then return nil, payload_err end
  local sent, send_err = invoke(peer, {'send', 'send_message', 'sendMessage'}, payload)
  if sent == nil or sent == false then return nil, send_err end
  local response, receive_err = invoke(peer, {'receive', 'recv'}, config.timeout or self.timeout or 30)
  if response == nil then return nil, receive_err end
  return decode(response, config.response_format or self.response_format)
end

function T:call_stream(call_template, args, on_event)
  if type(on_event) ~= 'function' then return nil, 'WebRTC streaming requires an event callback' end
  local config = call_template or self
  local peer, connect_err = self:_connect(config)
  if not peer then return nil, connect_err end
  local payload, payload_err = self:_payload(config, args or {})
  if not payload then return nil, payload_err end
  local sent, send_err = invoke(peer, {'send', 'send_message', 'sendMessage'}, payload)
  if sent == nil or sent == false then return nil, send_err end
  while true do
    local response, receive_err = invoke(peer, {'receive', 'recv'}, config.timeout or self.timeout or 30)
    if response == nil then
      if receive_err == nil or tostring(receive_err):match('closed') then return true end
      return nil, receive_err
    end
    local value, decode_err = decode(response, config.response_format or self.response_format)
    if decode_err then return nil, decode_err end
    local ok, keep_going = pcall(on_event, value)
    if not ok then return nil, 'WebRTC event callback error: ' .. tostring(keep_going) end
    if keep_going == false then return true end
  end
end

function T:register_manual(call_template)
  local config = call_template or self
  if config.manual_request ~= nil then
    local copy = {}
    for key, value in pairs(config) do copy[key] = value end
    copy.message = config.manual_request
    return self:call(copy, config.manual_args or {})
  end
  local peer, err = self:_connect(config)
  if not peer then return nil, err end
  local response, receive_err = invoke(peer, {'receive', 'recv'}, config.timeout or self.timeout or 30)
  if response == nil then return nil, receive_err end
  return decode(response, config.response_format or 'json')
end

function T:close()
  if self._peer then invoke(self._peer, {'close', 'disconnect'}); self._peer = nil end
  return true
end

function M.new(config) return T.new(config) end
M.Transport = T
return M
