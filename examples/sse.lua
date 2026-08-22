package.path='./lua/?.lua;./lua/?/init.lua;'..package.path
local sse=require('utcp.transports.sse')
local url=os.getenv('UTCP_SSE_URL') or 'http://127.0.0.1:8090/events'
local ok,err=sse.new({}):listen(url,function(e)
  print('SSE event:',e.event,e.id,require('utcp.json').encode(e.data))
end)
assert(ok,err)
