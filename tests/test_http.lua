package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local utcp = require('utcp')
local url = os.getenv('UTCP_HTTP_URL') or 'http://127.0.0.1:8080/echo'

local client = utcp.new({})
client:add_manual({
  tools = {
    {
      name = 'echo',
      tool_call_template = {
        call_template_type = 'http',
        url = url,
        http_method = 'POST',
      },
    },
  },
})

local result, err = client:call_tool('echo', {message = 'integration check'})
assert(result, err)
assert(result.message == 'integration check')

print('HTTP integration test: ok')
