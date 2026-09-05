package.path = './lua/?.lua;./lua/?/init.lua;./examples/grpc/?.lua;' .. package.path

-- The default Greeter service metadata and descriptor live beside this file.
-- Run `make server-grpc` in one terminal and `make example-grpc` in another.
-- UTCP_GRPC_DESCRIPTOR and UTCP_GRPC_MODULE can select generated external files.
local utcp = require('utcp')

local smoke = os.getenv('UTCP_EXAMPLE_SMOKE') == '1'
local target = os.getenv('UTCP_GRPC_TARGET') or 'localhost:50051'
local descriptor_set = not smoke and os.getenv('UTCP_GRPC_DESCRIPTOR') or nil
local descriptor_module = os.getenv('UTCP_GRPC_MODULE') or 'helloworld_grpc'
local grpc_module

if smoke then
  descriptor_module = {
    Greeter = {methods = {
      SayHello = {
        full_name = 'helloworld.Greeter.SayHello',
        client_streaming = false,
        server_streaming = false,
      },
      WatchHello = {
        full_name = 'helloworld.Greeter.WatchHello',
        client_streaming = false,
        server_streaming = true,
      },
    }},
  }
  grpc_module = {}
  function grpc_module.context(options) return options end
  function grpc_module.dial()
    local connection = {}
    function connection:invoke(_, _, request)
      return {message = 'Hello, ' .. request.name .. '!'}
    end
    function connection:new_stream(_, _, request)
      local responses = {
        {message = 'Hello, ' .. request.name .. '!'},
        {message = 'Goodbye, ' .. request.name .. '!'},
      }
      return {recv = function() return table.remove(responses, 1) end}
    end
    function connection:close() return true end
    return connection
  end
else
  grpc_module = assert(require('grpc'))
  if not descriptor_set and descriptor_module == 'helloworld_grpc' then
    local bundled_descriptor = require('helloworld_descriptor')
    assert(grpc_module.load_descriptors(bundled_descriptor))
  end
end

local client = assert(utcp.new({
  manual_call_templates = {{
    name = 'greeter',
    call_template_type = 'grpc',
    target = target,
    descriptor_set_path = descriptor_set,
    descriptor_module = descriptor_module,
    grpc_module = grpc_module,
    insecure = os.getenv('UTCP_GRPC_TLS') ~= '1',
    manual = {
      manual_version = '1.0.0',
      utcp_version = '1.1.0',
      tools = {
        {
          name = 'say_hello',
          description = 'Call the unary Greeter.SayHello RPC.',
          tool_call_template = {
            call_template_type = 'grpc',
            service = 'Greeter',
            method = 'SayHello',
          },
        },
        {
          name = 'watch_hello',
          description = 'Read the server stream from Greeter.WatchHello.',
          tool_call_template = {
            call_template_type = 'grpc',
            service = 'Greeter',
            method = 'WatchHello',
          },
        },
      },
    },
  }},
}))

local name = arg[1] or 'Lua'
local reply, call_err = client:call_tool('greeter.say_hello', {name = name})
assert(reply, call_err)
print('unary:', reply.message)

if smoke or os.getenv('UTCP_RUN_REALTIME_EXAMPLES') == '1'
  or os.getenv('UTCP_RUN_REAL_GRPC') == '1' or arg[2] == '--stream' then
  local ok, stream_err = client:call_tool_streaming(
    'greeter.watch_hello',
    {name = name},
    function(message)
      print('stream:', message.message)
    end
  )
  assert(ok, stream_err)
end

client:close()
