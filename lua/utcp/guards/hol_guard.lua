-- HOL Guard adapter for the lua-utcp client-side guard interface.
--
-- HOL Guard's `command test` command is deliberately side-effect free: it
-- classifies a command but neither executes it nor records an approval. This
-- adapter makes that classification available before UTCP dispatches a tool.

local json = require('utcp.json')

local M = {}
local Adapter = {}
Adapter.__index = Adapter

local supported_decisions = {
  allow = true,
  deny = true,
  review = true,
  error = true,
}

local function shellquote(value)
  value = tostring(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function trim(value)
  if type(value) ~= 'string' then
    return nil
  end

  return value:match('^%s*(.-)%s*$')
end

local function normalize(value)
  if type(value) ~= 'string' then
    return nil
  end

  return value:lower():gsub('[%s%-]+', '_')
end

local function reason_for(result, fallback)
  if type(result) ~= 'table' then
    return fallback
  end

  local classification = result.classification
  local classification_reason = type(classification) == 'table'
    and (classification.reason or classification.message)
    or nil

  return result.reason or result.message or result.summary
    or classification_reason or fallback
end

local function decision_from_value(value)
  value = normalize(value)

  if value == 'allow' or value == 'allowed' or value == 'safe' then
    return 'allow'
  end

  if value == 'deny' or value == 'denied' or value == 'block'
      or value == 'blocked' or value == 'unsafe' or value == 'dangerous' then
    return 'deny'
  end

  if value == 'review' or value == 'review_required'
      or value == 'require_review' or value == 'warn'
      or value == 'warning' or value == 'caution' then
    return 'review'
  end

  if value == 'error' or value == 'failed' or value == 'unavailable' then
    return 'error'
  end

  return nil
end

local function command_decision(result)
  -- HOL Guard 3.x reports a coarse status and a nested classification. A
  -- successful process exit only means that Guard classified the command; it
  -- is not itself an allow decision.
  local classification = result.classification
  local explicitly_benign = type(classification) == 'table'
    and classification.explicitly_benign == true

  local status_decision = decision_from_value(result.status)
  if status_decision then
    return status_decision
  end

  if explicitly_benign then
    return 'allow'
  end

  local minimum_action = decision_from_value(result.minimum_action)
  if minimum_action == 'deny' or minimum_action == 'review' then
    return minimum_action
  end

  -- A no-match result is only allowed when Guard marked the command as
  -- explicitly benign. Otherwise the classifier did not establish safety, so
  -- preserve the client's fail-closed posture with a review decision.
  if normalize(result.status) == 'no_match' then
    return 'review'
  end

  if minimum_action == 'allow' then
    return 'allow'
  end

  -- Support the flat output emitted by older HOL Guard versions.
  for _, key in ipairs({
    'decision', 'classification', 'action', 'verdict', 'result', 'risk',
    'risk_level',
  }) do
    local decision = decision_from_value(result[key])
    if decision then
      return decision
    end
  end

  if result.safe == true or result.is_safe == true or result.allowed == true then
    return 'allow'
  end

  if result.safe == false or result.is_safe == false or result.allowed == false then
    return 'deny'
  end

  return nil
end

local function default_run(argv)
  local quoted = {}
  for index, value in ipairs(argv) do
    quoted[index] = shellquote(value)
  end

  local pipe, pipe_err = io.popen(table.concat(quoted, ' ') .. ' 2>&1', 'r')
  if not pipe then
    return false, nil, pipe_err or 'failed to start hol-guard'
  end

  local output = pipe:read('*a')
  local ok, _, code = pipe:close()
  if not ok or (code and code ~= 0) then
    return false, output, 'hol-guard command test failed'
  end

  return true, output
end

local function command_for(self, call)
  if self.command_for then
    return self.command_for(call)
  end

  local args = call.args
  if type(args) == 'table' then
    return args[self.command_arg]
  end

  return nil
end

function Adapter:evaluate(call)
  local command = command_for(self, call)

  if command == nil or command == '' then
    return {
      decision = self.unmapped_decision,
      reason = self.unmapped_reason,
    }
  end

  if type(command) ~= 'string' then
    return {
      decision = 'error',
      reason = 'HOL Guard command input must be a string',
    }
  end

  local argv = {self.executable, 'command', 'test', command, '--json'}
  local ran, ok, output, run_err = pcall(self.run, argv, call)
  if not ran then
    return {
      decision = 'error',
      reason = 'HOL Guard runner failed: ' .. tostring(ok),
    }
  end

  if ok ~= true then
    return {
      decision = 'error',
      reason = trim(run_err) or trim(output) or 'HOL Guard command test failed',
    }
  end

  local result, decode_err = json.decode(output or '')
  if type(result) ~= 'table' then
    return {
      decision = 'error',
      reason = 'HOL Guard returned invalid JSON: ' .. tostring(decode_err or output),
    }
  end

  local decision = command_decision(result)
  if not decision then
    return {
      decision = 'error',
      reason = reason_for(result, 'HOL Guard returned an unknown command classification'),
      hol_guard = result,
    }
  end

  return {
    decision = decision,
    reason = reason_for(result),
    hol_guard = result,
  }
end

-- Construct a UTCP guard backed by `hol-guard command test <command> --json`.
--
-- Options:
--   executable          HOL Guard executable path (default: "hol-guard")
--   command_arg         argument holding the shell command (default: "command")
--   command_for(call)   custom command extractor; return nil when unmapped
--   unmapped_decision   allow | deny | review | error (default: error)
--   unmapped_reason     reason used when a call cannot be classified
--   approve(call, review) optional application-owned reviewer callback
--   run(argv, call)     test seam; return true, json_output or false, output, err
--
-- Calls without a command mapping fail closed by default. Set an explicit
-- unmapped_decision only when another control covers those non-shell tools.
function M.new(opts)
  opts = opts or {}

  assert(type(opts) == 'table', 'HOL Guard options must be a table')
  assert(
    opts.executable == nil or type(opts.executable) == 'string',
    'HOL Guard executable must be a string'
  )
  assert(
    opts.command_arg == nil or type(opts.command_arg) == 'string',
    'HOL Guard command_arg must be a string'
  )
  assert(
    opts.command_for == nil or type(opts.command_for) == 'function',
    'HOL Guard command_for must be a function'
  )
  assert(
    opts.run == nil or type(opts.run) == 'function',
    'HOL Guard run must be a function'
  )
  assert(
    opts.approve == nil or type(opts.approve) == 'function',
    'HOL Guard approve must be a function'
  )

  local unmapped_decision = opts.unmapped_decision or 'error'
  assert(
    supported_decisions[unmapped_decision],
    'HOL Guard unmapped_decision must be allow, deny, review, or error'
  )

  local self = setmetatable({
    executable = opts.executable or 'hol-guard',
    command_arg = opts.command_arg or 'command',
    command_for = opts.command_for,
    run = opts.run or default_run,
    unmapped_decision = unmapped_decision,
    unmapped_reason = opts.unmapped_reason
      or 'HOL Guard cannot classify this tool call; configure command_for or unmapped_decision',
  }, Adapter)

  if opts.approve then
    self.approve = function(_, call, review)
      return opts.approve(call, review)
    end
  end

  return self
end

M.Adapter = Adapter

return M
