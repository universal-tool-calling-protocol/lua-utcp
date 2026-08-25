package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Requires:
--   luarocks install lua-utcp
--   luarocks install lua-openai
--   export OPENROUTER_API_KEY=sk-or-...
--
-- This example demonstrates a small end-to-end CodeMode workflow:
--
--   OpenRouter
--       ↓
--   generate Lua CodeMode
--       ↓
--   CodeMode
--       ↓
--   canonical filesystem.read
--       ↓
--   OpenRouter refactors the actual README
--       ↓
--   generate Lua CodeMode
--       ↓
--   CodeMode
--       ↓
--   canonical filesystem.patch
--
-- The important part is that the model never gets direct filesystem
-- access. All filesystem operations go through codemode.call_tool().

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
local model = os.getenv('OPENROUTER_MODEL') or 'inclusionai/ling-3.0-flash'

local function request_lua(instruction)
  local status, response = openrouter:create_chat_completion({
    {
      role = 'system',
      content = [[
You generate small, deterministic Lua programs for lua-utcp CodeMode.

Return ONLY executable Lua source code. Do not use Markdown fences.

The sandbox exposes exactly one way to invoke UTCP tools:

  codemode.call_tool(name, args)

Use the exact canonical tool names from the supplied catalog.
Never invent, shorten, or wrap tool names.

For filesystem operations, call the canonical names directly, for example:

  codemode.call_tool("filesystem.read", { path = "README.md" })

or:

  codemode.call_tool("filesystem.patch", { patch = patch })

Do not call "read", "patch", or "filesystem".
Do not use os.execute, io.popen, require, shell commands, or git.
Do not access the host filesystem directly.

The program must terminate and return a Lua value.
]],
    },
    {
      role = 'user',
      content = instruction,
    },
  }, {
    model = model,
    temperature = 0,
  })

  assert(status == 200, 'OpenRouter request failed: HTTP ' .. tostring(status))

  local source = response
    and response.choices
    and response.choices[1]
    and response.choices[1].message
    and response.choices[1].message.content

  assert(type(source) == 'string' and source ~= '', 'OpenRouter returned no Lua program')
  return strip_code_fence(source)
end

local catalog_json = assert(utcp.json.encode(catalog))

-- First stage: let the model produce the smallest possible program whose
-- only job is to read README.md through the canonical UTCP tool.
local read_source = request_lua([[
Generate a Lua CodeMode program that reads README.md.

Requirements:
1. Call exactly one UTCP tool.
2. The tool must be the canonical filesystem.read tool.
3. Pass { path = "README.md" }.
4. Return the complete result of that call.
5. Do not call any other tool.

Canonical tool catalog:
]] .. catalog_json)

print('--- generated read CodeMode ---')
print(read_source)
print('--------------------------------')

local read_execution, read_error = codemode:call_tool_chain(
  read_source,
  { instruction_limit = 10000 }
)

assert(read_execution, utcp.json.encode(read_error))

local read_result = read_execution.result
assert(read_result ~= nil, 'filesystem.read returned no result')

print('--- filesystem.read result ---')
print(utcp.json.encode(read_result))
print('--------------------------------')

-- Second stage: send the actual README returned by the tool to OpenRouter.
-- OpenRouter produces a unified diff, but the diff is still applied by
-- CodeMode through the canonical filesystem.patch tool.
local read_json = assert(utcp.json.encode(read_result))

local patch_source = request_lua([[
Generate a Lua CodeMode program that refactors README.md.

The actual result returned by filesystem.read is included below.
Use that content as the only source of truth for the README.

Requirements:
1. Create a real unified diff for README.md.
2. The diff must improve structure, clarity, and readability.
3. Preserve project-specific facts already present in the README.
4. Do not invent features, APIs, commands, dependencies, URLs,
   versions, benchmarks, or other project facts.
5. The patch must modify ONLY README.md.
6. Apply the diff by calling exactly one canonical UTCP tool:

     codemode.call_tool("filesystem.patch", { patch = patch })

7. Return the patch result.
8. Do not call filesystem.read again.
9. Do not call filesystem.write.
10. Do not use shell, git, os.execute, io.popen, require, or direct
    filesystem access.

The patch must be derived from the actual README below.

ACTUAL filesystem.read RESULT:
]] .. read_json .. [[

CANONICAL TOOL CATALOG:
]] .. catalog_json)

print('--- generated patch CodeMode ---')
print(patch_source)
print('--------------------------------')

local patch_execution, patch_error = codemode:call_tool_chain(
  patch_source,
  { instruction_limit = 20000 }
)

assert(patch_execution, utcp.json.encode(patch_error))

print('--- filesystem.patch result ---')
print(utcp.json.encode(patch_execution.result))
print('--------------------------------')

print('CodeMode README refactor: ok')
