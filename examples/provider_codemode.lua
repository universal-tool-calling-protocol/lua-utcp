package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local utcp = require('utcp')

-- 1. Load both manual declarations from one UTCP 1.1 config file.
local client, err = utcp.Client.new('examples/provider.json')
assert(client, err)

-- 3. CodeMode exposes a controlled codemode.call_tool(tool_name, args) API.
local codemode = utcp.codemode.new(client)

-- 4. One Lua program can chain multiple UTCP calls.
-- The HTTP server must expose POST /add and POST /multiply.
local execution, exec_err = codemode:call_tool_chain([[
  local sum = codemode.call_tool('calculator.add', {a = 10, b = 20})
  local product = codemode.call_tool('calculator.multiply', {a = sum, b = 3})

  print('sum =', sum)
  print('product =', product)

  return {
    sum = sum,
    product = product
  }
]])

assert(execution, exec_err and exec_err.error)
print('result:', utcp.json.encode(execution.result))
