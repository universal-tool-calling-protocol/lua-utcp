local json = require('utcp.json')
local Registry = require('utcp.registry')
local transports = require('utcp.transports')
local errors = require('utcp.errors')
local Guard = require('utcp.guard')
local auth = require('utcp.auth')
local protocol = require('utcp.protocol')
local migration = require('utcp.migration')
local variable_support = require('utcp.variables')

local Client = {}
Client.__index = Client

local function provider_transport_type(provider)
  return protocol.type(provider, 'http')
end

local function tool_transport_type(template_cfg, provider)
  return protocol.type(template_cfg, provider and provider_transport_type(provider) or 'http')
end

local function merged_config(provider, template_cfg, values)
  local config = {}

  if provider then
    for key, value in pairs(provider) do
      config[key] = value
    end
  end

  for key, value in pairs(template_cfg) do
    config[key] = value
  end

  return variable_support.substitute(config, values or {}, provider and provider.name, true)
end

local function metadata_for_config(config)
  if config.auth == nil then return nil end
  return auth.metadata(config.auth)
end

local function mcp_manual(listed_tools)
  local tools = {}

  for _, tool in ipairs((listed_tools or {}).tools or {}) do
    tools[#tools + 1] = {
      name = tool.name,
      description = tool.description,
      inputs = {
        type = 'object',
        properties = (tool.inputSchema or {}).properties or {},
      },
      tool_call_template = {
        call_template_type = 'mcp',
        name = tool.name,
        arguments_path = 'arguments',
      },
    }
  end

  return {
    manual_version = '1.0',
    utcp_version = '1.0',
    tools = tools,
  }
end

function Client.new(cfg)
  cfg = cfg or {}
  if type(cfg) == 'string' then
    local file, open_err = io.open(cfg, 'r')
    if not file then return nil, open_err end
    local source = file:read('*a')
    file:close()
    local decoded, decode_err = json.decode(source)
    if type(decoded) ~= 'table' then return nil, decode_err or 'invalid UTCP client config' end
    cfg = decoded
  end
  local migrated, migration_err = migration.config(cfg)
  if not migrated then return nil, migration_err end
  cfg = migrated
  local variable_values, variable_err = variable_support.load(cfg)
  if not variable_values then return nil, variable_err end

  local self = setmetatable({
    config = cfg,
    variables = variable_values,
    registry = Registry.new(),
    providers = {},
    manuals = {},
    _discovered = {},
    _provider_transports = {},
    _tool_transports = {},
  }, Client)

  for _, provider in ipairs(cfg.manual_call_templates or cfg.providers or {}) do
    local added, add_err = self:add_provider(provider)
    if not added then return nil, add_err end
  end

  if cfg.manual then
    local response, manual_err = self:add_manual(cfg.manual)
    if not response then return nil, manual_err end
  end

  return self
end

