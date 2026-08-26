package.path='./lua/?.lua;./lua/?/init.lua;'..package.path

local utcp = require('utcp')

local provider, err = utcp.load_provider('examples/provider.json')
assert(provider, err)
assert(provider.name == 'calculator')
assert(provider.manual)
assert(#provider.manual.tools >= 2)
assert(provider.manual.tools[1].name == 'add')

local client = utcp.Client.new()
assert(client:load_provider('examples/provider.json'))
assert(#client:list_tools() >= 2)
assert(client:find_tool('add'))
assert(client:find_tool('multiply'))

local cm = utcp.codemode.new(client)
assert(type(cm.call_tool_chain) == 'function')

print('provider.json tests: ok')
