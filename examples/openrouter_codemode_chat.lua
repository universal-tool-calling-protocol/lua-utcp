package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Requires:
--   luarocks install lua-openai
--
-- Environment:
--   export OPENROUTER_API_KEY=sk-or-...
--
-- Start the local UTCP HTTP example server:
--   make server-http
--
-- This example demonstrates:
--
--   OpenRouter
--       ↓
--   Lua CodeMode program
--       ↓
--   codemode.call_tool("calculator.add", ...)
--       ↓
--   use .result
--       ↓
--   codemode.call_tool("calculator.multiply", ...)
--       ↓
--   return final result
--
-- The generated Lua source is executed by the UTCP CodeMode runtime.

local utcp = require('utcp')
local OpenRouter = require('openai.compat.openrouter')

local function strip_code_fence(source)
  source = source:gsub('^%s*```lua%s*', '')
  source = source:gsub('^%s*```%s*', '')
  source = source:gsub('%s*```%s*$', '')
  return source:gsub('^%s+', ''):gsub('%s+$', '')
end

--
-- Load UTCP provider.
--

local provider, err = utcp.load_provider('examples/provider.json')
assert(provider, err)

--
-- Create canonical UTCP client.
--

local client = utcp.Client.new()

assert(client:add_provider(provider))

--
-- Create CodeMode runtime.
--

local codemode = utcp.codemode.new(client)

--
-- Build the tool catalog exposed to the LLM.
--
-- The model sees only canonical qualified UTCP tool names.
--

local catalog = {}

for _, tool in ipairs(codemode:list_tools()) do
  catalog[#catalog + 1] = {
    name = provider.name .. '.' .. tool.name,
    description = tool.description,
    inputs = tool.inputs or tool.input_schema,
    outputs = tool.outputs or tool.output_schema,
  }
end

--
-- OpenRouter client.
--

local api_key = assert(
  os.getenv('OPENROUTER_API_KEY'),
  'OPENROUTER_API_KEY is required'
)

local router = OpenRouter.new(api_key)

--
-- CodeMode planner.
--
-- The planner is deliberately constrained:
--
--   LLM -> Lua source
--   Lua source -> canonical UTCP tools
--
-- The model must not invent tools or bypass CodeMode.
--

local chat = router:new_chat_session({
  model = os.getenv('OPENROUTER_MODEL')
    or 'nvidia/nemotron-3.5-lightning:free',

  temperature = 0,

  messages = {
    {
      role = 'system',

      content = [[
You are a Lua UTCP CodeMode planner.

Your generated output is executable Lua source code.
It will be passed directly to the UTCP CodeMode runtime.

==================================================
STRICT OUTPUT CONTRACT
==================================================

Return ONLY executable Lua source code.

Do NOT:
- return Markdown
- use ``` fences
- explain your answer
- describe the solution
- return JSON
- return natural language
- print anything
- invent APIs
- invent tools
- call HTTP directly
- call shell commands
- call filesystem APIs
- call external APIs directly

The generated program MUST be valid Lua.

The generated program MUST finish by returning the requested value.

==================================================
AVAILABLE TOOL API
==================================================

The ONLY tool API available to your program is:

    codemode.call_tool(name, args)

Every tool invocation MUST use this API.

Example:

    local result = codemode.call_tool(
      "calculator.add",
      {
        a = 10,
        b = 20
      }
    )

==================================================
TOOL NAMES
==================================================

Use ONLY canonical qualified tool names from the tool catalog.

Never invent a tool name.

For example, if the catalog contains:

    calculator.add

then use exactly:

    codemode.call_tool("calculator.add", ...)

Do not use:

    add
    calculator_add
    calculator.addition
    math.add

==================================================
TOOL ARGUMENTS
==================================================

Tool arguments MUST match the input schema from the catalog.

Do not invent argument names.

Do not add unnecessary arguments.

Do not omit required arguments.

==================================================
TOOL RESULTS
==================================================

Calculator tools return an object containing:

    result

The `result` field contains the numeric result.

When chaining tools, extract `.result`.

Correct:

    local add_result = codemode.call_tool(
      "calculator.add",
      {
        a = 7,
        b = 8
      }
    )

    local multiply_result = codemode.call_tool(
      "calculator.multiply",
      {
        a = add_result.result,
        b = 4
      }
    )

Incorrect:

    local multiply_result = codemode.call_tool(
      "calculator.multiply",
      {
        a = add_result,
        b = 4
      }
    )

Incorrect:

    local multiply_result = codemode.call_tool(
      "calculator.multiply",
      {
        a = 15,
        b = 4
      }
    )

The second form is forbidden because it hardcodes a value that must come
from the first tool execution.

==================================================
TOOL CHAINING
==================================================

When one tool depends on another tool:

1. Call the first tool.
2. Store its result.
3. Extract the required field.
4. Pass that value to the next tool.
5. Store the second result.
6. Extract the required field.
7. Return the final value.

The generated program must perform real tool chaining.

Do not simulate tool results.

Do not calculate tool results locally when the task requires a tool call.

Do not hardcode values that are expected to come from tool execution.

==================================================
DETERMINISTIC EXECUTION
==================================================

Generate the smallest program that satisfies the request.

Avoid:
- unnecessary functions
- loops
- conditionals
- helper abstractions
- logging
- printing
- unrelated calculations
- unnecessary variables

Prefer direct sequential tool calls.

==================================================
EXPECTED PROGRAM STRUCTURE
==================================================

For a two-step calculator chain, the structure should look like:

    local first = codemode.call_tool("calculator.add", {
      a = 7,
      b = 8
    })

    local second = codemode.call_tool("calculator.multiply", {
      a = first.result,
      b = 4
    })

    return {
      sum = first.result,
      product = second.result
    }

Use the actual tool schemas from the catalog as the authoritative source.

==================================================
AVAILABLE UTCP TOOLS
==================================================

]] .. utcp.json.encode(catalog),
    },
  },
})

--
-- Ask OpenRouter to generate the CodeMode program.
--

local source = chat:send([[
Generate the Lua CodeMode program for this task.

TASK:

1. Call `calculator.add` with:
     a = 7
     b = 8

2. Store the returned object.

3. Extract its numeric `.result`.

4. Call `calculator.multiply` with:
     a = the actual `.result` returned by `calculator.add`
     b = 4

5. Store the returned object.

6. Extract its numeric `.result`.

7. Return exactly:

     {
       sum = 15,
       product = 60
     }

IMPORTANT:

The second tool call MUST use the actual result of the first tool call.

Therefore this is required:

    local add_result = codemode.call_tool("calculator.add", {
      a = 7,
      b = 8
    })

    local multiply_result = codemode.call_tool("calculator.multiply", {
      a = add_result.result,
      b = 4
    })

The following is NOT allowed:

    a = 15

because the purpose of this example is to demonstrate real CodeMode
tool chaining.

Generate ONLY executable Lua source code.
]])

assert(
  type(source) == 'string' and source ~= '',
  'OpenRouter did not return Lua source'
)

--
-- Some models may still return a Markdown fence despite the prompt.
-- Remove it defensively before CodeMode execution.
--

source = strip_code_fence(source)

--
-- Show generated CodeMode source.
--

print('--- generated CodeMode ---')
print(source)
print('--- execution ---')

--
-- Execute the generated Lua program through canonical UTCP CodeMode.
--

local execution, exec_err = codemode:call_tool_chain(source, {
  instruction_limit = 100000,
})

assert(
  execution,
  exec_err and exec_err.error or 'CodeMode execution failed'
)

--
-- Show the final result.
--

print('result:', utcp.json.encode(execution.result))