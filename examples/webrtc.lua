package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- A WebRTC binding is host-specific. The named module must expose new(config)
-- and return a connected DataChannel adapter with send(), receive()/recv(),
-- and optional connect()/close() methods:
--   UTCP_WEBRTC_MODULE=my_webrtc_adapter lua examples/webrtc.lua hello
local utcp = require('utcp')

local smoke = os.getenv('UTCP_EXAMPLE_SMOKE') == '1'
local binding = os.getenv('UTCP_WEBRTC_MODULE')
local data_channel
if smoke then
  data_channel = {}
  function data_channel:connect() return true end
  function data_channel:send(value) self.response = value; return true end
  function data_channel:receive() local value = self.response; self.response = nil; return value end
  function data_channel:close() return true end
else
  assert(binding, 'UTCP_WEBRTC_MODULE must name a Lua WebRTC DataChannel adapter')
end

local client = assert(utcp.new({
  manual_call_templates = {{
    name = 'peer',
    call_template_type = 'webrtc',
    webrtc_module = binding,
    data_channel = data_channel,
    signaling_url = os.getenv('UTCP_WEBRTC_SIGNALING_URL'),
    ice_servers = {{
      urls = os.getenv('UTCP_WEBRTC_STUN_URL') or 'stun:stun.l.google.com:19302',
    }},
    data_channel_label = os.getenv('UTCP_WEBRTC_CHANNEL') or 'utcp',
    manual = {
      manual_version = '1.0.0',
      utcp_version = '1.1.0',
      tools = {{
        name = 'echo',
        description = 'Exchange one JSON message over an RTCDataChannel.',
        inputs = {
          type = 'object',
          properties = {value = {type = 'string'}},
          required = {'value'},
        },
        tool_call_template = {
          call_template_type = 'webrtc',
          message = {value = 'UTCP_ARG_value_UTCP_END'},
          response_format = 'json',
          timeout = 15,
        },
      }},
    },
  }},
}))

local response, err = client:call_tool('peer.echo', {value = arg[1] or 'hello'})
assert(response, err)
print(utcp.json.encode(response))
client:close()
