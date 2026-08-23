package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local template = require('utcp.template')

local args = {
  a = 10,
  b = 20,
  enabled = true,
  nested = { value = 42 },
}

local body = template.render_value({
  a = '{a}',
  b = '{b}',
  enabled = '{enabled}',
  nested = { value = '{nested.value}' },
  label = 'value-{a}',
}, args)

assert(type(body.a) == 'number' and body.a == 10)
assert(type(body.b) == 'number' and body.b == 20)
assert(type(body.enabled) == 'boolean' and body.enabled == true)
assert(type(body.nested.value) == 'number' and body.nested.value == 42)
assert(body.label == 'value-10')

print('template typed rendering: ok')
