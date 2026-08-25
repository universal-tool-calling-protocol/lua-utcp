package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Requires:
--   luarocks install lua-utcp
--   luarocks install lua-openai
--   export OPENROUTER_API_KEY=sk-or-...
--
-- This example demonstrates an end-to-end CodeMode workflow:
--
--   OpenRouter
--       ↓
--   generate Lua CodeMode
--       ↓
--   CodeMode
--       ↓
--   canonical filesystem.read
--       ↓
--   refactor README
--       ↓
--   canonical filesystem.patch
--
-- The model never gets direct filesystem access.
-- All filesystem operations go through codemode.call_tool().

local utcp = require('utcp')
local OpenRouter = require('openai.compat.openrouter')

local function assert_ok(value, message)
  assert(value ~= nil, message or 'operation failed')
  return value
end

local function strip_code_fence(source)
  source = source:gsub('^%s*```lua%s*', '')
  source = source:gsub('^%s*```%s*', '')
  source = source:gsub('%s*```%s*$', '')
  return source
end

local function load_provider(path)
  local provider, err = utcp.load_provider(path)
  assert(provider, err)
  return provider
end

local client = utcp.Client.new()

local provider = load_provider('examples/provider.json')
assert(client:add_provider(provider))

local codemode = utcp.codemode.new(client)

local tools = assert_ok(codemode:list_tools(), 'failed to list UTCP tools')
assert(#tools > 0, 'provider returned no tools')

local catalog = {}

for _, tool in ipairs(tools) do
  catalog[#catalog + 1] = {
    name = tool.name,
    description = tool.description,
    inputs = tool.inputs or tool.input_schema,
    outputs = tool.outputs or tool.output_schema,
  }
end

local function require_tool(name)
  for _, tool in ipairs(catalog) do
    if tool.name == name then
      return tool
    end
  end

  error('missing canonical tool: ' .. name)
end

require_tool('filesystem.read')
require_tool('filesystem.patch')

local api_key = assert(
  os.getenv('OPENROUTER_API_KEY'),
  'OPENROUTER_API_KEY is required'
)

local openrouter = OpenRouter.new(api_key)
local model = os.getenv('OPENROUTER_MODEL')
  or 'nvidia/nemotron-3.5-lightning:free'

local catalog_json = assert(utcp.json.encode(catalog))

local status, response = openrouter:create_chat_completion({
  {
    role = 'system',
    content = [[
You generate a deterministic Lua program for lua-utcp CodeMode.

Return ONLY executable Lua source code.
Do not use Markdown fences.

The program MUST perform the complete README refactoring workflow.
It is NOT acceptable to only read README.md.

Available tool API:

  codemode.call_tool(name, args)

IMPORTANT:
The program MUST contain BOTH of these calls:

  local read_result = codemode.call_tool(
    "filesystem.read",
    { path = "README.md" }
  )

and later:

  local patch_result = codemode.call_tool(
    "filesystem.patch",
    { patch = patch }
  )

The program must use the actual value of read_result when constructing
the patch.

Required execution flow:

1. Read README.md:

   local read_result = codemode.call_tool(
     "filesystem.read",
     { path = "README.md" }
   )

2. Extract the actual README content from read_result.

3. Construct a unified diff stored in a variable named `patch`.

4. The patch must improve README.md structure, clarity, and readability.

5. The patch must be based ONLY on the README content returned by
   filesystem.read.

6. Preserve all project-specific facts already present in the README.

7. Never invent:
   - features
   - APIs
   - commands
   - dependencies
   - URLs
   - versions
   - benchmarks
   - architecture claims
   - project capabilities

8. Apply the generated diff:

   local patch_result = codemode.call_tool(
     "filesystem.patch",
     { patch = patch }
   )

9. Return patch_result.

The program MUST NOT terminate after filesystem.read.

The program MUST call filesystem.patch after filesystem.read.

The program MUST NOT call filesystem.read more than once.

The program MUST NOT call filesystem.write.

The patch must modify ONLY README.md.

Use ONLY these canonical tool names:

  filesystem.read
  filesystem.patch

Never use:
  read
  patch
  filesystem

Do not use:
  os.execute
  io.popen
  require
  shell commands
  git
  direct filesystem access

The program must terminate and return a Lua value.

Canonical tool catalog:
]] .. catalog_json,
  },
  {
    role = 'user',
    content = 'Refactor README.md using the workflow described above.',
  },
}, {
  model = model,
  temperature = 0,
})

assert(
  status == 200,
  'OpenRouter request failed: HTTP ' .. tostring(status)
)

local source = response
  and response.choices
  and response.choices[1]
  and response.choices[1].message
  and response.choices[1].message.content

assert(
  type(source) == 'string' and source ~= '',
  'OpenRouter returned no Lua program'
)

source = strip_code_fence(source)

print('--- generated README refactor CodeMode ---')
print(source)
print('------------------------------------------')

local execution, execution_error = codemode:call_tool_chain(
  source,
  { instruction_limit = 30000 }
)

assert(
  execution,
  utcp.json.encode(execution_error)
)

print('--- filesystem.patch result ---')
print(utcp.json.encode(execution.result))
print('--------------------------------')

print('CodeMode README refactor: ok')