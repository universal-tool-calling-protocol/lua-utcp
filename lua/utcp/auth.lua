local M = {}
function M.apply(headers, auth)
  headers = headers or {}; auth = auth or {}
  if auth.type == 'bearer' then headers['Authorization'] = 'Bearer '..auth.token
  elseif auth.type == 'basic' then
    local b = require('mime').b64(auth.username..':'..auth.password); headers['Authorization'] = 'Basic '..b
  elseif auth.type == 'api_key' then headers[auth.header or 'X-API-Key'] = auth.api_key
  elseif auth.type == 'header' then headers[auth.name] = auth.value end
  for k,v in pairs(auth.headers or {}) do headers[k] = v end
  return headers
end
return M
