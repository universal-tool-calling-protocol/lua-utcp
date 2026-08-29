local http = require('utcp.transports.http')

local M = {}
local T = {}
T.__index = T

function T.new(cfg)
  return setmetatable(cfg or {}, T)
end

function T:call(template_cfg, args)
  local body = {
    query = template_cfg.query or template_cfg.document,
    variables = template_cfg.variables or args,
    operationName = template_cfg.operation_name,
  }

  return http.new(self):request(
    'POST',
    template_cfg.url or self.url,
    body,
    template_cfg.headers or self.headers
  )
end

function M.new(cfg)
  return T.new(cfg)
end

M.Transport = T
return M
