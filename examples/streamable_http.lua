package.path='./lua/?.lua;./lua/?/init.lua;'..package.path
local stream=require('utcp.transports.streamable')
local url=os.getenv('UTCP_STREAMABLE_URL') or 'http://127.0.0.1:8091/call'
local result,err=stream.new({}):call({url=url,http_method='POST'},{message='hello'},function(event)
  print('stream event:',require('utcp.json').encode(event))
end)
assert(result,err)
