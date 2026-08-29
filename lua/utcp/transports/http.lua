local json = require('utcp.json')
local template = require('utcp.template')
local auth = require('utcp.auth')
local M = {}; local T = {}; T.__index = T
local cached_http, cached_ltn12, socket_error

local function socket_http()
  if cached_http then return cached_http, cached_ltn12 end
  if socket_error then return nil, socket_error end
  local ok, http = pcall(require, 'socket.http')
  if not ok then
    socket_error = 'lua-socket is required: ' .. tostring(http)
    return nil, socket_error
  end
  local ok2, ltn12 = pcall(require, 'ltn12')
  if not ok2 then socket_error = 'ltn12 is required'; return nil, socket_error end
  cached_http, cached_ltn12 = http, ltn12
  return cached_http, cached_ltn12
end

local function normalize_error(err)
  err = tostring(err)
  return err:gsub('^.-:%d+: ', '')
end

function T.new(cfg)
  return setmetatable(cfg or {}, T)
end

function T:request(method, url, body, headers)
  local http, ltn12 = socket_http()
  if not http then return nil, ltn12 end

  headers = auth.apply(headers or {}, self.auth)
  local sink = {}
  local payload = body

  if type(body) == 'table' then
    payload = json.encode(body)
    headers['content-type'] = headers['content-type'] or 'application/json'
  end

  if payload then
    headers['content-length'] = tostring(#payload)
  end

  local previous_timeout = http.TIMEOUT
  if self.timeout ~= nil then
    http.TIMEOUT = self.timeout
  end

  local request_ok, ok, code, response_headers, status = pcall(http.request, {
    url = url,
    method = method,
    headers = headers,
    source = payload and ltn12.source.string(payload) or nil,
    sink = ltn12.sink.table(sink),
  })

  http.TIMEOUT = previous_timeout

  if not request_ok then
    return nil, normalize_error(ok), response_headers
  end

  local text = table.concat(sink)
  if not ok then
    return nil, tostring(code), response_headers
  end

  if tonumber(code) >= 400 then
    return nil, 'HTTP '..tostring(code)..' '..(status or ''), response_headers, text
  end

  local decoded = json.decode(text)
  if decoded ~= nil then return decoded, nil, response_headers, text end
  return text, nil, response_headers, text
end

function T:call(template_cfg, args)
  local url = template.render(template_cfg.url or self.url, args)
  local method = (template_cfg.http_method or template_cfg.method or self.method or 'POST'):upper()

  local headers = {}
  for k, v in pairs(template_cfg.headers or self.headers or {}) do
    headers[k] = template.render(v, args)
  end

  local body = template_cfg.body
  if body == nil and method ~= 'GET' and method ~= 'HEAD' then
    body = template_cfg.body_fields or args
  end

  body = template.render_value(body, args)

  if method == 'GET' or method == 'DELETE' then
    local q = template_cfg.query_params or template_cfg.query
    if q then
      local parts = {}
      for k, v in pairs(q) do
        parts[#parts + 1] = k..'='..template.render(v, args)
      end
      if #parts > 0 then
        url = url..(url:find('%?') and '&' or '?')..table.concat(parts, '&')
      end
    end
  end

  return self:request(method, url, body, headers)
end

function M.new(cfg)
  return T.new(cfg)
end

M.Transport = T
return M
