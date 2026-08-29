local errors = require('utcp.errors')

local M = {}

local function guard_error(kind, message, call, verdict)
  return errors.new(kind, message, {
    tool_name = call.tool_name,
    args = call.args,
    verdict = verdict,
  })
end

local function evaluator_for(guard)
  if type(guard) == 'function' then
    return function(call)
      return guard(call)
    end
  end

  if type(guard) == 'table' and type(guard.evaluate) == 'function' then
    return function(call)
      return guard:evaluate(call)
    end
  end

  return nil
end

local function approver_for(guard)
  if type(guard) == 'table' and type(guard.approve) == 'function' then
    return function(call, review)
      return guard:approve(call, review)
    end
  end

  return nil
end

local function bypasses(guard, call)
  if type(guard) ~= 'table' or guard.bypass_tools == nil then
    return false
  end

  if type(guard.bypass_tools) ~= 'table' then
    return nil, 'UTCP guard bypass_tools must be a table'
  end

  if guard.bypass_tools[call.tool_name] == true then
    return true
  end

  for _,tool_name in ipairs(guard.bypass_tools) do
    if tool_name == call.tool_name then
      return true
    end
  end

  return false
end

-- Evaluate a client-side tool-call guard. A guard may be a function or a table
-- with an evaluate(call) method. It must return one of the documented verdicts:
--
--   "allow" | { decision = "allow" }
--   "deny"  | { decision = "deny", reason = "..." }
--   "review"| { decision = "review", reason = "..." }
--   "error" | { decision = "error", reason = "..." }
--
-- A review is blocked unless guard.approve(call, review_verdict) returns an
-- "allow" verdict. Invalid results and callback failures fail closed as guard
-- errors.
function M.evaluate(guard, call)
  if guard == nil then
    return true
  end

  local bypass, bypass_err = bypasses(guard, call)
  if bypass_err then
    return nil, guard_error('guard_error', bypass_err, call)
  end
  if bypass then
    return true
  end

  local evaluate = evaluator_for(guard)
  if not evaluate then
    return nil, guard_error(
      'guard_error',
      'UTCP guard must be a function or expose evaluate(call)',
      call
    )
  end

  local ok, verdict = pcall(evaluate, call)
  if not ok then
    return nil, guard_error(
      'guard_error',
      'UTCP guard evaluation failed: ' .. tostring(verdict),
      call
    )
  end

  local decision = type(verdict) == 'table' and verdict.decision or verdict
  local reason = type(verdict) == 'table' and verdict.reason or nil

  if decision == 'allow' then
    return true
  end

  if decision == 'deny' then
    return nil, guard_error(
      'guard_denied',
      reason or 'tool call denied by guard',
      call,
      verdict
    )
  end

  if decision == 'review' then
    local approve = approver_for(guard)
    if not approve then
      return nil, guard_error(
        'guard_review_required',
        reason or 'tool call requires guard review',
        call,
        verdict
      )
    end

    local approved, approval = pcall(approve, call, verdict)
    if not approved then
      return nil, guard_error(
        'guard_error',
        'UTCP guard approval failed: ' .. tostring(approval),
        call,
        verdict
      )
    end

    local approval_decision = type(approval) == 'table' and approval.decision or approval
    local approval_reason = type(approval) == 'table' and approval.reason or nil
    if approval_decision == 'allow' then
      return true
    end

    if approval_decision == 'deny' then
      return nil, guard_error(
        'guard_denied',
        approval_reason or reason or 'tool call denied during guard approval',
        call,
        approval
      )
    end

    if approval_decision == 'review' then
      return nil, guard_error(
        'guard_review_required',
        approval_reason or reason or 'tool call still requires guard review',
        call,
        approval
      )
    end

    if approval_decision == 'error' then
      return nil, guard_error(
        'guard_error',
        approval_reason or 'guard approval could not evaluate tool call',
        call,
        approval
      )
    end

    return nil, guard_error(
      'guard_error',
      'UTCP guard approval returned an invalid decision: ' .. tostring(approval_decision),
      call,
      approval
    )
  end

  if decision == 'error' then
    return nil, guard_error(
      'guard_error',
      reason or 'guard could not evaluate tool call',
      call,
      verdict
    )
  end

  return nil, guard_error(
    'guard_error',
    'UTCP guard returned an invalid decision: ' .. tostring(decision),
    call,
    verdict
  )
end

return M
