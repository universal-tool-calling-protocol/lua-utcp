-- Run from the repository root with Lua 5.3 or 5.4:
--   make server-grpc
package.path = './examples/grpc/?.lua;' .. package.path

local grpc = require('grpc')
local hello = require('helloworld_grpc')
local descriptor = require('helloworld_descriptor')

assert(grpc.load_descriptors(descriptor))

local host = arg[1] or os.getenv('UTCP_GRPC_HOST') or '127.0.0.1'
local port = tonumber(arg[2] or os.getenv('UTCP_GRPC_PORT')) or 50051
local server = grpc.new_server({compression = os.getenv('GRPC_COMPRESSION')})

assert(hello.register_greeter_server(server, {
  say_hello = function(_, request)
    return {message = 'Hello, ' .. request.name .. '!'}
  end,
  watch_hello = function(_, request)
    local greetings = {'Hello', 'Welcome', 'Goodbye'}
    local index = 0
    return function()
      index = index + 1
      if not greetings[index] then return nil end
      return {message = greetings[index] .. ', ' .. request.name .. '!'}
    end
  end,
}))

assert(server:listen({host = host, port = port, insecure = true}))
print(string.format('gRPC Greeter server listening on %s:%d', host, port))
assert(server:loop())
