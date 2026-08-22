package.path='./lua/?.lua;./lua/?/init.lua;'..package.path
local tcp=require('utcp.transports.tcp')
local port=tonumber(os.getenv('UTCP_TCP_PORT') or '9000')
local result,err=tcp.new({host=os.getenv('UTCP_TCP_HOST') or '127.0.0.1',port=port,frame='line'}):call({},{message='hello over TCP'})
assert(result,err)
print('TCP result:',require('utcp.json').encode(result))
