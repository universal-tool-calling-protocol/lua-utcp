package.path='./lua/?.lua;./lua/?/init.lua;'..package.path

local utcp = require('utcp')

local client = utcp.Client.new({
  providers = {
    {
      name = 'calculator',
      tools = {
        {name = 'add', description = 'Add two numbers', inputs = {type='object'}, tool_call_template = {call_template_type='test'}},
        {name = 'multiply', description = 'Multiply two numbers', inputs = {type='object'}, tool_call_template = {call_template_type='test'}},
      },
    },
  },
})

function client:call_tool(name, args)
  if name == 'add' then return (args.a or 0) + (args.b or 0) end
  if name == 'multiply' then return (args.a or 0) * (args.b or 0) end
  return nil, 'unknown tool: '..name
end

local codemode = utcp.codemode.new(client)
local execution, err = codemode:call_tool_chain([[
  local sum = codemode.call_tool('add', {a = 10, b = 20})
  local result = codemode.call_tool('multiply', {a = sum, b = 3})
  print('CodeMode workflow result:', result)
  return {sum = sum, result = result}
]])

assert(execution, err and err.error)
print('result:', utcp.json.encode(execution.result))
print('logs:', utcp.json.encode(execution.logs))
