local Registry = {}
Registry.__index = Registry
function Registry.new()
  return setmetatable({tools = {}, providers = {}, _ordered = nil}, Registry)
end
function Registry:add_provider(provider)
  assert(provider and provider.name, 'provider.name is required')
  self.providers[provider.name] = provider
end
function Registry:add_tool(tool, provider)
  assert(tool and tool.name, 'tool.name is required')
  self.tools[tool.name] = {tool = tool, provider = provider}
  self._ordered = nil
end
function Registry:add_manual(manual, provider)
  for _, tool in ipairs(manual.tools or {}) do self:add_tool(tool, provider) end
end
function Registry:get(name) return self.tools[name] end
function Registry:all()
  if not self._ordered then
    local ordered = {}
    for _, item in pairs(self.tools) do ordered[#ordered+1] = item end
    table.sort(ordered, function(a,b) return a.tool.name < b.tool.name end)
    self._ordered = ordered
  end
  return self._ordered
end
function Registry:search(query, tags)
  query = (query or ''):lower(); local out = {}
  for _, item in ipairs(self:all()) do
    local t = item.tool; local hay = (t.name..' '..(t.description or '')):lower(); local ok = query == '' or hay:find(query, 1, true)
    if ok and tags and #tags > 0 then
      local set = {}; for _, x in ipairs(t.tags or {}) do set[x] = true end
      for _, x in ipairs(tags) do if not set[x] then ok = false; break end end
    end
    if ok then out[#out+1] = item end
  end
  return out
end
return Registry
