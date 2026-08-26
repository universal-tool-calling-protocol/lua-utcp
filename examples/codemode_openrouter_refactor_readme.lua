package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Requires:
--   luarocks install lua-utcp
--   luarocks install lua-openai
--   export OPENROUTER_API_KEY=sk-or-...
--
-- This example demonstrates:
--
--   filesystem.read
--       ↓
--   extract actual README text
--       ↓
--   OpenRouter refactors that exact text
--       ↓
--   call_tool_chain
--       ├── diff.unified
--       └── filesystem.patch
--
-- The important property is that OpenRouter receives the ACTUAL README
-- returned by filesystem.read.
--
-- OpenRouter does not generate the filesystem operation.
-- OpenRouter only generates the replacement README.
--
-- The unified diff and filesystem mutation are executed by the
-- canonical UTCP tools through one call_tool_chain invocation.

local utcp = require('utcp')
local OpenRouter = require('openai.compat.openrouter')

local function assert_ok(value, message)
  assert(
    value ~= nil,
    message or 'operation failed'
  )

  return value
end

local function load_provider(path)
  local provider, err =
    utcp.load_provider(path)

  assert(
    provider,
    err
  )

  return provider
end

local function json_decode(value)
  if type(value) ~= 'string' then
    return nil
  end

  local ok, decoded =
    pcall(
      utcp.json.decode,
      value
    )

  if ok then
    return decoded
  end

  return nil
end

local function extract_readme_text(value, depth)
  depth = depth or 0

  --
  -- Protect against pathological nested responses.
  --

  if depth > 8 then
    return nil
  end

  --
  -- Plain string.
  --

  if type(value) == 'string' then
    --
    -- A provider may return the README directly.
    --

    local decoded = json_decode(value)

    if decoded ~= nil then
      local nested =
        extract_readme_text(
          decoded,
          depth + 1
        )

      if nested ~= nil then
        return nested
      end
    end

    --
    -- The string itself is the README.
    --

    return value
  end

  if type(value) ~= 'table' then
    return nil
  end

  --
  -- Most likely fields first.
  --

  local fields = {
    'content',
    'result',
    'data',
    'output',
    'text',
    'body',
  }

  for _, field in ipairs(fields) do
    if value[field] ~= nil then
      local text =
        extract_readme_text(
          value[field],
          depth + 1
        )

      if text ~= nil then
        return text
      end
    end
  end

  --
  -- Some providers wrap the response in:
  --
  --   { response = ... }
  --   { value = ... }
  --   { payload = ... }
  --

  local nested_fields = {
    'response',
    'value',
    'payload',
    'result',
  }

  for _, field in ipairs(nested_fields) do
    if value[field] ~= nil then
      local text =
        extract_readme_text(
          value[field],
          depth + 1
        )

      if text ~= nil then
        return text
      end
    end
  end

  return nil
end

local function extract_openrouter_content(response)
  local content =
    response
      and response.choices
      and response.choices[1]
      and response.choices[1].message
      and response.choices[1].message.content

  assert(
    type(content) == 'string',
    'OpenRouter returned no message content'
  )

  assert(
    content ~= '',
    'OpenRouter returned empty message content'
  )

  return content
end

local function strip_markdown_fence(source)
  source =
    source:gsub(
      '^%s*```markdown%s*',
      ''
    )

  source =
    source:gsub(
      '^%s*```md%s*',
      ''
    )

  source =
    source:gsub(
      '^%s*```%s*',
      ''
    )

  source =
    source:gsub(
      '%s*```%s*$',
      ''
    )

  return source
end

local function validate_replacement(
  original,
  replacement
)
  assert(
    type(original) == 'string',
    'original README must be a string'
  )

  assert(
    type(replacement) == 'string',
    'replacement README must be a string'
  )

  assert(
    replacement ~= '',
    'replacement README is empty'
  )

  --
  -- Do not allow the model to return a diff.
  --

  assert(
    not replacement:match(
      '^%s*diff%s+'
    ),
    'OpenRouter returned a diff instead of README content'
  )

  assert(
    not replacement:match(
      '^%s*```'
    ),
    'replacement README contains a Markdown fence'
  )

  --
  -- Preserve the project title when the original has one.
  --

  local first_line =
    original:match(
      '^[^\r\n]*'
    )

  local project_name =
    first_line
      and first_line:match(
        '^#%s+(.+)$'
      )

  if project_name and project_name ~= '' then
    assert(
      replacement:find(
        project_name,
        1,
        true
      ) ~= nil,
      'replacement README lost project name: '
        .. project_name
    )
  end

  return true
end

local function require_tool(
  catalog,
  name
)
  for _, tool in ipairs(catalog) do
    if tool.name == name then
      return tool
    end
  end

  error(
    'missing canonical tool: '
      .. name
  )
end

--
-- ============================================================
-- UTCP CLIENT
-- ============================================================
--

local client =
  utcp.Client.new()

local provider =
  load_provider(
    'examples/provider.json'
  )

assert(
  client:add_provider(provider)
)

--
-- Make sure the canonical tools exist.
--

local tools =
  assert_ok(
    client:list_tools(),
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
    inputs =
      tool.inputs
      or tool.input_schema,
    outputs =
      tool.outputs
      or tool.output_schema,
  }
end

require_tool(
  catalog,
  'filesystem.read'
)

