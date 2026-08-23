local json = require('utcp.json')
local M = {}

local function tostring_safe(v)
  if v == nil then return '' end
  if type(v) == 'string' or type(v) == 'number' or type(v) == 'boolean' then return tostring(v) end
  local s, err = json.encode(v)
  if not s then error(err) end
  return s
end

local function lookup(args, key)
  local v = args[key]
  if v ~= nil then return v end

  local cur = args
  for part in key:gmatch('[^%.]+') do
    if type(cur) ~= 'table' then return nil end
    cur = cur[part]
  end
  return cur
end

-- Render a scalar template as text. This is appropriate for URLs,
-- headers and other string-valued template fields.
function M.render(s, args)
  if type(s) ~= 'string' then return s end
  args = args or {}
  return (s:gsub('{([%w_%.%-]+)}', function(k)
    return tostring_safe(lookup(args, k))
  end))
end

-- Render a request value while preserving argument types. An exact
-- placeholder such as "{a}" resolves to the original number/boolean/table
-- instead of turning it into the string "10". Embedded placeholders remain
-- strings, e.g. "/items/{id}" -> "/items/42".
function M.render_value(value, args)
  args = args or {}

  if type(value) == 'string' then
    local key = value:match('^%s*{([%w_%.%-]+)}%s*$')
    if key then
      local resolved = lookup(args, key)
      if resolved ~= nil then return resolved end
    end
    return M.render(value, args)
  end

  if type(value) == 'table' then
    local out = {}
    for k, v in pairs(value) do
      out[k] = M.render_value(v, args)
    end
    return out
  end

  return value
end

function M.query(args)
  local out = {}
  for k,v in pairs(args or {}) do
    if type(v) ~= 'table' then out[#out+1] = tostring(k)..'='..tostring(v) end
  end
  return table.concat(out, '&')
end

return M
