local M = {}
local E = {}
E.__index = E
function E.new(kind, message, fields)
  local e = setmetatable(fields or {}, E)
  e.kind, e.message = kind or 'error', message or 'UTCP error'
  return e
end
function E:__tostring() return string.format('%s: %s', self.kind, self.message) end
function M.new(kind, message, fields) return E.new(kind, message, fields) end
function M.raise(kind, message, fields) error(E.new(kind, message, fields), 2) end
function M.is(err) return type(err) == 'table' and getmetatable(err) == E end
M.Error = E
return M
