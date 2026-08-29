local json = require('utcp.json')
local auth = require('utcp.auth')

local M = {}
local T = {}
T.__index = T

function T.new(cfg)
  return setmetatable(cfg or {}, T)
end

function T:auth_metadata()
  return auth.metadata(self.auth)
end

function T:call(template_cfg, args)
  local socket = require('socket')
  local client, err = socket.udp()
  if not client then return nil, err end

  client:settimeout(self.timeout or 5)
  local host = template_cfg.host or self.host or '127.0.0.1'
  local port = template_cfg.port or self.port
  if not port then
    client:close()
    return nil, 'udp port is required'
  end

  local encoded = json.encode(template_cfg.payload or template_cfg.body or args)
  if not encoded then
    client:close()
    return nil, 'cannot encode JSON'
  end

  local sent, send_err = client:sendto(encoded, host, port)
  if not sent then
    client:close()
    return nil, send_err
  end

  local response, receive_err = client:receive()
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
