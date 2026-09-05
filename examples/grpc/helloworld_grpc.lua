-- Generated service metadata for examples/grpc/helloworld.proto.
local M = {}

M.Greeter = {
  service_name = 'helloworld.Greeter',
  methods = {
    SayHello = {
      name = 'SayHello',
      full_name = 'helloworld.Greeter.SayHello',
      path = '/helloworld.Greeter/SayHello',
      input_type = '.helloworld.HelloRequest',
      output_type = '.helloworld.HelloReply',
      client_streaming = false,
      server_streaming = false,
      interceptors = {client = 'unary', server = 'unary'},
    },
    WatchHello = {
      name = 'WatchHello',
      full_name = 'helloworld.Greeter.WatchHello',
      path = '/helloworld.Greeter/WatchHello',
      input_type = '.helloworld.HelloRequest',
      output_type = '.helloworld.HelloReply',
      client_streaming = false,
      server_streaming = true,
      interceptors = {client = 'stream', server = 'stream'},
    },
  },
}

function M.register_greeter_server(server, implementation)
  return server:register_service(M.Greeter, implementation)
end

return M
