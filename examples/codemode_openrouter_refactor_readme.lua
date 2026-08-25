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
--   canonical UTCP tools
--       ↓
--   filesystem.read
--       ↓
--   filesystem.patch
--
-- OpenRouter generates the workflow.
-- CodeMode executes the canonical UTCP tools.

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

add_provider(
  client,
  'examples/provider.json'
)

local codemode = utcp.codemode.new(client)

--
-- Discover canonical UTCP tools.
--

local tools = assert(
  codemode:list_tools()
)

assert(
  #tools > 0,
  'provider returned no tools'
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
-- The provider MUST expose these as real canonical UTCP tools.
--

local filesystem_read_tool
local filesystem_write_tool
local filesystem_patch_tool

for _, tool in ipairs(tool_catalog) do
  if tool.name == 'filesystem.read' then
    filesystem_read_tool = tool
  elseif tool.name == 'filesystem.write' then
    filesystem_write_tool = tool
  elseif tool.name == 'filesystem.patch' then
    filesystem_patch_tool = tool
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

assert(
  filesystem_patch_tool,
  'canonical filesystem.patch tool was not discovered'
)

print(
  'filesystem read tool: ' ..
  filesystem_read_tool.name
)

print(
  'filesystem write tool: ' ..
  filesystem_write_tool.name
)

print(
  'filesystem patch tool: ' ..
  filesystem_patch_tool.name
)

--
-- OpenRouter.
--

local api_key = assert(
  os.getenv('OPENROUTER_API_KEY'),
  'OPENROUTER_API_KEY is required'
)

local openrouter = OpenRouter.new(api_key)

--
-- Planner prompt.
--

local prompt = [[
You are a Lua CodeMode planner for a UTCP agent.

Your job is to generate ONE SMALL, DETERMINISTIC Lua program that
will be executed directly by the UTCP CodeMode runtime.

The user wants to refactor README.md.

============================================================
OUTPUT FORMAT
============================================================

Return ONLY executable Lua source code.

DO NOT return:
- Markdown
- ``` fences
- explanations
- comments outside the generated Lua program
- JSON
- prose

The generated program must terminate.

The generated program must use:

    codemode.call_tool(name, args)

for every UTCP tool invocation.

============================================================
CRITICAL: CANONICAL UTCP TOOL NAMES
============================================================

The supplied UTCP catalog is AUTHORITATIVE.

Use the exact tool names from the supplied catalog.

Filesystem operations are exposed as canonical UTCP tools.

The canonical filesystem tools include:

    filesystem.read
    filesystem.write
    filesystem.patch

These are REAL UTCP tool names.

They are NOT nested operations.

They MUST be passed directly as the first argument to
codemode.call_tool.

CORRECT:

    local read_result = codemode.call_tool("filesystem.read", {
      path = "README.md"
    })

CORRECT:

    local patch_result = codemode.call_tool("filesystem.patch", {
      patch = patch
    })

CORRECT:

    local write_result = codemode.call_tool("filesystem.write", {
      path = "new-file.txt",
      content = content
    })

WRONG:

    codemode.call_tool("filesystem", {
      tool = "filesystem.read",
      inputs = {
        path = "README.md"
      }
    })

WRONG:

    codemode.call_tool("read", {
      path = "README.md"
    })

WRONG:

    codemode.call_tool("write", {
      path = "README.md",
      content = content
    })

WRONG:

    codemode.call_tool("patch", {
      patch = patch
    })

Never invent a generic "filesystem" wrapper.

Never shorten canonical tool names.

Never remove the "filesystem." prefix.

============================================================
CANONICAL FILESYSTEM TOOLS
============================================================

The supplied catalog defines the filesystem tools.

Use only names that actually occur in the canonical catalog.

Known filesystem tools include:

    filesystem.read
    filesystem.write

If filesystem.patch is present in the supplied catalog, it may
be used for modifying an existing file.

Do NOT assume tools exist merely because they are mentioned in
this prompt.

The supplied canonical catalog is authoritative.

============================================================
FILESYSTEM READ
============================================================

filesystem.read has this input:

    {
      path = string
    }

For README.md:

    local read_result = codemode.call_tool("filesystem.read", {
      path = "README.md"
    })

Use the actual returned value from the tool.

Do not invent result fields.

Inspect the actual result structure before assuming a field name.

The README content must come from the actual filesystem.read
result.

============================================================
FILESYSTEM PATCH
============================================================

filesystem.patch accepts:

    {
      patch = string
    }

The patch must be a real unified diff.

Example:

    --- a/README.md
    +++ b/README.md
    @@
    -old text
    +new text

filesystem.patch is preferred for modifying an existing README.

Use:

    codemode.call_tool("filesystem.patch", {
      patch = patch
    })

Do NOT call:

    codemode.call_tool("filesystem", ...)
    codemode.call_tool("patch", ...)

============================================================
FILESYSTEM WRITE
============================================================

filesystem.write accepts:

    {
      path = string,
      content = string
    }

filesystem.write is intended for creating a new file.

README.md already exists.

Therefore:

NEVER use filesystem.write to modify README.md.

For this task use:

    filesystem.read

followed by:

    filesystem.patch

============================================================
TASK
============================================================

Refactor README.md.

The workflow MUST be:

1. Read README.md using:

       codemode.call_tool("filesystem.read", {
         path = "README.md"
       })

2. Obtain the ACTUAL README content from the result.

3. Analyze the actual README content.

4. Improve the README while preserving its existing
   project-specific information.

5. Generate a unified diff based on the actual README content.

6. Apply the modification using:

       codemode.call_tool("filesystem.patch", {
         patch = patch
       })

7. Return:

       return {
         read = read_result,
         patch = patch_result
       }

============================================================
CRITICAL DATA FLOW
============================================================

The generated program MUST establish this dependency:

    filesystem.read
          ↓
    actual README content
          ↓
    README analysis
          ↓
    generated unified diff
          ↓
    filesystem.patch

The patch MUST be derived from the actual result of
filesystem.read.

DO NOT hard-code a replacement README.

DO NOT create a generic README.

DO NOT create a new README from scratch.

DO NOT call filesystem.patch before filesystem.read.

DO NOT call filesystem.write.

DO NOT call filesystem.replace unless that tool actually exists
in the supplied canonical catalog and the generated program has
an exact old text block from the read result.

DO NOT call filesystem.insert unless that tool actually exists
in the supplied canonical catalog and the generated program has
an exact anchor from the read result.

============================================================
README REFACTORING RULES
============================================================

Preserve useful project-specific information.

Improve:

- structure
- organization
- headings
- readability
- clarity
- installation instructions when already present
- usage examples when already supported
- existing explanations
- consistency

You MAY reorganize existing information.

You MAY improve wording.

You MAY remove obvious duplication.

You MAY fix obvious inconsistencies when they are supported
by the existing README.

You MUST NOT invent:

- project features
- APIs
- commands
- dependencies
- installation steps
- configuration
- environment variables
- transports
- examples
- benchmarks
- performance claims
- URLs
- version numbers
- tool names
- tool arguments
- output fields

If information is not present in the README and is not explicitly
provided by the canonical tool catalog, do not add it.

============================================================
PATCH REQUIREMENTS
============================================================

The generated patch must be a valid unified diff.

It must modify ONLY:

    README.md

It must NOT modify:

- source files
- tests
- provider files
- configuration files
- git files
- any other file

The patch should contain enough context for the filesystem.patch
tool to apply it safely.

Do not produce a patch for a file other than README.md.

============================================================
TOOL USAGE RULES
============================================================

Use ONLY canonical UTCP tool names from the supplied catalog.

For filesystem operations, use the exact canonical names:

    filesystem.read
    filesystem.write
    filesystem.patch

Never call:

    codemode.call_tool("filesystem", ...)

Never call:

    codemode.call_tool("read", ...)
    codemode.call_tool("write", ...)
    codemode.call_tool("patch", ...)

Never invent a different wrapper.

Never call an unknown UTCP tool.

============================================================
NO UNNECESSARY OPERATIONS
============================================================

Only perform the operations necessary to complete the task.

Expected tool sequence:

    filesystem.read
          ↓
    filesystem.patch

Do not:

- list the workspace
- grep the workspace
- stat README.md
- check git status
- run shell commands
- commit changes
- inspect unrelated files

README.md is already a known path.

============================================================
NO SHELL
============================================================

Do NOT use shell.

Do NOT use os.execute.

Do NOT use io.popen.

Do NOT invoke git.

Do NOT invoke external commands.

Use only:

    codemode.call_tool

============================================================
NO HALLUCINATION
============================================================

Never assume that a tool exists.

Never assume an input field exists.

Never assume a result field exists.

Use only the schemas supplied in the canonical tool catalog.

The canonical catalog is authoritative.

============================================================
TERMINATION
============================================================

The generated Lua program must terminate after:

1. reading README.md
2. creating a refactoring patch from the actual content
3. applying the patch
4. returning the results

Do not create loops that repeatedly call tools.

Do not retry indefinitely.

Do not wait for external input.

Do not create recursive calls.

============================================================
EXPECTED PROGRAM SHAPE
============================================================

The generated program should conceptually look like:

    local read_result = codemode.call_tool("filesystem.read", {
      path = "README.md"
    })

    -- Obtain and analyze the actual README content.

    local patch = "..."

    local patch_result = codemode.call_tool("filesystem.patch", {
      patch = patch
    })

    return {
      read = read_result,
      patch = patch_result
    }

This is a SHAPE example only.

The actual patch MUST be based on the actual README content
returned by filesystem.read.

============================================================
FINAL VALIDATION BEFORE RETURNING CODE
============================================================

Before returning the Lua source, verify mentally that:

1. Every codemode.call_tool call uses a canonical UTCP tool name.
2. Filesystem calls use "filesystem.read" or another exact
   canonical filesystem tool name.
3. No generic "filesystem" wrapper is used.
4. No shortened "read", "write", or "patch" name is used.
5. README.md is read first.
6. The patch is derived from the actual README content.
7. filesystem.write is NOT used.
8. filesystem.patch is used for the existing README.
9. Only README.md is modified.
10. No shell or git is used.
11. No invented result fields are used.
12. The program terminates.
13. The program returns read and patch results.

============================================================
CANONICAL UTCP TOOL CATALOG
============================================================

]] .. utcp.json.encode(tool_catalog)

--
-- Request Lua from OpenRouter.
--

print('--- requesting Lua from OpenRouter ---')

local status, response = openrouter:create_chat_completion({
  {
    role = 'system',
    content = [[
Generate small, deterministic Lua CodeMode programs for UTCP.

Use ONLY the canonical tools and schemas supplied by the user.

Never hallucinate tools, arguments, or result fields.

The canonical filesystem tools are named exactly:

    filesystem.read
    filesystem.write
    filesystem.patch

when those tools are present in the supplied catalog.

Use the canonical tool name directly as the first argument to
codemode.call_tool.

Example:

    local read_result = codemode.call_tool("filesystem.read", {
      path = "README.md"
    })

Example:

    local patch_result = codemode.call_tool("filesystem.patch", {
      patch = patch
    })

Never use a generic "filesystem" wrapper.

Never call:

    codemode.call_tool("read", ...)
    codemode.call_tool("write", ...)
    codemode.call_tool("patch", ...)

Never call:

    codemode.call_tool("filesystem", {
      tool = "filesystem.read",
      inputs = ...
    })

The generated program must:

1. call the canonical "filesystem.read" tool;
2. use its actual result;
3. derive a unified diff from the actual README content;
4. call the canonical "filesystem.patch" tool;
5. terminate.

Only use tools that actually appear in the supplied canonical
catalog.
]]
  },
  {
    role = 'user',
    content = prompt
  }
}, {
  model = os.getenv('OPENROUTER_MODEL')
    or 'stealth/ox-alpha',

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

local smoke_execution, smoke_err =
  codemode:call_tool_chain(
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
-- Direct canonical filesystem.read test.
--
-- This intentionally verifies that the canonical UTCP registry
-- contains and resolves "filesystem.read".
--

print('--- canonical filesystem.read test ---')

local read_test_source = [[
local result = codemode.call_tool("filesystem.read", {
  path = "README.md"
})

return {
  read = result
}
]]

print('calling filesystem.read...')

local read_execution, read_err =
  codemode:call_tool_chain(
    read_test_source,
    {
      instruction_limit = 10000,
    }
  )

assert(
  read_execution,
  read_err and read_err.error or
    'filesystem.read CodeMode test failed'
)

print(
  'filesystem.read result:',
  utcp.json.encode(read_execution.result)
)

--
-- Execute OpenRouter-generated CodeMode.
--

print('--- execution ---')
print('calling generated CodeMode...')
print('')

local execution, exec_err =
  codemode:call_tool_chain(
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