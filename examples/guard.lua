package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local utcp = require('utcp')

-- This CLI prompt is for the example only. A production application should
-- replace it with its authenticated authorization workflow (for example, a
-- privileged approval screen that verifies the approver's identity).
local function request_payment_approval(call, review)
  io.write(('Human approval required for %s.\n'):format(call.tool_name))
  io.write(('Reason: %s\n'):format(review.reason or 'No reason provided'))
  io.write('An authorized approver must type ALLOW to continue: ')

  local response = io.read('*l')
  if response == 'ALLOW' then
    return {decision = 'allow'}
  end

  return {decision = 'deny', reason = 'payment was not approved'}
end

local client = utcp.new({
  guard = {
    -- These local reads are explicitly safe and do not require evaluation.
    bypass_tools = {'read_profile', 'get_account_summary'},
    evaluate = function(_, call)
      if call.tool_name == 'delete_account' then
        return {decision = 'deny', reason = 'account deletion is not permitted'}
      end

      if call.tool_name == 'send_payment' then
        return {decision = 'review', reason = 'payment needs human approval'}
      end

      return {decision = 'deny', reason = 'tool is not approved'}
    end,
    approve = function(_, call, review)
      assert(call.tool_name == 'send_payment')
      assert(review.decision == 'review')
      return request_payment_approval(call, review)
    end,
  },
})

client:add_manual({
  tools = {
    {
      name = 'read_profile',
      description = 'Read a profile from a local fixture',
      tool_call_template = {
        call_template_type = 'text',
        path = 'examples/tool-result.json',
      },
    },
    {
      name = 'delete_account',
      description = 'Delete an account',
      tool_call_template = {
        call_template_type = 'text',
        path = 'examples/tool-result.json',
      },
    },
    {
      name = 'get_account_summary',
      description = 'Read an account summary',
      tool_call_template = {
        call_template_type = 'text',
        path = 'examples/tool-result.json',
      },
    },
    {
      name = 'send_payment',
      description = 'Send a payment',
      tool_call_template = {
        call_template_type = 'text',
        path = 'examples/tool-result.json',
      },
    },
  },
})

-- This call dispatches even though the Guard's default decision is deny.
local profile, profile_err = client:call_tool('read_profile', {})
assert(profile, profile_err)
print('bypassed:', profile.message)

-- This guarded-client tool is on bypass_tools, so it returns without evaluation.
local summary, summary_err = client:call_tool('get_account_summary', {})
assert(summary, summary_err)
print('bypassed result:', summary.message)

-- The Guard returns review, approval returns allow, then the tool dispatches.
local payment, payment_err = client:call_tool('send_payment', {})
assert(payment, payment_err)
print('approved result:', payment.message)

for _,tool_name in ipairs({'delete_account'}) do
  local result, err = client:call_tool(tool_name, {})
  assert(result == nil and utcp.errors.is(err), 'expected a structured Guard error')
  print(tool_name .. ':', err.kind, err.message)
end
