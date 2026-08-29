local M = {}

local ownership_values = {
  static = true,
  user = true,
}

local oauth_grant_types = {
  client_credentials = true,
  authorization_code = true,
  device_code = true,
  jwt_bearer = true,
}

local function auth_type(auth)
  -- `type` predates the UTCP-shaped `auth_type` field in this implementation.
  -- Keep accepting it so existing client configuration remains valid.
  return auth.auth_type or auth.type
end

-- Return the auth ownership metadata defined by UTCP issue #62 without
-- mutating the source manual/configuration.  This intentionally only
-- describes a credential's provisioning model; acquiring, refreshing, and
-- storing credentials remains an application concern.
function M.metadata(auth)
  if auth == nil then return nil end
  if type(auth) ~= 'table' then
    return nil, 'UTCP auth must be a table'
  end

  local kind = auth_type(auth)
  if kind == nil or kind == '' then
    return nil, 'UTCP auth.auth_type is required'
  end

  local ownership = auth.ownership or 'static'
  if not ownership_values[ownership] then
    return nil, 'UTCP auth.ownership must be "static" or "user"'
  end

  local grant_type = auth.grant_type
  if kind == 'oauth2' then
    grant_type = grant_type or 'client_credentials'
    if not oauth_grant_types[grant_type] then
      return nil,
        'UTCP auth.grant_type must be "client_credentials", "authorization_code", "device_code", or "jwt_bearer"'
    end
  elseif grant_type ~= nil then
    return nil, 'UTCP auth.grant_type is only valid when auth_type is "oauth2"'
  end

  return {
    auth_type = kind,
    ownership = ownership,
    grant_type = grant_type,
  }
end

function M.apply(headers, auth)
  headers = headers or {}
  auth = auth or {}

  local kind = auth_type(auth)
  if kind == 'bearer' then
    headers['Authorization'] = 'Bearer '..auth.token
  elseif kind == 'oauth2' and (auth.token or auth.access_token) then
    -- Token lifecycle management is deliberately outside UTCP.  When an
    -- application has obtained a token, send it using the OAuth2 bearer
    -- convention while preserving the metadata for the caller to inspect.
    headers['Authorization'] = 'Bearer '..(auth.token or auth.access_token)
  elseif kind == 'basic' then
    local b = require('mime').b64(auth.username..':'..auth.password)
    headers['Authorization'] = 'Basic '..b
  elseif kind == 'api_key' then
    headers[auth.header or auth.var_name or 'X-API-Key'] = auth.api_key
  elseif kind == 'header' then
    headers[auth.name] = auth.value
  end

  for k, v in pairs(auth.headers or {}) do headers[k] = v end
  return headers
end

return M
