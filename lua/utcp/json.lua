local M = {}
local backend
for _, name in ipairs({'cjson.safe', 'cjson', 'dkjson'}) do
  local ok, mod = pcall(require, name)
  if ok then backend = mod; break end
end
function M.available() return backend ~= nil end
function M.encode(v)
  if not backend then return nil, 'no JSON backend; install lua-cjson or dkjson' end
  local ok, out = pcall(backend.encode, v)
  if not ok then return nil, out end
  return out
end
function M.decode(s)
  if not backend then return nil, 'no JSON backend; install lua-cjson or dkjson' end
  local ok, out, err = pcall(backend.decode, s)
  if not ok then return nil, out end
  if out == nil and err then return nil, err end
  return out
end
return M