require_tool(
  catalog,
  'diff.unified'
)

require_tool(
  catalog,
  'filesystem.patch'
)

--
-- ============================================================
-- OPENROUTER
-- ============================================================
--

local api_key =
  assert(
    os.getenv(
      'OPENROUTER_API_KEY'
    ),
    'OPENROUTER_API_KEY is required'
  )

local openrouter =
  OpenRouter.new(api_key)

local model =
  os.getenv(
    'OPENROUTER_MODEL'
  )
  or 'nvidia/nemotron-3.5-lightning:free'

print(
  '--- OpenRouter model ---'
)

print(model)

print(
  '------------------------'
)

--
-- ============================================================
-- STEP 1
-- filesystem.read
-- ============================================================
--

print('')
print(
  '--- filesystem.read ---'
)

local read_result, read_error =
  client:call_tool(
    'filesystem.read',
    {
      path = 'README.md',
    }
  )

if read_result == nil then
  error(
    'filesystem.read failed: '
      .. tostring(
        utcp.json.encode(
          read_error
        )
      )
  )
end

print(
  'raw filesystem.read result type: '
    .. type(read_result)
)

--
-- ============================================================
-- STEP 2
-- Extract actual README text
-- ============================================================
--

local original_content =
  extract_readme_text(
    read_result
  )

assert(
  type(original_content) == 'string',
  'filesystem.read result does not contain README text'
)

assert(
  original_content ~= '',
  'filesystem.read returned empty README'
)

print(
  'extracted README bytes: '
    .. tostring(
      #original_content
    )
)

print('')
print(
  '--- actual README text ---'
)

print(original_content)

print(
  '---------------------------'
)

--
-- ============================================================
-- STEP 3
-- OpenRouter refactors ACTUAL README
-- ============================================================
--

local system_prompt = [[
You are a technical README editor.

You will receive the complete actual README.md content.

Your task is to produce a cleaner, clearer, better structured version
of THAT README.

The supplied README is the only source of truth.

Return ONLY the complete replacement README.md.

Do not return:
- JSON
- a diff
- explanations
- commentary
- Markdown fences around the README

Preserve factual information from the source.

Preserve:
- project name
- existing URLs
- existing commands
- existing installation instructions
- existing usage instructions
- existing dependencies
- existing versions
- existing technical claims
- existing license information

Improve:
- structure
- heading hierarchy
- readability
- clarity
- organization
- concise wording
- duplication

Do not invent information.

Never invent:
- features
- APIs
- commands
- dependencies
- URLs
- versions
- benchmarks
- architecture
- installation commands
- usage commands
- configuration
- environment variables
- license information
- capabilities

Do not guess what the project does.

Do not add conventional boilerplate merely because it is common in
software READMEs.

Do not replace factual source material with generic placeholder text.

The result must be a complete README.md based exclusively on the
README supplied by the user.
]]

local user_prompt =
  [[
Refactor this exact README.md.

----- BEGIN ACTUAL README -----

]]
  .. original_content
  .. [[

----- END ACTUAL README -----

Return ONLY the complete refactored README.
]]

print('')
print(
  '--- OpenRouter README refactor ---'
)

local status, response =
  openrouter:create_chat_completion(
    {
      {
        role = 'system',
        content = system_prompt,
      },
      {
        role = 'user',
        content = user_prompt,
      },
    },
    {
      model = model,
      temperature = 0,
    }
  )

assert(
  status == 200,
  'OpenRouter request failed: HTTP '
    .. tostring(status)
)

local replacement =
  extract_openrouter_content(
    response
  )

replacement =
  strip_markdown_fence(
    replacement
  )

validate_replacement(
  original_content,
  replacement
)

print('')
print(
  '--- refactored README ---'
)

print(replacement)

print(
  '--------------------------'
)

--
-- ============================================================
-- STEP 4
-- diff.unified → filesystem.patch
-- ============================================================
--
-- One call_tool_chain replaces two separate call_tool calls.
--
-- $previous is resolved by Client:call_tool_chain() to the result
-- of the immediately preceding tool.
--
-- Therefore:
--
--   diff.unified
--          ↓
--       $previous
--          ↓
--   filesystem.patch
--

print('')
print(
  '--- diff.unified → filesystem.patch chain ---'
)

local chain_result, chain_error =
  client:call_tool_chain({
    {
      name = 'diff.unified',
      args = {
        original = original_content,
        replacement = replacement,
        path = 'README.md',
      },
    },

    {
      name = 'filesystem.patch',
      args = {
        patch = '$previous',
      },
    },
  })

if chain_result == nil then
  print(
    '--- call_tool_chain error ---'
  )

  print(
    utcp.json.encode(
      chain_error
    )
  )

  print(
    '-----------------------------'
  )

  error(
    'README refactor chain failed: '
      .. tostring(
        utcp.json.encode(
          chain_error
        )
      )
  )
end

--
-- The final chain result is the filesystem.patch result.
--

local patch_step =
  chain_result[
    #chain_result
  ]

assert(
  patch_step ~= nil,
  'call_tool_chain returned no final result'
)

print('')
print(
  '--- filesystem.patch result ---'
)

print(
  utcp.json.encode(
    patch_step.result
  )
)

print(
  '--------------------------------'
)

print('')
print(
  'README refactor: ok'
)