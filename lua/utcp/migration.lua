local M = {}

local function copy(value, seen)
  if type(value) ~= 'table' then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = setmetatable({}, getmetatable(value))
  seen[value] = out
  for key, item in pairs(value) do out[copy(key, seen)] = copy(item, seen) end
  return out
end

local function migrate_template(value)
  local template = copy(value or {})
  template.call_template_type = template.call_template_type
    or template.provider_type
    or template.transport
    or template.type
  template.provider_type = nil

  if template.method and not template.http_method then
    template.http_method = template.method
  end
  if template.cwd and not template.working_dir then
    template.working_dir = template.cwd
  end
  return template
end

function M.manual(value)
  if type(value) ~= 'table' then return nil, 'UTCP manual must be a table' end
  local manual = copy(value)
  if type(manual.tools) ~= 'table' then return nil, 'UTCP manual must contain tools' end

  if manual.provider_info and not manual.info then
    manual.info = {
      title = manual.provider_info.title or manual.provider_info.name,
      version = manual.provider_info.version,
      description = manual.provider_info.description,
    }
  end

  for index, source_tool in ipairs(manual.tools) do
    if type(source_tool) ~= 'table' then
      return nil, 'UTCP tool at index ' .. index .. ' must be a table'
    end
    local tool = copy(source_tool)
    tool.inputs = tool.inputs or tool.parameters or {type = 'object', properties = {}}
    tool.parameters = nil
    local template = tool.tool_call_template or tool.call_template or tool.provider
    if template then tool.tool_call_template = migrate_template(template) end
    tool.call_template = nil
    tool.provider = nil
    manual.tools[index] = tool
  end

  local legacy = type(manual.utcp_version) == 'string'
    and manual.utcp_version:match('^0%.1') ~= nil
  manual.manual_version = manual.manual_version or '1.0.0'
  if legacy then manual.utcp_version = '1.1.0' end
  manual.utcp_version = manual.utcp_version or '1.1.0'
  manual.provider_info = nil
  return manual
end

function M.config(value)
  if type(value) ~= 'table' then return nil, 'UTCP client config must be a table' end
  local config = copy(value)
  if config.manual_call_templates == nil and config.providers ~= nil then
    config.manual_call_templates = {}
    for index, provider in ipairs(config.providers) do
      config.manual_call_templates[index] = migrate_template(provider)
    end
  else
    for index, template in ipairs(config.manual_call_templates or {}) do
      config.manual_call_templates[index] = migrate_template(template)
    end
  end
  return config
end

M.call_template = migrate_template
M.copy = copy
return M
