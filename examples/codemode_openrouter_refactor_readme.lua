package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Requires:
--   luarocks install lua-utcp
--   luarocks install lua-openai
--   export OPENROUTER_API_KEY=sk-or-...
--
-- This example demonstrates:
--
--   OpenRouter
--       ↓
--   Generate Lua CodeMode
--       ↓
--   CodeMode
--       ↓
--   canonical UTCP CLI wrapper
--       ↓
--   go-harness-filesystem tools
--
-- The important property is that OpenRouter generates the workflow,
-- while CodeMode executes the actual canonical tool calls.

local utcp = require('utcp')
local OpenRouter = require('openai.compat.openrouter')

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

local function add_provider(client, path)
  local provider = load_provider(path)
  assert(client:add_provider(provider))
  return provider
end

local client = utcp.Client.new()

local provider = add_provider(
  client,
  'examples/provider.json'
)

local codemode = utcp.codemode.new(client)

--
-- Discover canonical UTCP tools.
--

local tools = assert(codemode:list_tools())

assert(
  #tools > 0,
  'CLI provider returned no tools'
)

local tool_catalog = {}

for _, tool in ipairs(tools) do
  tool_catalog[#tool_catalog + 1] = {
    name = tool.name,
    description = tool.description,
    inputs = tool.inputs or tool.input_schema,
    outputs = tool.outputs or tool.output_schema,
  }
end

print('--- canonical tools ---')

for _, tool in ipairs(tool_catalog) do
  print('  ' .. tostring(tool.name))
end

print('-----------------------')

--
-- Find the canonical filesystem wrapper.
--

--
-- Discover the canonical filesystem tools.
--

local filesystem_read_tool
local filesystem_write_tool

for _, tool in ipairs(tool_catalog) do
  if tool.name == 'filesystem.read' then
    filesystem_read_tool = tool
  elseif tool.name == 'filesystem.write' then
    filesystem_write_tool = tool
  end
end

assert(
  filesystem_read_tool,
  'canonical filesystem.read tool was not discovered'
)

assert(
  filesystem_write_tool,
  'canonical filesystem.write tool was not discovered'
)

print('filesystem read tool: ' .. filesystem_read_tool.name)
print('filesystem write tool: ' .. filesystem_write_tool.name)


--
-- OpenRouter.
--

local api_key = assert(
  os.getenv('OPENROUTER_API_KEY'),
  'OPENROUTER_API_KEY is required'
)

local openrouter = OpenRouter.new(api_key)

--
-- The model must reason from the actual canonical catalog.
--
-- Do not hard-code filesystem.read / filesystem.write as UTCP tools.
--
-- The canonical UTCP tool is "filesystem".
-- Its "tool" argument is passed to go-harness-filesystem and must
-- contain an actual CLI tool name supported by that executable.
--

local prompt = [[
You are a Lua CodeMode planner for a UTCP agent.

Generate a SMALL, DETERMINISTIC Lua program that will be executed
directly by the UTCP CodeMode runtime.

The user wants to refactor README.md.

IMPORTANT OUTPUT RULES:

- Return ONLY executable Lua source code.
- Do NOT return Markdown.
- Do NOT use ``` fences.
- Do NOT explain the code.
- Do NOT print anything.
- Do NOT define functions unless absolutely necessary.
- Do NOT invent tools.
- Do NOT invent tool arguments.
- Do NOT invent result fields.
- Use ONLY canonical tool names from the supplied UTCP tool catalog.
- Call tools ONLY through codemode.call_tool(name, args).
- Arguments MUST match the supplied input schemas exactly.
- Use actual tool results as inputs to subsequent calls.
- Never substitute a different tool because it sounds similar.
- The tool catalog is authoritative.

AVAILABLE API:

  codemode.call_tool(name, args)

The function returns the tool result directly.

TASK:

Refactor README.md.

The workflow MUST be:

1. Call the canonical filesystem.read tool to read README.md.

2. Use the ACTUAL README content returned by filesystem.read.

3. Generate an improved README while preserving the existing
   project-specific content.

4. Call the canonical filesystem.write tool to write the improved
   README back to README.md.

5. Do NOT modify any other file.

6. Do NOT use shell.

7. Do NOT use git.

8. Do NOT commit anything.

9. Return:

   {
     read = <actual read result>,
     write = <actual write result>
   }

IMPORTANT DATA FLOW:

The write content MUST be derived from the actual read result.

Do NOT hard-code a replacement README.

Do NOT generate a generic README.

Do NOT call filesystem.write before filesystem.read.

Do NOT invent information that is not present in the README or
canonical tool catalog.

CANONICAL UTCP TOOLS:

]] .. utcp.json.encode(tool_catalog)

print('--- requesting Lua from OpenRouter ---')

local status, response = openrouter:create_chat_completion({
  {
    role = 'system',
    content = [[
Generate small, deterministic Lua CodeMode programs for UTCP.

Use ONLY the canonical tools and schemas supplied by the user.

Never hallucinate tools, arguments, or result fields.

The canonical UTCP tool "filesystem" is a wrapper around the
go-harness-filesystem CLI.

Never invent filesystem.read or filesystem.write as UTCP tool names.

The generated program must execute a real filesystem inspection
followed by a filesystem mutation.

The generated program MUST terminate after completing the workflow.
]]
  },
  {
    role = 'user',
    content = prompt
  }
}, {
  model = os.getenv('OPENROUTER_MODEL')
    or 'inclusionai/ling-3.0-flash',
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

assert(
  source ~= '',
  'OpenRouter returned an empty Lua program'
)

print('--- generated CodeMode ---')
print(source)
print('--------------------------')

--
-- CodeMode smoke test.
--

print('--- CodeMode smoke test ---')

local smoke_source = [[
return {
  ok = true
}
]]

local smoke_execution, smoke_err = codemode:call_tool_chain(
  smoke_source,
  {
    instruction_limit = 10000,
  }
)

assert(
  smoke_execution,
  smoke_err and smoke_err.error or
    'CodeMode smoke test failed'
)

print(
  'smoke result:',
  utcp.json.encode(smoke_execution.result)
)

--
-- IMPORTANT:
--
-- Do NOT hard-code "filesystem.read".
--
-- The wrapper is "filesystem", but the operation name is determined
-- by the actual go-harness-filesystem CLI.
--
-- We discover likely read/write operations from the canonical tool
-- metadata when available.
--

local function find_tool_suffix(name, suffix)
  if type(name) ~= 'string' then
    return false
  end

  return name == suffix
    or name:match('%.' .. suffix .. '$') ~= nil
    or name:match(':' .. suffix .. '$') ~= nil
end

local read_operation
local write_operation

for _, tool in ipairs(tool_catalog) do
  if find_tool_suffix(tool.name, 'read') then
    read_operation = tool.name
  end

  if find_tool_suffix(tool.name, 'write') then
    write_operation = tool.name
  end
end

--
-- If the CLI exposes the operation names through the filesystem
-- wrapper schema, inspect that schema instead.
--


local execution, exec_err = codemode:call_tool_chain(
  source,
  {
    instruction_limit = 100000,
  }
)

assert(
  execution,
  exec_err and exec_err.error or
    'CodeMode execution failed'
)

print('--- execution result ---')
print(
  utcp.json.encode(execution.result)
)