package.path='./lua/?.lua;./lua/?/init.lua;'..package.path

local utcp = require('utcp')

local config, err = utcp.load_config('examples/provider.json')
assert(config, err)
assert(#config.manual_call_templates == 2)
assert(config.manual_call_templates[1].name == 'calculator')
assert(config.manual_call_templates[1].call_template_type == 'http')
assert(config.manual_call_templates[2].name == 'filesystem')
assert(config.manual_call_templates[2].call_template_type == 'cli')

local client = utcp.Client.new()
assert(client:load_provider('examples/provider.json'))
assert(#client:list_tools() == 6)
assert(client:find_tool('calculator.add'))
assert(client:find_tool('calculator.multiply'))
assert(client:find_tool('filesystem.read'))
assert(client:find_tool('filesystem.write'))
assert(client:find_tool('filesystem.diff.unified'))
assert(client:find_tool('filesystem.patch'))

local cm = utcp.codemode.new(client)
assert(type(cm.call_tool_chain) == 'function')

print('provider.json tests: ok')
