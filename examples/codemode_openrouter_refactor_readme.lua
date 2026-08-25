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

local filesystem_tool

for _, tool in ipairs(tool_catalog) do
  if tool.name == 'filesystem' then
    filesystem_tool = tool
    break
  end
end

assert(
  filesystem_tool,
  'canonical filesystem tool was not discovered'
)

print('filesystem wrapper: ' .. filesystem_tool.name)

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
- Use ONLY canonical UTCP tool names from the supplied catalog.
- Call tools ONLY through codemode.call_tool(name, args).
- Arguments MUST match the supplied input schemas exactly.
- Use actual tool results as inputs to subsequent calls.
- Never substitute a different tool because it sounds similar.
- The supplied tool catalog is authoritative.

AVAILABLE API:

  codemode.call_tool(name, args)

The function returns the tool result directly.

IMPORTANT:

The canonical UTCP tool named "filesystem" is a wrapper around
go-harness-filesystem.

"filesystem" is the ONLY UTCP tool name that may be used for
filesystem operations.

DO NOT call:

  codemode.call_tool("filesystem.read", ...)
  codemode.call_tool("filesystem.write", ...)
  codemode.call_tool("filesystem.list", ...)

Those are NOT canonical UTCP tool names.

Instead, call the canonical wrapper:

  codemode.call_tool("filesystem", {
    tool = "<ACTUAL CLI TOOL NAME>",
    inputs = {
      ...
    }
  })

The value of "tool" MUST be an actual tool name supported by the
filesystem CLI.

Do NOT guess this value.

Use the canonical filesystem tool schema and tool catalog supplied
below to determine the correct operation and its arguments.

TASK:

Refactor README.md.

The workflow MUST be:

1. Read README.md using the canonical filesystem tool.

2. The read operation MUST happen before any write operation.

3. Use the ACTUAL README content returned by the read operation as
   the source material for the refactoring.

4. Generate an improved README while preserving useful,
   project-specific existing content.

5. Write the improved README back to README.md using the canonical
   filesystem tool.

6. Do NOT modify any other file.

7. Do NOT commit anything.

8. Do NOT use shell.

9. Return:

   {
     read = <actual read result>,
     write = <actual write result>
   }

README REFACTORING RULES:

- Preserve project-specific information.
- Do not replace README.md with a generic template.
- Improve structure and organization.
- Improve clarity and readability.
- Improve examples only when supported by the original README.
- Correct obvious inconsistencies only when supported by the original
  README.
- Do NOT invent project features.
- Do NOT invent APIs.
- Do NOT invent commands.
- Do NOT invent installation instructions.
- Do NOT invent configuration.
- Do NOT invent tool names.
- Do NOT invent tool arguments.
- Do NOT invent output fields.

CRITICAL DATA-FLOW REQUIREMENT:

The write operation MUST depend on the actual read result.

The program MUST:

1. call the canonical filesystem read tool;
2. inspect the returned README content;
3. construct the improved README from that content;
4. call the canonical filesystem write tool;
5. return both results.

Do NOT hard-code a replacement README.

Do NOT write a generic README.

Do NOT write before reading.

Do NOT call unnecessary tools.

The generated program MUST terminate after the read/write workflow.

CANONICAL UTCP TOOL CATALOG:

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

local filesystem_inputs = filesystem_tool.inputs

if type(filesystem_inputs) == 'table'
  and type(filesystem_inputs.properties) == 'table'
then
  local tool_property = filesystem_inputs.properties.tool

  if type(tool_property) == 'table' then
    local enum = tool_property.enum

    if type(enum) == 'table' then
      for _, value in ipairs(enum) do
        if type(value) == 'string' then
          if value == 'read' or value:match('%.read$') then
            read_operation = value
          end

          if value == 'write' or value:match('%.write$') then
            write_operation = value
          end
        end
      end
    end
  end
end

print('filesystem read operation: ' .. tostring(read_operation))
print('filesystem write operation: ' .. tostring(write_operation))


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