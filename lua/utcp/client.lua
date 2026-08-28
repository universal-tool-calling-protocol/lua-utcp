local json=require('utcp.json'); local Registry=require('utcp.registry'); local transports=require('utcp.transports'); local errors=require('utcp.errors')
local Client={}; Client.__index=Client
local aliases={streamable_http='streamable',streamable='streamable',http='http',sse='sse',tcp='tcp',udp='udp',cli='cli',text='text',graphql='graphql',mcp='mcp'}
function Client.new(cfg)
  cfg=cfg or {}; local self=setmetatable({config=cfg,registry=Registry.new(),providers={},_discovered={},_provider_transports={},_tool_transports={}},Client)
  for _,p in ipairs(cfg.providers or {}) do self:add_provider(p) end
  if cfg.manual then self:add_manual(cfg.manual) end
  return self
end
function Client:add_provider(p)
  assert(p.name,'provider.name is required'); self.providers[p.name]=p; self.registry:add_provider(p)
  self._discovered[p]=nil; self._provider_transports[p]=nil
  if p.manual then self:add_manual(p.manual,p); self._discovered[p]=p.manual elseif p.tools then local manual={tools=p.tools}; self:add_manual(manual,p); self._discovered[p]=manual end
  return p
end
function Client:load_provider(path)
  local provider = require('utcp.provider').load(path)
  if not provider then return nil, 'failed to load provider: '..tostring(path) end
  return self:add_provider(provider)
end
function Client:add_manual(manual,provider)
  assert(manual and manual.tools,'UTCP manual must contain tools')
  for _,tool in ipairs(manual.tools) do
    local previous=self.registry:get(tool.name)
    if previous then self._tool_transports[previous.tool]=nil end
    self.registry:add_tool(tool,provider)
  end
end
function Client:_transport(p)
  local typ=aliases[p.call_template_type or p.provider_type or p.transport or p.type or 'http']; if not typ then error('unsupported UTCP transport: '..tostring(typ)) end
  if typ=='mcp' then
    local cached=self._provider_transports[p]
    if cached then return cached end
    cached=transports[typ].new(p); self._provider_transports[p]=cached; return cached
  end
  return transports[typ].new(p)
