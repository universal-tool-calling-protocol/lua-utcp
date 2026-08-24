package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Requires:
--   luarocks install lua-openai
--
-- Environment:
--   export OPENROUTER_API_KEY=sk-or-...
--
-- Start the local calculator server first:
--   make server-http
--
-- This example demonstrates the CodeMode repair loop:
--
--   OpenRouter -> Lua -> CodeMode -> UTCP tool
--                         |
--                       error
--                         |
--                    structured error
--                         |
--                     OpenRouter
--                         |
--                    repaired Lua
--                         |
--                      CodeMode
--

local utcp = require('utcp')
local OpenRouter = require('openai.compat.openrouter')

local function strip_code_fence(source)
  source = source:gsub('^%s*```lua%s*', '')
  source = source:gsub('^%s*```%s*', '')
  source = source:gsub('%s*```%s*$', '')
  return source:gsub('^%s+', ''):gsub('%s+$', '')
end

local provider, err = utcp.load_provider('examples/provider.json')
assert(provider, err)

local client = utcp.Client.new()
assert(client:add_provider(provider))

local codemode = utcp.codemode.new(client)

local catalog = {}
for _, tool in ipairs(codemode:list_tools()) do
  catalog[#catalog + 1] = {
    name = provider.name .. '.' .. tool.name,
    description = tool.description,
    inputs = tool.inputs or tool.input_schema,
    outputs = tool.outputs or tool.output_schema,
  }
end

local router = OpenRouter.new(assert(
  os.getenv('OPENROUTER_API_KEY'),
  'OPENROUTER_API_KEY is required'
))

local chat = router:new_chat_session({
  model = os.getenv('OPENROUTER_MODEL')
    or 'nvidia/nemotron-3.5-lightning:free',
  temperature = 0,
  messages = {
    {
      role = 'system',
      content = [[
You are a Lua UTCP CodeMode planner.

Return ONLY executable Lua source code.
Do not use Markdown fences.
Do not explain the program.
Do not invent tools.
Do not call HTTP directly.
Use only codemode.call_tool(name, args).
Use canonical qualified tool names from the catalog.
Calculator tools return an object with a numeric `.result` field.

Available UTCP tools:
]] .. utcp.json.encode(catalog),
    },
  },
})

-- The first program is deliberately requested with a bad tool name so the
-- example deterministically demonstrates error -> repair -> execution.
local source = chat:send([[
Generate a Lua program that calculates 7 + 8 and then multiplies the result
by 4.

For this first attempt ONLY, intentionally make exactly one mistake:
call `calculator.multiplay` instead of `calculator.multiply`.

Still use the result of the add call as the first argument of the multiply
call and return:
  {sum = 15, product = 60}

Return ONLY Lua source code.
]])

assert(type(source) == 'string' and source ~= '',
  'OpenRouter did not return Lua source')
source = strip_code_fence(source)

local max_repairs = 2
local execution
local exec_err

for attempt = 0, max_repairs do
  print(string.format('--- CodeMode attempt %d ---', attempt + 1))
  print(source)

  execution, exec_err = codemode:call_tool_chain(source, {
    instruction_limit = 100000,
  })

  if execution then
    break
  end

  print('structured error:', utcp.json.encode(exec_err))

  if not exec_err.retryable or attempt >= max_repairs then
    error(exec_err.message or exec_err.error or 'CodeMode execution failed')
  end

  local repair_prompt = [[
The previous Lua CodeMode program failed during execution.

Repair the program and return ONLY executable Lua source code.
Do not explain the fix.
Do not use Markdown fences.
Do not invent tools.
Use only codemode.call_tool(name, args).
Preserve the requested result and use actual tool results for chaining.

Previous program:

]] .. source .. [[

Structured execution error:

]] .. utcp.json.encode(exec_err) .. [[

Repair the program so that it calculates 7 + 8, passes the actual numeric
`.result` to calculator.multiply with b = 4, and returns:

{
  sum = 15,
  product = 60
}

Return ONLY the repaired Lua source code.
]]

  source = chat:send(repair_prompt)
  assert(type(source) == 'string' and source ~= '',
    'OpenRouter did not return repaired Lua source')
  source = strip_code_fence(source)
end

assert(execution, exec_err and exec_err.message or 'CodeMode execution failed')

print('--- final result ---')
print(utcp.json.encode(execution.result))
