local json = require('utcp.json')

local M = {}
local T = {}
T.__index = T

function T.new(cfg)
  return setmetatable(cfg or {}, T)
end

function T:call(template_cfg, args)
  local socket = require('socket')
  local host = self.host or template_cfg.host or '127.0.0.1'
  local port = self.port or template_cfg.port
  assert(port, 'tcp port is required')

  local client, err = socket.tcp()
  if not client then return nil, err end

  client:settimeout(self.timeout or 10)
  local connected, connect_err = client:connect(host, port)
  if not connected then
    client:close()
    return nil, connect_err
  end

  local payload = template_cfg.payload or template_cfg.body or args
  local encoded = json.encode(payload)
  if not encoded then
    client:close()
    return nil, 'cannot encode JSON'
  end

  local frame = template_cfg.frame or self.frame or 'line'
  local sent, send_err = client:send(frame == 'line' and encoded .. '\n' or encoded)
  if not sent then
    client:close()
    return nil, send_err
  end

  local response, receive_err = client:receive(frame == 'line' and '*l' or '*a')
  client:close()
  if not response then return nil, receive_err end

  local decoded = json.decode(response)
  if decoded ~= nil then return decoded end
  return response
end

function M.new(cfg)
  return T.new(cfg)
end

M.Transport = T
return M
