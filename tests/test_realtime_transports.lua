package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local json = require('utcp.json')
local WebSocket = require('utcp.transports.websocket')
local Grpc = require('utcp.transports.grpc')
local WebRTC = require('utcp.transports.webrtc')

local fake_websocket = {created = 0, responses = {}}
function fake_websocket.new_from_uri(url, protocols)
  fake_websocket.created = fake_websocket.created + 1
  fake_websocket.url, fake_websocket.protocols = url, protocols
  local request_headers = {values = {}}
  function request_headers:upsert(key, value) self.values[key:lower()] = value end
  local socket = {request = {headers = request_headers}, readyState = 0, sent = {}}
  function socket:connect() self.readyState = 1; return true end
  function socket:send(value) self.sent[#self.sent + 1] = value; fake_websocket.sent = value; return true end
  function socket:receive()
    local value = table.remove(fake_websocket.responses, 1)
    if value == nil then return nil, 'closed' end
    return value
  end
  function socket:close() self.readyState = 3; return true end
  fake_websocket.socket = socket
  return socket
end

fake_websocket.responses = {'{"ok":true}'}
local ws = WebSocket.new({websocket_module = fake_websocket, keep_alive = true})
local ws_result = assert(ws:call({
  url = 'wss://example.test/tools',
  protocol = 'utcp-v1',
  message = {value = 'UTCP_ARG_value_UTCP_END'},
  response_format = 'json',
  headers = {Authorization = 'token'},
}, {value = 7}))
assert(ws_result.ok == true)
assert(json.decode(fake_websocket.sent).value == 7)
assert(fake_websocket.protocols[1] == 'utcp-v1')
assert(fake_websocket.socket.request.headers.values.authorization == 'token')
assert(WebSocket.validate_url('ws://localhost:8080/ws'))
assert(WebSocket.validate_url('ws://127.0.0.1.attacker.example/ws') == nil)

fake_websocket.responses = {'1', '2'}
local streamed = {}
assert(ws:call_stream({url = 'wss://example.test/tools', message = '{}'}, {}, function(value)
  streamed[#streamed + 1] = value
  return #streamed < 2
end))
assert(streamed[1] == 1 and streamed[2] == 2)
assert(fake_websocket.created == 1, 'keep-alive WebSocket must be reused')
assert(ws:close())

local fake_grpc = {calls = {}}
function fake_grpc.context(options) fake_grpc.context_options = options; return options end
function fake_grpc.dial(target, options)
  fake_grpc.target, fake_grpc.dial_options = target, options
  local connection = {}
  function connection:invoke(_, method, request)
    fake_grpc.calls[#fake_grpc.calls + 1] = method.full_name
    return {reply = request.name}
  end
  function connection:new_stream(_, method)
    local stream = {sent = {}, responses = method.server_streaming and {{n = 1}, {n = 2}} or {{count = 2}}}
    function stream:send(value) self.sent[#self.sent + 1] = value; return true end
    function stream:close_send() return true end
    function stream:recv() return table.remove(self.responses, 1) end
    fake_grpc.stream = stream
    return stream
  end
  function connection:close() fake_grpc.closed = true; return true end
  return connection
end

local grpc = Grpc.new({grpc_module = fake_grpc, target = 'localhost:50051', insecure = true})
local unary = assert(grpc:call({
  target = 'localhost:50051',
  method_descriptor = {full_name = 'demo.Echo.Call', client_streaming = false, server_streaming = false},
}, {name = 'Lua'}))
assert(unary.reply == 'Lua')
assert(fake_grpc.target == 'localhost:50051' and fake_grpc.dial_options.insecure == true)

local grpc_events = {}
assert(grpc:call_stream({
  method_descriptor = {full_name = 'demo.Echo.Watch', client_streaming = false, server_streaming = true},
}, {}, function(value) grpc_events[#grpc_events + 1] = value end))
assert(#grpc_events == 2 and grpc_events[2].n == 2)

local client_stream = assert(grpc:call({
  method_descriptor = {full_name = 'demo.Echo.Send', client_streaming = true, server_streaming = false},
}, {messages = {{n = 1}, {n = 2}}}))
assert(client_stream.count == 2 and #fake_grpc.stream.sent == 2)
assert(grpc:close() and fake_grpc.closed)

local peer = {responses = {'{"answer":42}'}, sent = {}}
function peer:connect(config) self.config = config; return true end
function peer:send(value) self.sent[#self.sent + 1] = value; return true end
function peer:receive() return table.remove(self.responses, 1) end
function peer:close() self.closed = true; return true end

local rtc = WebRTC.new({data_channel = peer})
local rtc_result = assert(rtc:call({
  message = {question = 'UTCP_ARG_question_UTCP_ARG'}, response_format = 'json'
}, {question = 'life'}))
assert(rtc_result.answer == 42)
assert(json.decode(peer.sent[1]).question == 'life')
assert(rtc:close() and peer.closed)

print('WebSocket, gRPC and WebRTC transport tests: ok')
