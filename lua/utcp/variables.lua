local M = {}

local function namespaced_key(namespace, key)
  if not namespace or namespace == '' then return nil end
  return namespace:gsub('_', '__') .. '_' .. key
end

local function lookup(values, namespace, key)
  local qualified = namespaced_key(namespace, key)
  if qualified and values[qualified] ~= nil then return values[qualified] end
  if values[key] ~= nil then return values[key] end
  return os.getenv(key)
end

local function load_dotenv(path, values)
  local file, err = io.open(path, 'r')
  if not file then return nil, err end
  for line in file:lines() do
    local key, value = line:match('^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$')
    if key and value then
      local quote = value:sub(1, 1)
      if (quote == '"' or quote == "'") and value:sub(-1) == quote then
        value = value:sub(2, -2)
      end
      if values[key] == nil then values[key] = value end
    end
  end
  file:close()
  return true
end

function M.load(config)
  local values = {}
  for key, value in pairs(config.variables or {}) do values[key] = value end
  for _, loader in ipairs(config.load_variables_from or {}) do
    local kind = loader.variable_loader_type or loader.type
    if kind == 'dotenv' then
      local ok, err = load_dotenv(loader.env_file_path or loader.path or '.env', values)
      if not ok and loader.optional ~= true then return nil, err end
    elseif kind ~= 'environment' and kind ~= 'env' then
      return nil, 'unsupported variable loader: ' .. tostring(kind)
    end
  end
  return values
end

function M.substitute(value, values, namespace, strict, seen)
  if type(value) == 'string' then
    local exact = value:match('^%${([%a_][%w_]*)}$')
    if exact then
      local resolved = lookup(values, namespace, exact)
      if resolved ~= nil then return resolved end
      if strict then return nil, 'missing UTCP variable: ' .. exact end
      return value
    end

    local missing
    local rendered = value:gsub('%${([%a_][%w_]*)}', function(key)
      local resolved = lookup(values, namespace, key)
      if resolved == nil then missing = missing or key; return '${' .. key .. '}' end
      return tostring(resolved)
    end)
    if strict and missing then return nil, 'missing UTCP variable: ' .. missing end
    return rendered
  end

  if type(value) == 'table' then
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    setmetatable(out, getmetatable(value))
    for key, item in pairs(value) do
      local resolved, err = M.substitute(item, values, namespace, strict, seen)
      if err then return nil, err end
      out[key] = resolved
    end
    return out
  end
  return value
end

local function collect(value, out, seen)
  if type(value) == 'string' then
    for key in value:gmatch('%${([%a_][%w_]*)}') do out[key] = true end
  elseif type(value) == 'table' then
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for _, item in pairs(value) do collect(item, out, seen) end
  end
end

function M.required(value, values, namespace)
  local found, missing = {}, {}
  collect(value, found)
  for key in pairs(found) do
    if lookup(values or {}, namespace, key) == nil then missing[#missing + 1] = key end
  end
  table.sort(missing)
  return missing
end

function M.find_required(value)
  local found, names = {}, {}
  collect(value, found)
  for key in pairs(found) do names[#names + 1] = key end
  table.sort(names)
  return names
end

return M