end
function Client:_discover_provider(p)
  local cached=self._discovered[p]; if cached then return cached end
  if p.manual then self:add_manual(p.manual,p); self._discovered[p]=p.manual; return p.manual end
  local t=self:_transport(p); local manual
  if p.discovery then
    if p.discovery.method=='GET' or p.discovery.url then
      local result,err=t:request('GET',p.discovery.url or p.url,p.discovery.body,p.discovery.headers); if err then return nil,err end; manual=result
    end
  elseif p.tools_url or p.discovery_url then
    local result,err=t:request('GET',p.tools_url or p.discovery_url,nil,p.headers); if err then return nil,err end; manual=result
  elseif p.provider_type=='mcp' or p.call_template_type=='mcp' then
    local result,err=t:initialize(); if err then return nil,err end; local listed,e=t:list_tools(); if e then return nil,e end
    local tools={}; for _,tool in ipairs((listed or {}).tools or {}) do tools[#tools+1]={name=tool.name,description=tool.description,inputs={type='object',properties=(tool.inputSchema or {}).properties or {}},tool_call_template={call_template_type='mcp',name=tool.name,arguments_path='arguments'}} end
    manual={manual_version='1.0',utcp_version='1.0',tools=tools}; self:add_manual(manual,p); self._discovered[p]=manual; return manual
  end
  if manual then self:add_manual(manual,p); self._discovered[p]=manual; return manual end
  return nil,'provider has no discoverable manual'
end
function Client:discover()
  local out={}; for _,p in pairs(self.providers) do local m,err=self:_discover_provider(p); if not m then return nil,err end; out[#out+1]=m end; return out
end
function Client:list_tools() local out={}; for _,item in ipairs(self.registry:all()) do out[#out+1]=item.tool end; return out end
function Client:find_tool(name)
  local item=self.registry:get(name)
  if item then return item.tool,item.provider end

  -- CodeMode may use the fully-qualified provider.tool form. The canonical
  -- registry stores the tool's UTCP name, so resolve the qualified alias
  -- without adding a second mutable registry entry.
  local provider_name, tool_name = type(name) == 'string' and name:match('^([A-Za-z_][A-Za-z0-9_-]*)%.([A-Za-z_][A-Za-z0-9_.-]*)$') or nil, nil
  if provider_name then
    tool_name = name:match('^[^.]+%.(.+)$')
    local provider = self.providers[provider_name]
    if provider then
      local qualified = self.registry:get(tool_name)
      if qualified and qualified.provider == provider then
        return qualified.tool, qualified.provider
      end
    end
  end

  return nil,'unknown UTCP tool: '..tostring(name)
end
function Client:call_tool(name,args)
  local tool,p=self:find_tool(name)

  -- If the tool is not registered yet, try discovering provider manuals.
  -- This makes call_tool() usable directly after Client.new().
  if not tool then
    local requested = name

    -- Resolve provider.tool notation.
    local provider_name, tool_name = requested:match(
      '^([A-Za-z_][A-Za-z0-9_-]*)%.([A-Za-z_][A-Za-z0-9_.-]*)$'
    )

    if provider_name then
      local provider = self.providers[provider_name]
      if provider then
        local manual,err=self:_discover_provider(provider)
        if not manual then
          return nil,err
        end
        tool,p=self:find_tool(tool_name)
      end
    else
      -- Try discovery for all providers.
      local discovery_err

      for _,provider in pairs(self.providers) do
        local discovered,err=self:_discover_provider(provider)

        if not discovered then
          discovery_err=err
        else
          tool,p=self:find_tool(requested)
          if tool then
            break
          end
        end
      end

      if not tool and discovery_err then
        return nil,discovery_err
      end
    end
  end

  if not tool then
    return nil,'unknown UTCP tool: '..tostring(name)
  end

  local tpl=tool.tool_call_template or tool.call_template or tool

  local typ=aliases[
    tpl.call_template_type
      or tpl.provider_type
      or tpl.transport
      or p and p.transport
      or 'http'
  ]

  if not typ then
    return nil,'unsupported UTCP transport'
  end

  local cfg={}

  if p then
    for k,v in pairs(p) do
      cfg[k]=v
    end
  end

  for k,v in pairs(tpl) do
    cfg[k]=v
  end

  local transport=self._tool_transports[tool]
  if typ=='mcp' and p then
    transport=transport or self._provider_transports[p]
    if not transport then transport=transports[typ].new(cfg); self._provider_transports[p]=transport end
  elseif not transport then
    transport=transports[typ].new(cfg)
  end
  self._tool_transports[tool]=transport

  if typ=='mcp' then
    return transport:call_tool(
      tpl.name or name,
      args or {}
    )
  end

  return transport:call(
    tpl,
    args or {}
  )
end
function Client:call_tool_stream(name,args,on_event)
  local tool,p=self:find_tool(name); if not tool then return nil,p end; local tpl=tool.tool_call_template or tool.call_template or tool; local typ=aliases[tpl.call_template_type or tpl.provider_type or 'sse'];
  local cfg={}; if p then for k,v in pairs(p) do cfg[k]=v end end; for k,v in pairs(tpl) do cfg[k]=v end
  local transport=self._tool_transports[tool]
  if not transport then transport=transports[typ].new(cfg); self._tool_transports[tool]=transport end
  if typ=='sse' then return transport:listen(tpl.url or cfg.url,on_event)
  elseif typ=='streamable' then return transport:call(tpl,args or {},on_event)
  else return nil,'tool does not use a streaming transport: '..tostring(typ) end
end
function Client:search_tools(query,tags) local out={}; for _,item in ipairs(self.registry:search(query,tags)) do out[#out+1]=item.tool end; return out end
return Client
