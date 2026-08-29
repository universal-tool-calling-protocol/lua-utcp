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

function T:call(template_cfg)
  local path = template_cfg.path or template_cfg.file or self.path
  assert(path, 'text path is required')

  local file, err = io.open(path, 'r')
  if not file then return nil, err end

  local text = file:read('*a')
  file:close()

  local decoded = json.decode(text)
  if decoded ~= nil then return decoded end
  return text
end

function M.new(cfg)
  return T.new(cfg)
end

M.Transport = T
return M
