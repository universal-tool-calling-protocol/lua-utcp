package.path = './lua/?.lua;./lua/?/init.lua;'..package.path
local utcp = require('utcp')
local errors = require('utcp.errors')
local client = utcp.new({})
local provider = {name='example', transport='http', url='http://127.0.0.1:8080',allowed_communication_protocols={'http','text'}}
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

local original_guard_transport_new = {
  http = transports.http.new,
  cli = transports.cli.new,
  mcp = transports.mcp.new,
}
local guard_transport_calls = {http=0,cli=0,mcp=0}
local guard_transport_constructions = {http=0,cli=0,mcp=0}
for _,typ in ipairs({'http','cli','mcp'}) do
  transports[typ].new = function()
    guard_transport_constructions[typ] = guard_transport_constructions[typ] + 1
    if typ == 'mcp' then
      return {
        call_tool = function(_, _, args)
          guard_transport_calls[typ] = guard_transport_calls[typ] + 1
          return {called=guard_transport_calls[typ],args=args}
        end,
      }
    end
    return {
      call = function(_, _, args)
        guard_transport_calls[typ] = guard_transport_calls[typ] + 1
        return {called=guard_transport_calls[typ],args=args}
      end,
    }
  end
end

local function guarded_client(verdict, tool_name, transport)
  local guarded = utcp.new({
    guard = {
      evaluate = function(_, call)
        assert(call.tool_name == tool_name)
        assert(call.args.value == 7)
        return verdict
      end,
    },
  })
  guarded:add_manual({tools={{name=tool_name,tool_call_template={call_template_type=transport}}}})
  return guarded
end

for _,case in ipairs({
  {verdict={decision='deny',reason='blocked by policy'},kind='guard_denied',tool='guarded_http',transport='http'},
  {verdict={decision='review',reason='approval required'},kind='guard_review_required',tool='guarded_cli',transport='cli'},
  {verdict={decision='error',reason='guard unavailable'},kind='guard_error',tool='guarded_mcp',transport='mcp'},
}) do
  local result, guard_err = guarded_client(case.verdict, case.tool, case.transport):call_tool(case.tool, {value=7})
  assert(result == nil)
  assert(errors.is(guard_err) and guard_err.kind == case.kind)
end
for _,typ in ipairs({'http','cli','mcp'}) do
  assert(guard_transport_constructions[typ] == 0, 'non-allow guard decisions must not construct a '..typ..' transport')
  assert(guard_transport_calls[typ] == 0, 'non-allow guard decisions must not dispatch a '..typ..' transport call')
end

local allowed_result, allowed_err = guarded_client({decision='allow'}, 'allowed_http', 'http'):call_tool('allowed_http', {value=7})
assert(allowed_result and allowed_result.called == 1, allowed_err)
assert(guard_transport_constructions.http == 1, 'an allowed call must construct the HTTP transport once')
assert(guard_transport_calls.http == 1, 'an allowed call must dispatch exactly once')

local bypass_evaluations = 0
local bypass_client = utcp.new({
  guard = {
    bypass_tools = {'bypass_http'},
    evaluate = function()
      bypass_evaluations = bypass_evaluations + 1
      return {decision='deny'}
    end,
  },
})
bypass_client:add_manual({tools={{name='bypass_http',tool_call_template={call_template_type='http'}}}})
local bypass_result, bypass_err = bypass_client:call_tool('bypass_http', {value=7})
assert(bypass_result and bypass_result.called == 2, bypass_err)
assert(bypass_evaluations == 0, 'bypassed tools must not evaluate the guard')
assert(guard_transport_calls.http == 2, 'a bypassed tool must dispatch exactly once')

local review_evaluations, approval_requests = 0, 0
local approved_review_client = utcp.new({
  guard = {
    evaluate = function()
      review_evaluations = review_evaluations + 1
      return {decision='review',reason='human approval required'}
    end,
    approve = function(_, call, review)
      approval_requests = approval_requests + 1
      assert(call.tool_name == 'approved_http')
      assert(review.decision == 'review')
      return {decision='allow'}
    end,
  },
})
approved_review_client:add_manual({tools={{name='approved_http',tool_call_template={call_template_type='http'}}}})
local approved_result, approved_err = approved_review_client:call_tool('approved_http', {value=7})
assert(approved_result and approved_result.called == 3, approved_err)
assert(review_evaluations == 1 and approval_requests == 1, 'review calls must request approval once')
assert(guard_transport_calls.http == 3, 'an approved review must dispatch exactly once')

local guard_failure_client = utcp.new({
  guard = function()
    error('evaluator crashed')
  end,
})
guard_failure_client:add_manual({tools={{name='failed_guard',tool_call_template={call_template_type='http'}}}})
local failed_result, failed_guard_err = guard_failure_client:call_tool('failed_guard', {value=7})
assert(failed_result == nil)
assert(errors.is(failed_guard_err) and failed_guard_err.kind == 'guard_error')
assert(guard_transport_calls.http == 3, 'a guard failure must not dispatch a transport call')
for typ,new in pairs(original_guard_transport_new) do
  transports[typ].new = new
end
print('lua-utcp client lookup tests: ok')
