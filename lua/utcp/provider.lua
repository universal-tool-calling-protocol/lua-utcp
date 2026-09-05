local json = require('utcp.json')

local M = {}

function M.load(path)
  assert(type(path) == 'string' and path ~= '', 'provider path is required')
  local file, err = io.open(path, 'r')
  if not file then return nil, err end
  local source = file:read('*a')
  file:close()
  local document, decode_err = json.decode(source)
  if not document then return nil, decode_err or 'invalid provider.json' end
  if type(document) ~= 'table' then return nil, 'provider.json must contain a JSON object' end
  if document.manual_call_templates ~= nil then
    if type(document.manual_call_templates) ~= 'table' then
      return nil, 'manual_call_templates must be an array'
    end
    return document
  end
  if not document.name or document.name == '' then return nil, 'provider.name is required' end
  return document
end

return M
