package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local Cli = require('utcp.transports.cli')

local function assert_contains(value, expected)
  assert(
    value:find(expected, 1, true),
    string.format('expected %q to contain %q', value, expected)
  )
end

-- CLI command templates must support UTCP_ARG_* placeholders and nested
-- argument tables. This is the form used by CLI provider manuals.
local transport = Cli.new()

local result, err = transport:call({
  call_template_type = 'cli',
  commands = {
    {
      command = "printf '%s' tool=UTCP_ARG_tool_UTCP_END",
    },
  },
}, {
  tool = 'read',
  inputs = {
    path = 'README.md',
  },
})

assert(err == nil, err)
assert(type(result) == 'string')
assert_contains(result, 'tool=read')

local nested_result, nested_err = transport:call({
  call_template_type = 'cli',
  commands = {
    {
      command = 'printf %s UTCP_ARG_inputs_UTCP_END',
    },
  },
}, {
  inputs = {
    path = 'README.md',
  },
})

assert(nested_err == nil, nested_err)
assert(type(nested_result) == 'table')
assert(nested_result.path == 'README.md')

-- Existing command + args configuration must continue to work.
local legacy = Cli.new({
  command = "printf '%s'",
  args = {'ok'},
})

local legacy_result, legacy_err = legacy:call({}, {})
assert(legacy_err == nil, legacy_err)
assert(legacy_result == 'ok')

print('CLI transport tests: ok')
