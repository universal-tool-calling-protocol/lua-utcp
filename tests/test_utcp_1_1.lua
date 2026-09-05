package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local utcp = require('utcp')
local errors = require('utcp.errors')

local restricted = assert(utcp.new({
  warnings = false,
  manual_call_templates = {{
    name = 'restricted',
    call_template_type = 'http',
    manual = {
      manual_version = '1.0.0',
      utcp_version = '1.1.0',
      tools = {
        {name = 'safe', tool_call_template = {call_template_type = 'http', url = 'https://example.test'}},
        {name = 'shell', tool_call_template = {call_template_type = 'cli', command = 'true'}},
      },
    },
  }},
}))

assert(restricted:find_tool('restricted.safe'))
assert(restricted:find_tool('safe'))
assert(restricted:find_tool('restricted.shell') == nil)
assert(#restricted:list_tools() == 1)

local mixed = assert(utcp.new({
  warnings = false,
  manual_call_templates = {{
    name = 'mixed',
    call_template_type = 'http',
    allowed_communication_protocols = {'http', 'cli'},
    manual = {tools = {
      {name = 'safe', tool_call_template = {call_template_type = 'http', url = 'https://example.test'}},
      {name = 'shell', tool_call_template = {call_template_type = 'cli', command = 'true'}},
    }},
  }},
}))
assert(mixed:find_tool('mixed.shell'))
assert(#mixed:list_tools() == 2)

local provider = restricted.providers.restricted
restricted.registry:add_tool({name = 'injected', tool_call_template = {call_template_type = 'cli'}}, provider)
local result, protocol_err = restricted:call_tool('restricted.injected', {})
assert(result == nil)
assert(errors.is(protocol_err) and protocol_err.kind == 'protocol_not_allowed')

local legacy = assert(utcp.migration.manual({
  utcp_version = '0.1.0',
  provider_info = {name = 'legacy', version = '2.0'},
  tools = {{
    name = 'old',
    parameters = {type = 'object'},
    provider = {provider_type = 'http', method = 'GET', url = 'https://example.test'},
  }},
}))
assert(legacy.utcp_version == '1.1.0')
assert(legacy.info.title == 'legacy')
assert(legacy.tools[1].inputs.type == 'object')
assert(legacy.tools[1].tool_call_template.call_template_type == 'http')
assert(legacy.tools[1].tool_call_template.http_method == 'GET')

local vars = assert(utcp.new({
  variables = {TOKEN = 'global', api_TOKEN = 'scoped'},
  manual_call_templates = {{name = 'api', call_template_type = 'http', url = '${URL}'}},
}))
local required = vars:get_required_variables('api')
assert(#required == 1 and required[1] == 'URL')
local substituted = assert(utcp.variables.substitute('${TOKEN}', vars.variables, 'api', true))
assert(substituted == 'scoped')

local cyclic = {value = '${TOKEN}'}
cyclic.self = cyclic
local substituted_cycle = assert(utcp.variables.substitute(cyclic, vars.variables, 'api', true))
assert(substituted_cycle.value == 'scoped')
assert(substituted_cycle.self == substituted_cycle)
assert(#utcp.variables.find_required(cyclic) == 1)

local variable_probe = assert(utcp.new({variables = {MANUAL_URL = 'https://example.test/manual'}}))
local manual_variables = assert(variable_probe:get_required_variables_for_manual_and_tools({
  name = 'variable probe',
  call_template_type = 'http',
  url = '${MANUAL_URL}',
  manual = {tools = {{
    name = 'echo',
    tool_call_template = {
      call_template_type = 'http',
      url = '${TOOL_URL}/echo',
    },
  }}},
}))
assert(#manual_variables == 2)
assert(manual_variables[1] == 'MANUAL_URL' and manual_variables[2] == 'TOOL_URL')

local batch = assert(utcp.new())
local registrations = assert(batch:register_manuals({{
  name = 'batch-one',
  call_template_type = 'text',
  manual = {tools = {{
    name = 'read',
    tool_call_template = {call_template_type = 'text', path = '${FILE_PATH}'},
  }}},
}}))
assert(registrations[1].success == true)
local tool_variables = assert(batch:get_required_variables_for_registered_tool('batch_one.read'))
assert(#tool_variables == 1 and tool_variables[1] == 'FILE_PATH')
assert(batch:deregister_manual('missing') == false)

assert(mixed:deregister_manual('mixed'))
assert(mixed:find_tool('mixed.shell') == nil)

print('UTCP 1.1 compatibility tests: ok')
