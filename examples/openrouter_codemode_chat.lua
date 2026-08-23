package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Requires lua-openai and a running local UTCP HTTP example server.
--   luarocks install lua-openai
--   export OPENROUTER_API_KEY=sk-or-...
--   make server-http

local utcp = require('utcp')
local OpenRouter = require('openai.compat.openrouter')

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
  }
end

local router = OpenRouter.new(assert(os.getenv('OPENROUTER_API_KEY'),
  'OPENROUTER_API_KEY is required'))

local chat = router:new_chat_session({
  model = os.getenv('OPENROUTER_MODEL') or 'openai/gpt-5.4',
  temperature = 0,
  messages = {
    {
      role = 'system',
      content = [[
You are a Lua UTCP CodeMode planner.
For every request, answer with ONLY a Lua program.
The program may call only codemode.call_tool(name, args).
Never invent tool names or call HTTP directly.
Available tools:
]] .. utcp.json.encode(catalog),
    }
  }
})

local source = chat:send([[Create a Lua program that:
1. calls calculator.add with 7 and 8;
2. passes that result to calculator.multiply with 4;
3. returns {sum = ..., product = ...}.]])

assert(type(source) == 'string', 'OpenRouter did not return Lua source')
source = source:gsub('^%s*```lua%s*', ''):gsub('^%s*```%s*', ''):gsub('%s*```%s*$', '')

print('generated:')
print(source)

local execution, exec_err = codemode:call_tool_chain(source, {
  instruction_limit = 100000,
})
assert(execution, exec_err and exec_err.error)
print('result:', utcp.json.encode(execution.result))
