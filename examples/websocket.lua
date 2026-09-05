package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Start a WebSocket echo server on 127.0.0.1:8765, or set:
--   UTCP_WEBSOCKET_URL=wss://your-server.example/ws lua examples/websocket.lua
local utcp = require('utcp')

local smoke = os.getenv('UTCP_EXAMPLE_SMOKE') == '1'
local endpoint = os.getenv('UTCP_WEBSOCKET_URL') or 'ws://127.0.0.1:8765'
local websocket_module
if smoke then
  websocket_module = {}
  function websocket_module.new_from_uri()
    local socket = {readyState = 0, request = {headers = {}}}
    function socket.request.headers:upsert() end
    function socket:connect() self.readyState = 1; return true end
    function socket:send(value) self.response = value; return true end
    function socket:receive() return self.response end
    function socket:close() self.readyState = 3; return true end
    return socket
  end
end

local client = assert(utcp.new({
  manual_call_templates = {{
    name = 'socket',
    call_template_type = 'websocket',
    url = endpoint,
    websocket_module = websocket_module,
    manual = {
      manual_version = '1.0.0',
      utcp_version = '1.1.0',
      tools = {{
        name = 'echo',
        description = 'Send one JSON message and receive one JSON message.',
        inputs = {
          type = 'object',
          properties = {value = {type = 'string'}},
          required = {'value'},
        },
        tool_call_template = {
          call_template_type = 'websocket',
          url = endpoint,
          protocol = os.getenv('UTCP_WEBSOCKET_PROTOCOL'),
          message = {value = 'UTCP_ARG_value_UTCP_END'},
          response_format = 'json',
          keep_alive = true,
          timeout = 15,
        },
      }},
    },
  }},
}))

local result, err = client:call_tool('socket.echo', {value = arg[1] or 'hello'})
assert(result, err)
print(utcp.json.encode(result))
client:close()
