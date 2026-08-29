package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local utcp = require('utcp')

local command = os.getenv('HOL_GUARD_EXAMPLE_COMMAND') or 'git status --short'
local executable = os.getenv('HOL_GUARD_BIN') or 'hol-guard'

local function request_approval(call, review)
  io.write(('HOL Guard review required for: %s\n'):format(call.args.command))
  io.write(('Reason: %s\n'):format(review.reason or 'No reason provided'))
  io.write('Type ALLOW to run this command: ')

  if io.read('*l') == 'ALLOW' then
    return {decision = 'allow'}
  end

  return {decision = 'deny', reason = 'command was not approved'}
end

local client = utcp.new({
  guard = utcp.guards.hol_guard.new({
    executable = executable,
    command_for = function(call)
      if call.tool_name == 'shell' then
        return call.args.command
      end
    end,
    -- This example exposes only a shell tool. Other calls are denied rather
    -- than silently skipping HOL Guard classification.
    unmapped_decision = 'deny',
    approve = request_approval,
  }),
})

client:add_manual({
  manual_version = '1.0',
  utcp_version = '1.0',
  tools = {
    {
      name = 'shell',
      description = 'Run a command after HOL Guard command-safety classification',
      inputs = {
        type = 'object',
        properties = {
          command = {type = 'string'},
        },
        required = {'command'},
      },
      tool_call_template = {
        call_template_type = 'cli',
        -- The CLI transport quotes UTCP arguments. Pass the classified command
        -- as sh's single -c argument instead of treating it as an executable
        -- path with embedded spaces.
        command = 'sh -c UTCP_ARG_command_UTCP_END',
        output_type = 'text',
      },
    },
  },
})

print('Classifying with HOL Guard:', command)
local result, err = client:call_tool('shell', {command = command})
if not result then
  io.stderr:write(('Command was not dispatched (%s): %s\n'):format(
    err.kind or 'error',
    err.message or tostring(err)
  ))
  os.exit(1)
end

print('Command output:')
print(result)
