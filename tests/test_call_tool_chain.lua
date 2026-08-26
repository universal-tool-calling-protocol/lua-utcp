package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local Client = require('utcp.client')

local function assert_equal(actual, expected, message)
  assert(actual == expected, message or ('expected ' .. tostring(expected) .. ', got ' .. tostring(actual)))
end

local function new_client(calls)
  local client = Client.new()
  function client:call_tool(name, args)
    calls[#calls + 1] = { name = name, args = args }
    if name == 'read' then
      return { text = 'hello' }
    elseif name == 'transform' then
      return { text = args.content .. ' world' }
    elseif name == 'write' then
      return { written = args.content }
    elseif name == 'fail' then
      return nil, 'boom'
    elseif name == 'rollback' then
      return { rolled_back = args.name }
    end
    return nil, 'unknown test tool: ' .. tostring(name)
  end
  return client
end

-- Sequential execution passes the previous output into the next step.
do
  local calls = {}
  local client = new_client(calls)
  local result, err = client:call_tool_chain({
    { name = 'read', tool = 'read', arguments = {} },
    {
      name = 'transform',
      tool = 'transform',
      arguments = function(state)
        return { content = state.previous.output.text }
      end,
    },
    {
      name = 'write',
      tool = 'write',
      arguments = function(state)
        return { content = state.steps.transform.output.text }
      end,
    },
  })

  assert(not err, err)
  assert(result.ok)
  assert_equal(#result.steps, 3)
  assert_equal(result.output.written, 'hello world')
  assert_equal(calls[2].args.content, 'hello')
  assert_equal(calls[3].args.content, 'hello world')
end

-- A failed step stops the chain by default and records structured state.
do
  local calls = {}
  local client = new_client(calls)
  local result, err = client:call_tool_chain({
    { name = 'read', tool = 'read', arguments = {} },
    { name = 'fail', tool = 'fail', arguments = {} },
    { name = 'write', tool = 'write', arguments = {} },
  })

  assert(result == nil)
  assert(err)
  assert_equal(err.failed_step, 2)
  assert_equal(err.error, 'boom')
  assert_equal(#err.steps, 2)
  assert_equal(#calls, 2)
end

-- on_error=continue keeps executing while returning an unsuccessful result.
do
  local calls = {}
  local client = new_client(calls)
  local result, err = client:call_tool_chain({
    on_error = 'continue',
    { name = 'fail', tool = 'fail', arguments = {} },
    { name = 'write', tool = 'write', arguments = { content = 'after failure' } },
  })

  assert(not err, err)
  assert(not result.ok)
  assert_equal(result.failed_step, 1)
  assert_equal(#result.steps, 2)
  assert_equal(result.output.written, 'after failure')
end

-- rollback=true runs declared rollback tools in reverse order after failure.
do
  local calls = {}
  local client = new_client(calls)
  local result, err = client:call_tool_chain({
    rollback = true,
    { name = 'first', tool = 'read', arguments = {}, rollback = {
      tool = 'rollback',
      arguments = { name = 'first' },
    } },
    { name = 'second', tool = 'transform', arguments = { content = 'x' }, rollback = {
      tool = 'rollback',
      arguments = function(state)
        return { name = state.current.name }
      end,
    } },
    { name = 'fail', tool = 'fail', arguments = {} },
  })

  assert(result == nil)
  assert(err)
  assert_equal(#err.rollbacks, 2)
  assert_equal(err.rollbacks[1].step, 'second')
  assert_equal(err.rollbacks[2].step, 'first')
  assert_equal(calls[4].args.name, 'second')
  assert_equal(calls[5].args.name, 'first')
end

print('call_tool_chain tests passed')
