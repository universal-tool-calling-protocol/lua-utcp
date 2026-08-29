local json = require('utcp.json')
local Registry = require('utcp.registry')
local transports = require('utcp.transports')
local errors = require('utcp.errors')
local Guard = require('utcp.guard')
local auth = require('utcp.auth')

local Client = {}
Client.__index = Client

local aliases = {
  streamable_http = 'streamable',
  streamable = 'streamable',
  http = 'http',
  sse = 'sse',
  tcp = 'tcp',
  udp = 'udp',
  cli = 'cli',
  text = 'text',
  graphql = 'graphql',
  mcp = 'mcp',
}

local function provider_transport_type(provider)
  local requested_type = provider.call_template_type
    or provider.provider_type
    or provider.transport
    or provider.type
    or 'http'

  return aliases[requested_type]
end

local function tool_transport_type(template_cfg, provider)
  local requested_type = template_cfg.call_template_type
    or template_cfg.provider_type
    or template_cfg.transport
    or (provider and provider.transport)
    or 'http'

  return aliases[requested_type]
end

local function merged_config(provider, template_cfg)
  local config = {}

  if provider then
    for key, value in pairs(provider) do
      config[key] = value
    end
  end

  for key, value in pairs(template_cfg) do
    config[key] = value
  end

  return config
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

  local self = setmetatable({
    config = cfg,
    registry = Registry.new(),
    providers = {},
    _discovered = {},
    _provider_transports = {},
    _tool_transports = {},
  }, Client)

  for _, provider in ipairs(cfg.providers or {}) do
    self:add_provider(provider)
  end

  if cfg.manual then
    self:add_manual(cfg.manual)
  end

  return self
end

function Client:add_provider(provider)
  assert(provider.name, 'provider.name is required')

  self.providers[provider.name] = provider
  self.registry:add_provider(provider)
  self._discovered[provider] = nil
  self._provider_transports[provider] = nil

  if provider.manual then
    self:add_manual(provider.manual, provider)
    self._discovered[provider] = provider.manual
  elseif provider.tools then
    local manual = {tools = provider.tools}
    self:add_manual(manual, provider)
    self._discovered[provider] = manual
  end

  return provider
end

function Client:load_provider(path)
  local provider = require('utcp.provider').load(path)
  if not provider then
    return nil, 'failed to load provider: ' .. tostring(path)
  end

  return self:add_provider(provider)
end

function Client:add_manual(manual, provider)
  assert(manual and manual.tools, 'UTCP manual must contain tools')

  for _, tool in ipairs(manual.tools) do
    local previous = self.registry:get(tool.name)
    if previous then
      self._tool_transports[previous.tool] = nil
    end

    self.registry:add_tool(tool, provider)
  end
end

function Client:_transport(provider)
  local transport_type = provider_transport_type(provider)
  if not transport_type then
    error('unsupported UTCP transport: ' .. tostring(transport_type))
  end

  if transport_type == 'mcp' then
    local cached = self._provider_transports[provider]
    if cached then
      return cached
    end

    cached = transports[transport_type].new(provider)
    self._provider_transports[provider] = cached
    return cached
  end

  return transports[transport_type].new(provider)
end

function Client:_discover_provider(provider)
  local cached = self._discovered[provider]
  if cached then
    return cached
  end

  if provider.manual then
    self:add_manual(provider.manual, provider)
    self._discovered[provider] = provider.manual
    return provider.manual
  end

  local transport = self:_transport(provider)
  local manual

  if provider.discovery then
    if provider.discovery.method == 'GET' or provider.discovery.url then
      local result, err = transport:request(
        'GET',
        provider.discovery.url or provider.url,
        provider.discovery.body,
        provider.discovery.headers
      )
      if err then
        return nil, err
      end

      manual = result
    end
  elseif provider.tools_url or provider.discovery_url then
    local result, err = transport:request(
      'GET',
      provider.tools_url or provider.discovery_url,
      nil,
      provider.headers
    )
    if err then
      return nil, err
    end

    manual = result
  elseif provider.provider_type == 'mcp' or provider.call_template_type == 'mcp' then
    local _, initialize_err = transport:initialize()
    if initialize_err then
      return nil, initialize_err
    end

    local listed_tools, list_err = transport:list_tools()
    if list_err then
      return nil, list_err
    end

    manual = mcp_manual(listed_tools)
  end

  if manual then
    self:add_manual(manual, provider)
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
  local item = self.registry:get(name)
  if item then
    return item.tool, item.provider
  end

  -- CodeMode may use the fully-qualified provider.tool form. The canonical
  -- registry stores the tool's UTCP name, so resolve the qualified alias
  -- without adding a second mutable registry entry.
  if type(name) == 'string' then
    local provider_name, tool_name = name:match(
      '^([A-Za-z_][A-Za-z0-9_-]*)%.([A-Za-z_][A-Za-z0-9_.-]*)$'
    )
    local provider = provider_name and self.providers[provider_name]

    if provider then
      local qualified = self.registry:get(tool_name)
      if qualified and qualified.provider == provider then
        return qualified.tool, qualified.provider
      end
    end
  end

  return nil, 'unknown UTCP tool: ' .. tostring(name)
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
  return metadata_for_config(merged_config(provider, template_cfg))
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

    return self:find_tool(tool_name)
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

  if transport_type == 'mcp' and provider then
    transport = transport or self._provider_transports[provider]
    if not transport then
      transport = transports[transport_type].new(config)
      self._provider_transports[provider] = transport
    end
  elseif not transport then
    transport = transports[transport_type].new(config)
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

  local config = merged_config(provider, template_cfg)
  local _, auth_err = metadata_for_config(config)
  if auth_err then return nil, auth_err end

  local transport = self:_tool_transport(tool, provider, transport_type, config)

  if transport_type == 'mcp' then
    return transport:call_tool(template_cfg.name or name, call_args)
  end

  return transport:call(template_cfg, call_args)
end

function Client:call_tool_stream(name, args, on_event)
  local tool, provider = self:find_tool(name)
  if not tool then
    return nil, provider
  end

  local template_cfg = tool.tool_call_template or tool.call_template or tool
  local transport_type = aliases[
    template_cfg.call_template_type
      or template_cfg.provider_type
      or 'sse'
  ]
  local config = merged_config(provider, template_cfg)
  local _, auth_err = metadata_for_config(config)
  if auth_err then return nil, auth_err end

  local transport = self._tool_transports[tool]

  if not transport then
    transport = transports[transport_type].new(config)
    self._tool_transports[tool] = transport
  end

  if transport_type == 'sse' then
    return transport:listen(template_cfg.url or config.url, on_event)
  end

  if transport_type == 'streamable' then
    return transport:call(template_cfg, args or {}, on_event)
  end

  return nil, 'tool does not use a streaming transport: ' .. tostring(transport_type)
end

function Client:search_tools(query, tags)
  local tools = {}

  for _, item in ipairs(self.registry:search(query, tags)) do
    tools[#tools + 1] = item.tool
  end

  return tools
end

return Client
