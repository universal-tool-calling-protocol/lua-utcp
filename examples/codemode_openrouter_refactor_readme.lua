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
--   validate generated CodeMode
--       ↓
--   CodeMode
--       ↓
--   canonical filesystem.read
--       ↓
--   generate README replacement
--       ↓
--   construct deterministic unified diff
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

local function validate_generated_code(source)
  assert(
    type(source) == 'string' and source ~= '',
    'generated CodeMode is empty'
  )

  local function tool_pattern(tool_name)
    local escaped_name = tool_name:gsub('%.', '%%.')

    return 'codemode%.call_tool%s*%(%s*["\']'
      .. escaped_name
      .. '["\']'
  end

  local function count_tool_calls(tool_name)
    local count = 0
    local position = 1
    local pattern = tool_pattern(tool_name)

    while true do
      local start, finish = source:find(pattern, position)

      if not start then
        break
      end

      count = count + 1
      position = finish + 1
    end

    return count
  end

  local function find_tool_call(tool_name)
    return source:find(tool_pattern(tool_name), 1)
  end

  local read_count = count_tool_calls('filesystem.read')
  local patch_count = count_tool_calls('filesystem.patch')

  assert(
    read_count == 1,
    'generated CodeMode must contain exactly one filesystem.read call, got '
      .. tostring(read_count)
  )

  assert(
    patch_count >= 1,
    'generated CodeMode must contain at least one filesystem.patch call'
  )

  local read_position = find_tool_call('filesystem.read')
  local patch_position = find_tool_call('filesystem.patch')

  assert(
    read_position ~= nil,
    'filesystem.read call not found'
  )

  assert(
    patch_position ~= nil,
    'filesystem.patch call not found'
  )

  assert(
    read_position < patch_position,
    'filesystem.patch must occur after filesystem.read'
  )

  -- Reject direct filesystem access.
  assert(
    not source:find('os%.execute'),
    'generated CodeMode must not use os.execute'
  )

  assert(
    not source:find('io%.popen'),
    'generated CodeMode must not use io.popen'
  )

  assert(
    not source:find('require%s*%('),
    'generated CodeMode must not use require'
  )

  -- Reject non-canonical tool names.
  assert(
    not source:find(
      'codemode%.call_tool%s*%(%s*["\']read["\']'
    ),
    'generated CodeMode must use canonical tool name filesystem.read'
  )

  assert(
    not source:find(
      'codemode%.call_tool%s*%(%s*["\']patch["\']'
    ),
    'generated CodeMode must use canonical tool name filesystem.patch'
  )

  return true
end

local client = utcp.Client.new()

local provider = load_provider('examples/provider.json')
assert(client:add_provider(provider))

local codemode = utcp.codemode.new(client)

local tools = assert_ok(
  codemode:list_tools(),
  'failed to list UTCP tools'
)

assert(
  #tools > 0,
  'provider returned no tools'
)

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

local catalog_json = assert(
  utcp.json.encode(catalog)
)

local system_prompt = [=[
You generate a deterministic Lua program for lua-utcp CodeMode.

Return ONLY executable Lua source code.
Do not use Markdown fences.

The generated program MUST execute this workflow:

    filesystem.read
        ↓
    extract README content
        ↓
    generate replacement README content
        ↓
    construct patch
        ↓
    filesystem.patch
        ↓
    return patch_result

The program MUST contain exactly ONE filesystem.read call:

  local read_result = codemode.call_tool(
    "filesystem.read",
    { path = "README.md" }
  )

The program MUST contain a filesystem.patch call AFTER filesystem.read:

  local patch_result = codemode.call_tool(
    "filesystem.patch",
    { patch = patch }
  )

IMPORTANT:

The value returned by filesystem.read MUST participate in generating
the replacement README.

The generated README MUST be based on the actual README returned by
filesystem.read.

Do NOT invent project-specific facts.

Do NOT replace the README with a generic placeholder README.

Do NOT guess the project type.

Do NOT invent:

  - features
  - APIs
  - commands
  - dependencies
  - URLs
  - versions
  - benchmarks
  - architecture claims
  - project capabilities

Do NOT implement a generic diff algorithm.

Do NOT manually calculate unified diff hunk line counts.

Instead, generate the complete replacement README content and construct
a valid unified diff from the actual original README and replacement.

The generated program should conceptually follow this structure:

  local read_result = codemode.call_tool(
    "filesystem.read",
    { path = "README.md" }
  )

  local original_content = read_result

  -- extract the actual README content from original_content

  local replacement = [[
  ...
  ]]

  -- construct a valid unified diff from original_content
  -- and replacement

  local patch_result = codemode.call_tool(
    "filesystem.patch",
    { patch = patch }
  )

  return patch_result

The replacement README MUST:

1. Preserve all factual information from the original README.

2. Improve structure, clarity, and readability.

3. Remove placeholder text only when the original README clearly
   identifies it as placeholder text.

4. Never introduce unsupported technical details.

5. Keep the project name and existing factual information.

6. Avoid inventing installation commands.

7. Avoid inventing usage commands.

8. Avoid inventing dependencies.

9. Avoid inventing licenses.

10. Avoid inventing URLs.

The patch MUST be a valid unified diff.

The generated program is responsible for constructing the diff.

The generated program MUST NOT call filesystem.read more than once.

The generated program MUST NOT call filesystem.write.

The generated program MUST NOT call any tool other than:

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

The model never gets direct filesystem access.

All filesystem operations MUST go through:

  codemode.call_tool(name, args)

The generated program must terminate and return a Lua value.

Canonical tool catalog:
]=] .. catalog_json

print('--- OpenRouter model ---')
print(model)
print('------------------------')

local status, response = openrouter:create_chat_completion({
  {
    role = 'system',
    content = system_prompt,
  },
  {
    role = 'user',
    content = [[
Refactor README.md using the workflow described above.

The final README must be based exclusively on the actual README content
returned by filesystem.read.
]],
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

print('')
print('--- generated README refactor CodeMode ---')
print(source)
print('------------------------------------------')
print('')

print('--- validating generated CodeMode ---')

local valid, validation_error = pcall(
  validate_generated_code,
  source
)

assert(
  valid,
  'generated CodeMode validation failed: '
    .. tostring(validation_error)
)

print('CodeMode validation: OK')
print('')

print('--- executing CodeMode ---')

local execution, execution_error = codemode:call_tool_chain(
  source,
  {
    instruction_limit = 30000,
  }
)

if not execution then
  print('--- CodeMode execution error ---')
  print(utcp.json.encode(execution_error))
  print('--------------------------------')

  error(
    'CodeMode execution failed: '
      .. tostring(utcp.json.encode(execution_error))
  )
end

print('CodeMode execution: OK')
print('')

print('--- filesystem.patch result ---')

if execution.result ~= nil then
  print(utcp.json.encode(execution.result))
else
  print('null')
end

print('--------------------------------')

print('CodeMode README refactor: ok')