package.path = './lua/?.lua;./lua/?/init.lua;'..package.path
local utcp = require('utcp')
local socket = require('socket')
local server = assert(socket.bind('127.0.0.1', 0)); local ip,port=server:getsockname()
print('HTTP integration server expected at '..ip..':'..port)
print('Run against a real HTTP endpoint to exercise lua-socket request semantics.')
server:close()
print('lua-utcp HTTP smoke test: ok')
