local Registry = {}
Registry.__index = Registry
function Registry.new()
  return setmetatable({tools = {}, aliases = {}, providers = {}, _ordered = nil}, Registry)
end
function Registry:add_provider(provider)
  assert(provider and provider.name, 'provider.name is required')
  self.providers[provider.name] = provider
end
function Registry:add_tool(tool, provider)
  assert(tool and tool.name, 'tool.name is required')
  local qualified_name = provider and (provider.name .. '.' .. tool.name) or tool.name
  local previous = self.tools[qualified_name]
  local item = {tool = tool, provider = provider, qualified_name = qualified_name}
  self.tools[qualified_name] = item

  local aliases = self.aliases[tool.name] or {}
  if previous then
    for index, alias in ipairs(aliases) do
      if alias == previous then table.remove(aliases, index); break end
    end
  end
  aliases[#aliases + 1] = item
  self.aliases[tool.name] = aliases
  self._ordered = nil
  return item
end
function Registry:add_manual(manual, provider)
  for _, tool in ipairs(manual.tools or {}) do self:add_tool(tool, provider) end
end
function Registry:get(name, provider)
  local exact = self.tools[name]
  if exact and (not provider or exact.provider == provider) then return exact end
  local aliases = self.aliases[name]
  if not aliases then return nil end
  if provider then
    for _, item in ipairs(aliases) do
      if item.provider == provider then return item end
    end
    return nil
  end
  if #aliases == 1 then return aliases[1] end
  return nil, 'ambiguous UTCP tool name; use manual.tool: ' .. tostring(name)
end

function Registry:remove_provider(provider)
  local provider_name = type(provider) == 'table' and provider.name or provider
  for qualified_name, item in pairs(self.tools) do
    if item.provider and item.provider.name == provider_name then
      self.tools[qualified_name] = nil
      local aliases = self.aliases[item.tool.name] or {}
      for index = #aliases, 1, -1 do
        if aliases[index] == item then table.remove(aliases, index) end
      end
      if #aliases == 0 then self.aliases[item.tool.name] = nil end
    end
  end
  self.providers[provider_name] = nil
  self._ordered = nil
end
function Registry:all()
  if not self._ordered then
    local ordered = {}
    for _, item in pairs(self.tools) do ordered[#ordered+1] = item end
    table.sort(ordered, function(a,b) return a.qualified_name < b.qualified_name end)
    self._ordered = ordered
  end
  return self._ordered
end
function Registry:search(query, tags)
  query = (query or ''):lower(); local out = {}
  for _, item in ipairs(self:all()) do
    local t = item.tool; local hay = (item.qualified_name..' '..t.name..' '..(t.description or '')):lower(); local ok = query == '' or hay:find(query, 1, true)
    if ok and tags and #tags > 0 then
      local set = {}; for _, x in ipairs(t.tags or {}) do set[x] = true end
      ok = false
      for _, x in ipairs(tags) do if set[x] then ok = true; break end end
    end
    if ok then out[#out+1] = item end
  end
  return out
end
return Registry