function Client:add_provider(provider)
  if type(provider) ~= 'table' then return nil, 'provider must be a table' end
  if provider.manual_call_templates then
    local added = {}
    for _, call_template in ipairs(provider.manual_call_templates) do
      local value, err = self:add_provider(call_template)
      if not value then
        for _, previous in ipairs(added) do self:deregister_manual(previous.name) end
        return nil, err
      end
      added[#added + 1] = value
    end
    return added
  end
  if type(provider.name) ~= 'string' or provider.name == '' then
    return nil, 'provider.name is required'
  end
  if self.providers[provider.name] then
    return nil, 'manual already registered: ' .. provider.name
  end

  self.providers[provider.name] = provider
  self.registry:add_provider(provider)
  self._discovered[provider] = nil
  self._provider_transports[provider] = nil

  if provider.manual then
    local response, manual_err = self:add_manual(provider.manual, provider)
    if not response then
      self.providers[provider.name] = nil
      self.registry:remove_provider(provider)
      return nil, manual_err
    end
    self._discovered[provider] = provider.manual
  elseif provider.tools then
    local manual = {tools = provider.tools}
    local response, manual_err = self:add_manual(manual, provider)
    if not response then
      self.providers[provider.name] = nil
      self.registry:remove_provider(provider)
      return nil, manual_err
    end
    self._discovered[provider] = manual
  end

  return provider
end

function Client:load_provider(path)
  local document, load_err = require('utcp.provider').load(path)
  if not document then
    return nil, load_err or 'failed to load provider: ' .. tostring(path)
  end

  return self:add_provider(document)
end

function Client:add_manual(manual, provider)
  local normalized, manual_err = migration.manual(manual)
  if not normalized then return nil, manual_err end
  local registered, skipped = {}, {}
  local allowed, allowed_err
  if provider then
    allowed, allowed_err = protocol.allowed(provider)
    if not allowed then return nil, allowed_err end
  end

  for _, tool in ipairs(normalized.tools) do
    if type(tool.name) ~= 'string' or tool.name == '' then
      return nil, 'UTCP tool.name is required'
    end
    local template_cfg = tool.tool_call_template or tool
    local transport_type = tool_transport_type(template_cfg, provider)
    if not transport_type then
      skipped[#skipped + 1] = {name = tool.name, reason = 'unsupported UTCP transport'}
    elseif allowed and not allowed[transport_type] then
      local reason = "tool protocol '" .. transport_type .. "' is not allowed by manual '"
        .. provider.name .. "' (allowed: " .. protocol.display_allowed(allowed) .. ')'
      skipped[#skipped + 1] = {name = tool.name, reason = reason}
      if self.config.warnings ~= false then
        io.stderr:write('lua-utcp warning: ' .. reason .. '\n')
      end
    else
      local previous = self.registry:get(tool.name, provider)
      if previous then self._tool_transports[previous.tool] = nil end
      local item = self.registry:add_tool(tool, provider)
      tool.qualified_name = item.qualified_name
      registered[#registered + 1] = tool
    end
  end
  local manual_name = provider and provider.name or normalized.info and normalized.info.title
  if manual_name then self.manuals[manual_name] = normalized end
  return {manual = normalized, registered_tools = registered, skipped_tools = skipped}
end

function Client:_transport(provider)
  local transport_type = provider_transport_type(provider)
  if not transport_type then
    return nil, 'unsupported UTCP transport'
  end
  local module = transports[transport_type]
  if not module then return nil, 'unsupported UTCP transport: ' .. transport_type end
  local config, config_err = variable_support.substitute(provider, self.variables, provider.name, true)
  if not config then return nil, config_err end

  if transport_type == 'mcp' or transport_type == 'websocket'
      or transport_type == 'grpc' or transport_type == 'webrtc' then
    local cached = self._provider_transports[provider]
    if cached then
      return cached
    end

    cached = module.new(config)
    self._provider_transports[provider] = cached
    return cached
  end

  return module.new(config)
end

function Client:_discover_provider(provider)
  local cached = self._discovered[provider]
  if cached then
    return cached
  end

  if provider.manual then
    local response, manual_err = self:add_manual(provider.manual, provider)
    if not response then return nil, manual_err end
    self._discovered[provider] = provider.manual
    return provider.manual
  end

  local transport, transport_err = self:_transport(provider)
  if not transport then return nil, transport_err end
  local resolved_provider, resolve_err = variable_support.substitute(
    provider, self.variables, provider.name, true
  )
  if not resolved_provider then return nil, resolve_err end
  local manual

  if resolved_provider.discovery then
    if resolved_provider.discovery.method == 'GET' or resolved_provider.discovery.url then
      local result, err = transport:request(
        'GET',
        resolved_provider.discovery.url or resolved_provider.url,
        resolved_provider.discovery.body,
        resolved_provider.discovery.headers
      )
      if err then
        return nil, err
      end

      manual = result
    end
  elseif resolved_provider.tools_url or resolved_provider.discovery_url then
    local result, err = transport:request(
      'GET',
      resolved_provider.tools_url or resolved_provider.discovery_url,
      nil,
      resolved_provider.headers
    )
    if err then
      return nil, err
    end

    manual = result
  elseif provider_transport_type(provider) == 'mcp' then
    local _, initialize_err = transport:initialize()
    if initialize_err then
      return nil, initialize_err
    end

    local listed_tools, list_err = transport:list_tools()
    if list_err then
      return nil, list_err
    end

    manual = mcp_manual(listed_tools)
  elseif type(transport.register_manual) == 'function' then
    local result, register_err = transport:register_manual(resolved_provider)
    if not result then return nil, register_err end
    manual = result
  end

  if manual then
    local response, manual_err = self:add_manual(manual, provider)
    if not response then return nil, manual_err end
    self._discovered[provider] = manual
    return manual
  end

  return nil, 'provider has no discoverable manual'
end

function Client:discover()
  local manuals = {}

  for _, provider in pairs(self.providers) do
    local manual, err = self:_discover_provider(provider)
    if not manual then
      return nil, err
    end

    manuals[#manuals + 1] = manual
  end

  return manuals
end

function Client:list_tools()
  local tools = {}

  for _, item in ipairs(self.registry:all()) do
    tools[#tools + 1] = item.tool
  end

  return tools
end

function Client:find_tool(name)
  local item, lookup_err = self.registry:get(name)
  if item then
    return item.tool, item.provider
  end

  return nil, lookup_err or 'unknown UTCP tool: ' .. tostring(name)
end

-- Return the structured ownership metadata for a tool's effective auth block.
-- A tool-level auth block overrides the provider-level block, matching the
-- transport configuration used by call_tool.
function Client:auth_metadata(name)
  local tool, provider = self:find_tool(name)
  if not tool then
    tool, provider = self:_discover_tool(name)
  end
  if not tool then return nil, provider end

  local template_cfg = tool.tool_call_template or tool.call_template or tool
  local config, config_err = merged_config(provider, template_cfg, self.variables)
  if not config then return nil, config_err end
  return metadata_for_config(config)
end

function Client:_discover_tool(name)
  local provider_name, tool_name = type(name) == 'string' and name:match(
    '^([A-Za-z_][A-Za-z0-9_-]*)%.([A-Za-z_][A-Za-z0-9_.-]*)$'
  )

  if provider_name then
    local provider = self.providers[provider_name]
    if not provider then
      return nil, 'unknown UTCP tool: ' .. tostring(name)
    end

    local manual, err = self:_discover_provider(provider)
    if not manual then
      return nil, err
    end

    return self:find_tool(provider_name .. '.' .. tool_name)
  end

  local discovery_err
  for _, provider in pairs(self.providers) do
    local discovered, err = self:_discover_provider(provider)
    if not discovered then
      discovery_err = err
    else
      local tool, tool_provider = self:find_tool(name)
      if tool then
        return tool, tool_provider
      end
    end
  end

  if discovery_err then
    return nil, discovery_err
  end

  return nil, 'unknown UTCP tool: ' .. tostring(name)
end

function Client:_tool_transport(tool, provider, transport_type, config)
  local transport = self._tool_transports[tool]
  local module = transports[transport_type]
  if not module then return nil, 'unsupported UTCP transport: ' .. tostring(transport_type) end

  if (transport_type == 'mcp' or transport_type == 'websocket'
      or transport_type == 'grpc' or transport_type == 'webrtc') and provider
      and provider_transport_type(provider) == transport_type then
    transport = transport or self._provider_transports[provider]
    if not transport then
      transport = module.new(config)
      self._provider_transports[provider] = transport
    end
  elseif not transport then
    transport = module.new(config)
  end

  self._tool_transports[tool] = transport
  return transport
end

function Client:call_tool(name, args)
  local call_args = args or {}
  local allowed, guard_err = Guard.evaluate(self.config.guard, {
    tool_name = name,
    args = call_args,
    client = self,
  })
  if not allowed then
    return nil, guard_err
  end

  local tool, provider = self:find_tool(name)
  if not tool then
    tool, provider = self:_discover_tool(name)
  end

  if not tool then
    return nil, provider
  end

  local template_cfg = tool.tool_call_template or tool.call_template or tool
  local transport_type = tool_transport_type(template_cfg, provider)
  if not transport_type then
    return nil, 'unsupported UTCP transport'
  end

  local protocol_allowed, allowed_values = protocol.is_allowed(provider, transport_type)
  if not protocol_allowed then
    local detail = type(allowed_values) == 'table' and protocol.display_allowed(allowed_values) or tostring(allowed_values)
    return nil, errors.new('protocol_not_allowed',
      "tool '" .. tostring(name) .. "' uses disallowed protocol '" .. transport_type .. "'",
      {tool_name = name, protocol = transport_type, allowed_protocols = detail})
  end

  local config, config_err = merged_config(provider, template_cfg, self.variables)
  if not config then return nil, config_err end
  local _, auth_err = metadata_for_config(config)
  if auth_err then return nil, auth_err end

  local transport, transport_err = self:_tool_transport(tool, provider, transport_type, config)
  if not transport then return nil, transport_err end

  if transport_type == 'mcp' then
    return transport:call_tool(config.name or template_cfg.name or name, call_args)
  end

  return transport:call(config, call_args)
end

function Client:call_tool_stream(name, args, on_event)
  local call_args = args or {}
  local guard_allowed, guard_err = Guard.evaluate(self.config.guard, {
    tool_name = name, args = call_args, client = self,
  })
  if not guard_allowed then return nil, guard_err end
  local tool, provider = self:find_tool(name)
  if not tool then
    tool, provider = self:_discover_tool(name)
  end
  if not tool then return nil, provider end

  local template_cfg = tool.tool_call_template or tool.call_template or tool
  local transport_type = tool_transport_type(template_cfg, provider)
  if not transport_type then return nil, 'unsupported UTCP transport' end
  local protocol_allowed, allowed_values = protocol.is_allowed(provider, transport_type)
  if not protocol_allowed then
    return nil, errors.new('protocol_not_allowed',
      "tool '" .. tostring(name) .. "' uses disallowed protocol '" .. transport_type .. "'",
      {tool_name = name, protocol = transport_type, allowed_protocols = protocol.display_allowed(allowed_values)})
  end
  local config, config_err = merged_config(provider, template_cfg, self.variables)
  if not config then return nil, config_err end
  local _, auth_err = metadata_for_config(config)
  if auth_err then return nil, auth_err end

  local transport, transport_err = self:_tool_transport(tool, provider, transport_type, config)
  if not transport then return nil, transport_err end

  if type(transport.call_stream) == 'function' then
    return transport:call_stream(config, call_args, on_event)
  end

  if transport_type == 'sse' then
    return transport:listen(config.url, on_event)
  end

  if transport_type == 'streamable' then
    return transport:call(config, call_args, on_event)
  end

  return nil, 'tool does not use a streaming transport: ' .. tostring(transport_type)
end

function Client:search_tools(query, limit, any_of_tags_required)
  if type(limit) == 'table' then
    if limit.tags or limit.any_of_tags_required or limit.limit then
      any_of_tags_required = limit.any_of_tags_required or limit.tags
      limit = limit.limit
    else
      any_of_tags_required, limit = limit, nil
    end
  end
  if limit == nil then limit = 10 end
  local tools = {}

  for _, item in ipairs(self.registry:search(query, any_of_tags_required)) do
    tools[#tools + 1] = item.tool
    if limit > 0 and #tools >= limit then break end
  end

  return tools
end

function Client:register_manual(call_template)
  local provider = migration.call_template(call_template)
  if type(provider.name) == 'string' then provider.name = provider.name:gsub('[^%w_]', '_') end
  local ok, added, add_err = pcall(self.add_provider, self, provider)
  if not ok then return nil, tostring(added) end
  if not added then return nil, add_err end
  local manual, discover_err = self:_discover_provider(provider)
  if not manual then
    self:deregister_manual(provider.name)
    return nil, discover_err
  end
  return {
    manual = self.manuals[provider.name] or manual,
    manual_call_template = provider,
    success = true,
    errors = {},
  }
end

function Client:register_manuals(call_templates)
  if type(call_templates) ~= 'table' then return nil, 'manual call templates must be an array' end
  local results = {}
  for _, call_template in ipairs(call_templates) do
    local result, err = self:register_manual(call_template)
    if result then
      results[#results + 1] = result
    else
      results[#results + 1] = {
        manual_call_template = call_template,
        manual = {manual_version = '0.0.0', utcp_version = '1.1.0', tools = {}},
        success = false,
        errors = {tostring(err)},
      }
    end
  end
  return results
end

function Client:deregister_manual(name)
  local provider = self.providers[name]
  if not provider then return false end
  local transport = self._provider_transports[provider]
  if transport and type(transport.close) == 'function' then pcall(transport.close, transport) end
  self.registry:remove_provider(provider)
  self.providers[name], self.manuals[name] = nil, nil
  self._provider_transports[provider], self._discovered[provider] = nil, nil
  for tool in pairs(self._tool_transports) do
    if tool.qualified_name and tool.qualified_name:match('^' .. name:gsub('([^%w])', '%%%1') .. '%.') then
      local cached = self._tool_transports[tool]
      if cached and type(cached.close) == 'function' then pcall(cached.close, cached) end
      self._tool_transports[tool] = nil
    end
  end
  return true
end

function Client:get_required_variables(name)
  if name then
    local provider = self.providers[name]
    if not provider then return nil, 'unknown UTCP manual: ' .. tostring(name) end
    return variable_support.required(provider, self.variables, provider.name)
  end
  return variable_support.required(self.config, self.variables)
end

function Client:get_required_variables_for_manual_and_tools(call_template)
  local provider = migration.call_template(call_template)
  if type(provider.name) ~= 'string' or provider.name == '' then
    return nil, 'provider.name is required'
  end
  provider.name = provider.name:gsub('[^%w_]', '_')

  local required = variable_support.find_required(provider)
  if #variable_support.required(provider, self.variables, provider.name) > 0 then
    return required
  end

  local temporary, client_err = Client.new({variables = self.variables, warnings = false})
  if not temporary then return nil, client_err end
  local result, register_err = temporary:register_manual(provider)
  if not result then temporary:close(); return nil, register_err end

  local seen = {}
  for _, key in ipairs(required) do seen[key] = true end
  for _, tool in ipairs(result.manual.tools or {}) do
    for _, key in ipairs(variable_support.find_required(tool.tool_call_template or tool)) do
      seen[key] = true
    end
  end
  temporary:close()

  required = {}
  for key in pairs(seen) do required[#required + 1] = key end
  table.sort(required)
  return required
end

function Client:get_required_variables_for_registered_tool(name)
  local tool, provider = self:find_tool(name)
  if not tool then return nil, provider end
  return variable_support.find_required(tool.tool_call_template or tool)
end

function Client:tool_info(name)
  return self:find_tool(name)
end

function Client:close()
  local closed = {}
  for _, transport in pairs(self._provider_transports) do
    if not closed[transport] and type(transport.close) == 'function' then
      pcall(transport.close, transport); closed[transport] = true
    end
  end
  for _, transport in pairs(self._tool_transports) do
    if not closed[transport] and type(transport.close) == 'function' then
      pcall(transport.close, transport); closed[transport] = true
    end
  end
  self._provider_transports, self._tool_transports = {}, {}
  return true
end

Client.create = Client.new
Client.call_tool_streaming = Client.call_tool_stream

return Client
