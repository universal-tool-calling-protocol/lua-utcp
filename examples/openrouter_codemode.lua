package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Requires:
--   luarocks install lua-utcp
--   luarocks install lua-openai
--   export OPENROUTER_API_KEY=sk-or-...
--
-- Start the local calculator server first:
--   make server-http
--
-- This example demonstrates the intended agent loop:
-- OpenRouter generates Lua CodeMode -> CodeMode calls canonical UTCP tools.

local utcp = require('utcp')
local OpenRouter = require('openai.compat.openrouter')

local function strip_code_fence(source)
  source = source:gsub('^%s*```lua%s*', '')
  source = source:gsub('^%s*```%s*', '')
  source = source:gsub('%s*```%s*$', '')
  return source
end

local provider, err = utcp.load_provider('examples/provider.json')
assert(provider, err)

local client = utcp.Client.new()
assert(client:add_provider(provider))

local codemode = utcp.codemode.new(client)
local tools = assert(codemode:list_tools())

local tool_catalog = {}
for _, tool in ipairs(tools) do
  tool_catalog[#tool_catalog + 1] = {
    name = provider.name .. '.' .. tool.name,
    description = tool.description,
    inputs = tool.inputs or tool.input_schema,
    outputs = tool.outputs or tool.output_schema,
  }
end

local openrouter = OpenRouter.new(assert(os.getenv('OPENROUTER_API_KEY'),
  'OPENROUTER_API_KEY is required'))

local prompt = [[
You are the CodeMode planner for a Lua UTCP agent.

Generate ONLY executable Lua source code. Do not use markdown fences.
You have exactly one tool API:
  codemode.call_tool(name, args)

Use the canonical qualified tool names listed below. Do not invent tools.

The calculator tools return objects with a numeric `result` field.
Therefore, when using a calculator result as an input to another tool,
use `.result`, for example:
  local add_result = codemode.call_tool("calculator.add", {a=10, b=20})
  local sum = add_result.result

Return a Lua program that:
1. calls calculator.add with 10 and 20;
2. passes the numeric `.result` to calculator.multiply with 3;
3. returns { sum = 30, product = 90 }.

Available UTCP tools:
]] .. utcp.json.encode(tool_catalog)

local status, response = openrouter:create_chat_completion({
  {
    role = 'system',
    content = 'Generate small, deterministic Lua CodeMode programs for UTCP. Use tool output schemas exactly.'
  },
  { role = 'user', content = prompt }
}, {
  model = os.getenv('OPENROUTER_MODEL') or 'nvidia/nemotron-3.5-lightning:free',
  temperature = 0,
})

assert(status == 200, 'OpenRouter request failed: HTTP ' .. tostring(status))

local source = response.choices[1].message.content
assert(type(source) == 'string' and source ~= '', 'OpenRouter returned no Lua program')
source = strip_code_fence(source)

print('--- generated CodeMode ---')
print(source)
print('--- execution ---')

local execution, exec_err = codemode:call_tool_chain(source, {
  instruction_limit = 100000,
})
assert(execution, exec_err and exec_err.error)

print('result:', utcp.json.encode(execution.result))
