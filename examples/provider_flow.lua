package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local utcp = require('utcp')

local provider, err = utcp.load_provider('examples/provider.json')
assert(provider, err)

local client = utcp.Client.new({ providers = { provider } })

print('provider:', provider.name)
print('registered tools:')
for _, tool in ipairs(client:list_tools()) do
  print('  -', tool.name, '-', tool.description)
end

local codemode = utcp.codemode.new(client)
local interfaces = codemode:interfaces()
print('codemode interfaces:')
for _, name in ipairs(interfaces) do print('  -', name) end

print('\nRun examples/provider_codemode.lua after starting the HTTP provider.')
