package.path='./lua/?.lua;./lua/?/init.lua;'..package.path

local utcp = require('utcp')

local client = utcp.Client.new({
  providers = {
    {
      name = 'calculator',
      tools = {
        {name = 'add', description = 'Add two numbers', inputs = {type='object'}, tool_call_template = {call_template_type='test'}},
        {name = 'mul', description = 'Multiply two numbers', inputs = {type='object'}, tool_call_template = {call_template_type='test'}},
      },
    },
  },
})

function client:call_tool(name, args)
  if name == 'add' then return (args.a or 0) + (args.b or 0) end
  if name == 'mul' then return (args.a or 0) * (args.b or 0) end
  return nil, 'unknown test tool: '..name
end

local codemode = utcp.codemode.new(client)
assert(type(codemode.call_tool) == 'function')
assert(type(codemode.call_tool_chain) == 'function')

-- The CodeMode sandbox must call tools only through codemode.call_tool().
local result, err = codemode:call_tool_chain([[
  local sum = codemode.call_tool('calculator.add', {a = 10, b = 20})
  local product = codemode.call_tool('calculator.mul', {a = sum, b = 3})
  print('workflow complete', product)
  return product
]])

assert(result, err and err.error)
assert(result.result == 90)
assert(result.logs[1] == 'workflow complete\t90')
assert(result.interfaces[1] == 'add')

local iface = codemode:get_tool_interface('calculator.add')
assert(iface.name == 'calculator.add')
assert(iface.description == 'Add two numbers')

local unknown, unknown_err = codemode:call_tool('calculator.does_not_exist', {})
assert(unknown == nil)
assert(unknown_err ~= nil)

local bad, bad_err = codemode:call_tool_chain([[return codemode.call_tool('add', 'not-a-table')]])
assert(bad == nil)
assert(bad_err.stage == 'execute')

local compile, compile_err = codemode:call_tool_chain('this is not valid lua')
assert(compile == nil)
assert(compile_err.stage == 'compile')

-- Old namespace-based execution must no longer be available.
local old, old_err = codemode:call_tool_chain([[return calculator.add({a = 1, b = 2})]])
assert(old == nil)
assert(old_err.stage == 'execute')

-- The sandbox must not expose the underlying UTCP client.
local exposed, exposed_err = codemode:call_tool_chain([[return client]])
assert(exposed == nil)
assert(exposed_err.stage == 'execute')

print('codemode tests: ok')
