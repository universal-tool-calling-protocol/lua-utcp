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

local config, err = utcp.load_config('examples/provider.json')
assert(config, err)

local client = assert(utcp.Client.new(config))

local codemode = utcp.codemode.new(client)
local tools = assert(codemode:list_tools())

local tool_catalog = {}
for _, tool in ipairs(tools) do
  tool_catalog[#tool_catalog + 1] = {
    name = tool.qualified_name or tool.name,
    description = tool.description,
    inputs = tool.inputs or tool.input_schema,
    outputs = tool.outputs or tool.output_schema,
  }
end

local openrouter = OpenRouter.new(assert(os.getenv('OPENROUTER_API_KEY'),
  'OPENROUTER_API_KEY is required'))

local prompt = [[
You are a Lua CodeMode planner for a UTCP agent.

Your task is to generate a SMALL, DETERMINISTIC Lua program that will be
executed directly by the UTCP CodeMode runtime.

IMPORTANT OUTPUT RULES:
- Return ONLY valid executable Lua source code.
- Do NOT use Markdown.
- Do NOT use ``` fences.
- Do NOT explain your answer.
- Do NOT print anything.
- Do NOT define functions unless absolutely necessary.
- Do NOT invent tools, APIs, variables, or fields.
- Do NOT call tools through any API other than codemode.call_tool.
- Use ONLY the canonical tool names from the tool catalog below.
- Arguments MUST match the tool input schema exactly.
- Use the actual result returned by a tool as input to subsequent tools.

AVAILABLE API:

  codemode.call_tool(name, args)

The function returns the tool result directly.

TASK:

1. Call `calculator.add` with:
   {
     a = 10,
     b = 20
   }

2. Read the numeric value from the returned `.result` field.

3. Call `calculator.multiply` with:
   {
     a = <the numeric result from calculator.add>,
     b = 3
   }

4. Return exactly:
   {
     sum = 30,
     product = 90
   }

The second tool call MUST use the result of the first tool call.
Do NOT hardcode 30 as the input to `calculator.multiply`.

Example of the required execution pattern:

  local sum_result = codemode.call_tool("calculator.add", {
    a = 10,
    b = 20
  })

  local product_result = codemode.call_tool("calculator.multiply", {
    a = sum_result.result,
    b = 3
  })

  return {
    sum = sum_result.result,
    product = product_result.result
  }

Do not copy the example blindly if the actual tool schemas below require
different argument names. The tool catalog is authoritative.

AVAILABLE UTCP TOOLS:
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
