package.path = './lua/?.lua;./lua/?/init.lua;'..package.path
local utcp = require('utcp')
local client = utcp.new({})
local provider = {name='example', transport='http', url='http://127.0.0.1:8080'}
client:add_provider(provider)
client:add_manual({tools={{name='echo',description='Echo',inputs={type='object'},tool_call_template={call_template_type='http',url='http://127.0.0.1:8080/echo',http_method='POST'}}}}, provider)
local tool, p = client:find_tool('echo')
assert(tool and tool.name == 'echo')
assert(p == provider)
local qualified, qualified_provider = client:find_tool('example.echo')
assert(qualified and qualified.name == 'echo')
assert(qualified_provider == provider)
local missing, err = client:find_tool('missing')
assert(missing == nil and type(err) == 'string')

local before = client.registry:all()
client:add_manual({tools={{name='alpha',tool_call_template={call_template_type='text',path='unused'}}}}, provider)
local after = client.registry:all()
assert(before ~= after, 'adding a tool must invalidate the ordered registry cache')
assert(after[1].tool.name == 'alpha' and after[2].tool.name == 'echo')

local transports = require('utcp.transports')
local original_mcp_new = transports.mcp.new
local constructions = 0
transports.mcp.new = function()
  constructions = constructions + 1
  return {call_tool=function(_, name, args) return {name=name,args=args} end}
end
local mcp_provider = {name='stateful',provider_type='mcp',url='http://unused',tools={{name='ping',tool_call_template={call_template_type='mcp',name='ping'}}}}
local mcp_client = utcp.new({providers={mcp_provider}})
assert(mcp_client:call_tool('ping', {n=1}).args.n == 1)
assert(mcp_client:call_tool('ping', {n=2}).args.n == 2)
assert(constructions == 1, 'MCP calls must reuse the provider transport/session')
transports.mcp.new = original_mcp_new

local original_text_new = transports.text.new
local text_constructions = 0
transports.text.new = function()
  text_constructions = text_constructions + 1
  return {call=function(_, _, args) return args end}
end
local cached_client = utcp.new({})
cached_client:add_manual({tools={{name='cached',tool_call_template={call_template_type='text',path='unused'}}}})
assert(cached_client:call_tool('cached', {n=1}).n == 1)
assert(cached_client:call_tool('cached', {n=2}).n == 2)
assert(text_constructions == 1, 'non-MCP tools must reuse their transport instance')
cached_client:add_manual({tools={{name='cached',tool_call_template={call_template_type='text',path='replacement'}}}})
assert(cached_client:call_tool('cached', {n=3}).n == 3)
assert(text_constructions == 2, 'replacing a tool must invalidate its cached transport')
transports.text.new = original_text_new
print('lua-utcp client lookup tests: ok')
