local json = require('utcp.json')
local M = {}
local function tostring_safe(v)
  if v == nil then return '' end
  if type(v) == 'string' or type(v) == 'number' or type(v) == 'boolean' then return tostring(v) end
  local s, err = json.encode(v); if not s then error(err) end; return s
end
function M.render(s, args)
  if type(s) ~= 'string' then return s end
  args = args or {}
  return (s:gsub('{([%w_%.%-]+)}', function(k)
    local v = args[k]
    if v == nil then
      local cur = args
      for part in k:gmatch('[^%.]+') do cur = type(cur) == 'table' and cur[part] or nil end
      v = cur
    end
    return tostring_safe(v)
  end))
end
function M.query(args)
  local out = {}
  for k,v in pairs(args or {}) do
    if type(v) ~= 'table' then out[#out+1] = tostring(k)..'='..tostring(v) end
  end
  return table.concat(out, '&')
end
return M
