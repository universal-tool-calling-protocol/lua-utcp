local json = require('utcp.json')

local M = {}

function M.load(path)
  assert(type(path) == 'string' and path ~= '', 'provider path is required')
  local file, err = io.open(path, 'r')
  if not file then return nil, err end
  local source = file:read('*a')
  file:close()
  local provider, decode_err = json.decode(source)
  if not provider then return nil, decode_err or 'invalid provider.json' end
  if type(provider) ~= 'table' then return nil, 'provider.json must contain a JSON object' end
  if not provider.name or provider.name == '' then return nil, 'provider.name is required' end
  return provider
end

return M
