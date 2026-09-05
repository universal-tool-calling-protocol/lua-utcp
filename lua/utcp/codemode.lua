-- CodeMode execution for lua-utcp.
--
-- The public API mirrors the CodeMode model used by the reference
-- implementations: one code-execution entry point, with registered UTCP
-- tools exposed to the sandbox only through codemode.call_tool().
local json = require('utcp.json')

local M = {}

local function copy_table(src)
  local dst = {}
  for k, v in pairs(src or {}) do dst[k] = v end
  return dst
end

local function safe_name(name)
  return type(name) == 'string' and name:match('^[A-Za-z_][A-Za-z0-9_]*$') ~= nil
end

local function tool_interface(full_name, tool)
  return {
    name = full_name,
    description = tool.description,
    tags = tool.tags or {},
    inputs = tool.inputs or tool.input_schema or {},
    outputs = tool.outputs or tool.output_schema or {},
  }
end

local function make_tool_proxy(client, full_name)
  return function(args)
    args = args or {}
    return function()
      local result, err = client:call_tool(full_name, args)
      if result == nil and err ~= nil then error(err, 0) end
      return result
    end
  end
end

local function build_environment(client, opts, logs)
  opts = opts or {}
  local env = {}

  env.print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do
      parts[i] = tostring(select(i, ...))
    end
    logs[#logs + 1] = table.concat(parts, '\t')
  end

  env.json = {
    encode = json.encode,
    decode = json.decode,
  }

  -- Safe, deterministic standard-library subset.
  env.assert = assert
  env.error = error
  env.ipairs = ipairs
  env.pairs = pairs
  env.next = next
  env.select = select
  env.tonumber = tonumber
  env.tostring = tostring
  env.type = type
  env.math = copy_table(math)
  env.string = copy_table(string)
  env.table = copy_table(table)

  local interfaces = {}
  local tools = client:list_tools() or {}
  local entries = {}

  for _, tool in ipairs(tools) do
    local tool_name = tool.name
    local interface_name = tool.qualified_name or tool_name
    entries[#entries + 1] = {
      name = tool_name,
      interface_name = interface_name,
      tool = tool,
    }
    interfaces[#interfaces + 1] = interface_name
  end

  local function call_tool(name, args)
    if type(name) ~= 'string' or name == '' then
      error('codemode.call_tool expects a non-empty tool name', 2)
    end
    if args ~= nil and type(args) ~= 'table' then
      error('codemode.call_tool expects args to be a table', 2)
    end
    local result, err = client:call_tool(name, args or {})
    if result == nil and err ~= nil then
      error(err, 2)
    end
    return result
  end

  local function list_tools()
    return client:list_tools()
  end

  local function search_tools(query, tags)
    return client:search_tools(query, 10, tags)
  end

  local function get_tool_interface(name)
    for _, entry in ipairs(entries) do
      if entry.name == name or entry.interface_name == name then
        return tool_interface(entry.interface_name, entry.tool)
      end
    end
    return nil, 'unknown UTCP tool: ' .. tostring(name)
  end

  -- Code executed by the model gets exactly one controlled UTCP entry point.
  -- Do not expose the client, transport objects, or generated manual globals.
  env.codemode = {
    call_tool = call_tool,
    list_tools = list_tools,
    search_tools = search_tools,
    get_tool_interface = get_tool_interface,
  }

  if opts.globals then
    for k, v in pairs(opts.globals) do env[k] = v end
  end

  return env, interfaces
end

local function error_message(err)
  if type(err) == 'table' and err.message ~= nil then
    return tostring(err.message)
  end
  return tostring(err)
end

local function structured_error(stage, err, logs, interfaces)
  local message = error_message(err)
  local kind = stage == 'compile' and 'syntax_error' or 'runtime_error'
  local retryable = true

  if message == 'CodeMode instruction limit exceeded' then
    kind = 'instruction_limit'
    retryable = false
  end

  return {
    stage = stage,
    type = kind,
    message = message,
    error = message,
    retryable = retryable,
    logs = logs,
    interfaces = interfaces,
  }
end

function M.new(client, opts)
  assert(client, 'CodeMode requires a UTCP client')
  opts = opts or {}
  local api = {}

  function api.call_tool(name, args)
    return client:call_tool(name, args or {})
  end

  function api.call_tool_stream(name, args, on_event)
    return client:call_tool_stream(name, args or {}, on_event)
  end

  function api.list_tools()
    return client:list_tools()
  end

  function api.search_tools(query, tags)
    return client:search_tools(query, 10, tags)
  end

  function api.get_tool_interface(name)
    local tool = client:find_tool(name)
    if not tool then return nil, 'unknown UTCP tool: ' .. tostring(name) end
    return tool_interface(name, tool)
  end

  function api.interfaces()
    local _, interfaces = build_environment(client, opts, {})
    return interfaces
  end

  function api.call_tool_chain(_, source, exec_opts)
    exec_opts = exec_opts or {}
    assert(type(source) == 'string', 'call_tool_chain expects Lua source code')

    local logs = {}
    local env, interfaces = build_environment(client, opts, logs)
    local chunk, compile_err = load(source, 'utcp-codemode', 't', env)
    if not chunk then
      return nil, structured_error('compile', compile_err, logs, interfaces)
    end

    local instruction_limit = exec_opts.instruction_limit or opts.instruction_limit
    local hook_installed = false
    local function hook()
      error('CodeMode instruction limit exceeded', 0)
    end

    if instruction_limit and instruction_limit > 0 and debug and debug.sethook then
      debug.sethook(hook, '', instruction_limit)
      hook_installed = true
    end

    local ok, result = pcall(chunk)
    if hook_installed then debug.sethook() end

    if not ok then
      return nil, structured_error('execute', result, logs, interfaces)
    end

    return { result = result, logs = logs, interfaces = interfaces }
  end

  -- Compatibility aliases for host-side callers. The sandbox intentionally
  -- exposes only `codemode.call_tool(...)` and related methods.
  api.call = api.call_tool
  api.stream = api.call_tool_stream
  api.list = api.list_tools
  api.search = api.search_tools
  api.describe = api.get_tool_interface
  api.callToolChain = api.call_tool_chain
  api.searchTools = api.search_tools
  api.getToolInterface = api.get_tool_interface

  api.json = { encode = json.encode, decode = json.decode }
  return api
end

return M
