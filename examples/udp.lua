package.path='./lua/?.lua;./lua/?/init.lua;'..package.path
local udp=require('utcp.transports.udp')
local port=tonumber(os.getenv('UTCP_UDP_PORT') or '9001')
local result,err=udp.new({host=os.getenv('UTCP_UDP_HOST') or '127.0.0.1',port=port}):call({},{message='hello over UDP'})
assert(result,err)
print('UDP result:',require('utcp.json').encode(result))
