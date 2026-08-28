package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local utcp = require('utcp')
local transports = require('utcp.transports')
local Registry = require('utcp.registry')

local call_iterations = tonumber(arg[1]) or 20000
local registry_tools = tonumber(arg[2]) or 5000
local registry_iterations = tonumber(arg[3]) or 2000

local counts = {}

local function make_fake_transport(name)
  return function()
    counts[name] = (counts[name] or 0) + 1

    return {
      call = function(_, _, args)
        return args
      end,
      call_tool = function(_, _, args)
        return {result = args}
      end,
      listen = function(_, _, on_event)
        if on_event then on_event({event = 'message', data = {}}) end
        return true
      end,
      request = function()
        return {}, nil, {}, ''
      end,
      initialize = function()
        return {}
      end,
      list_tools = function()
        return {tools = {}}
      end,
    }
  end
end

local function patch_transports()
  local originals = {}
  for _, name in ipairs({ 'http', 'sse', 'streamable', 'tcp', 'udp', 'cli', 'text', 'graphql', 'mcp' }) do
    originals[name] = transports[name].new
    transports[name].new = make_fake_transport(name)
    counts[name] = 0
  end

  return function()
    for name, original in pairs(originals) do
      transports[name].new = original
    end
  end
end

local function create_client(scenario)
  if scenario.provider then
    return utcp.new({
      providers = {
        {
          name = scenario.provider,
          provider_type = scenario.transport,
          transport = scenario.transport,
          tools = {
            {
              name = scenario.tool,
              tool_call_template = {
                call_template_type = scenario.transport,
                name = scenario.tool,
              },
            },
          },
        },
      },
    })
  end

  local client = utcp.new({})
  client:add_manual({
    manual_version = '1.0',
    utcp_version = '1.0',
    tools = {
      {
        name = scenario.tool,
        description = 'benchmark tool',
        inputs = { type = 'object', properties = {} },
        tool_call_template = {
          call_template_type = scenario.transport,
          url = 'http://127.0.0.1:0/' .. scenario.tool,
        },
      },
    },
  })

  return client
end

local function run_calls(client, scenario, clear_cache, iterations)
  local tool, provider = client:find_tool(scenario.tool)
  local start = os.clock()

  for i = 1, iterations do
    if clear_cache then
      client._tool_transports[tool] = nil
      if provider then client._provider_transports[provider] = nil end
    end

    local err
    if scenario.call_stream then
      local _, e = client:call_tool_stream(scenario.tool, {index = i}, function() end)
      err = e
    else
      local _, e = client:call_tool(scenario.tool, {index = i})
      err = e
    end
    if err then
      return nil, err
    end
  end

  return os.clock() - start
end

local function benchmark_transport_cache()
  local restore = patch_transports()

  local scenarios = {
    { tool = 'bench_http', transport = 'http' },
    { tool = 'bench_sse', transport = 'sse', call_stream = true },
    { tool = 'bench_streamable', transport = 'streamable' },
    { tool = 'bench_tcp', transport = 'tcp' },
    { tool = 'bench_udp', transport = 'udp' },
    { tool = 'bench_cli', transport = 'cli' },
    { tool = 'bench_text', transport = 'text' },
    { tool = 'bench_graphql', transport = 'graphql' },
    { tool = 'bench_mcp', transport = 'mcp', provider = 'bench_mcp_provider' },
  }

  print(string.format('transport call benchmark (%d calls)', call_iterations))
  print(string.format('%-17s | %12s | %12s | %10s | %11s', 'transport', 'cached', 'uncached', 'ratio', 'constructs'))

  for _, scenario in ipairs(scenarios) do
    counts[scenario.transport] = 0
    local cached_client = create_client(scenario)
    local cached = run_calls(cached_client, scenario, false, call_iterations)
    if not cached then
      print(string.format('%-17s | %s', scenario.transport, 'ERROR'))
      return
    end
    local cached_constructs = counts[scenario.transport]

    counts[scenario.transport] = 0
    local uncached_client = create_client(scenario)
    local uncached = run_calls(uncached_client, scenario, true, call_iterations)
    if not uncached then
      print(string.format('%-17s | %s', scenario.transport, 'ERROR'))
      return
    end
    local uncached_constructs = counts[scenario.transport]

    local cached_ms = (cached / call_iterations) * 1000
    local uncached_ms = (uncached / call_iterations) * 1000
    local ratio = uncached_ms > 0 and (cached_ms > 0 and (uncached_ms / cached_ms) or 0) or 0
    local ratio_text = ratio > 0 and string.format('%8.2fx', ratio) or 'n/a'
    print(string.format('%-17s | %10.4f ms | %10.4f ms | %10s | %4d / %4d',
      scenario.transport, cached_ms, uncached_ms, ratio_text, cached_constructs, uncached_constructs))
  end

  restore()
end

local function benchmark_registry_cache()
  local registry = Registry.new()
  for i = 1, registry_tools do
    registry:add_tool({ name = string.format('tool_%04d', i) }, { name = 'provider' })
  end

  -- Warm up cached path once.
  registry:all()
  local cached_start = os.clock()
  for i = 1, registry_iterations do
    registry:all()
  end
  local cached = os.clock() - cached_start

  -- Force uncached work by invalidating cache each iteration.
  local uncached_start = os.clock()
  for i = 1, registry_iterations do
    registry._ordered = nil
    registry:all()
  end
  local uncached = os.clock() - uncached_start

  print()
  print('registry all() benchmark')
  print(string.format('tools=%d, cached calls=%d, uncached calls=%d',
    registry_tools, registry_iterations, registry_iterations))
  print(string.format('cached=%0.4fms total (%0.5fms each)',
    cached * 1000, (cached / registry_iterations) * 1000))
  print(string.format('uncached=%0.4fms total (%0.5fms each)',
    uncached * 1000, (uncached / registry_iterations) * 1000))
end

benchmark_transport_cache()
benchmark_registry_cache()
