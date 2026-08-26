local Chain = {}

local function resolve_arguments(arguments, state)
  if type(arguments) == 'function' then
    return arguments(state)
  end

  if arguments == nil then
    return {}
  end

  return arguments
end

local function normalize_error(step, err)
  if type(err) == 'table' then
    return err
  end

  return {
    step = step.name,
    tool = step.tool,
    error = tostring(err or 'tool call failed'),
  }
end

local function run_rollback(client, state, completed, errors)
  local rollbacks = {}

  for i = #completed, 1, -1 do
    local completed_step = completed[i]
    local rollback = completed_step.rollback

    if rollback then
      state.current = completed_step

      local rollback_tool = rollback.tool
      local rollback_arguments = rollback.arguments
      local ok, args_or_error = pcall(resolve_arguments, rollback_arguments, state)

      if not ok then
        rollbacks[#rollbacks + 1] = {
          step = completed_step.name,
          tool = rollback_tool,
          ok = false,
          error = tostring(args_or_error),
        }
      else
        local result, err = client:call_tool(rollback_tool, args_or_error or {})
        local rollback_result = {
          step = completed_step.name,
          tool = rollback_tool,
          ok = err == nil,
          output = result,
          error = err,
        }

        rollbacks[#rollbacks + 1] = rollback_result

        if err ~= nil then
          errors[#errors + 1] = {
            step = completed_step.name,
            tool = rollback_tool,
            error = err,
            rollback = true,
          }
        end
      end
    end
  end

  state.current = nil
  return rollbacks
end

function Chain.run(client, workflow)
  if type(workflow) ~= 'table' then
    return nil, 'call_tool_chain expects a workflow table'
  end

  local state = {
    ok = true,
    steps = {},
    errors = {},
    previous = nil,
    current = nil,
    output = nil,
  }

  local completed = {}
  local failed_step
  local failure_error

  for index, step in ipairs(workflow) do
    if type(step) ~= 'table' then
      return nil, {
        failed_step = index,
        error = 'workflow step must be a table',
        steps = state.steps,
      }
    end

    local tool = step.tool or step.name
    if type(tool) ~= 'string' or tool == '' then
      return nil, {
        failed_step = index,
        error = 'workflow step requires a non-empty tool',
        steps = state.steps,
      }
    end

    local name = step.name or tool
    local record = {
      index = index,
      name = name,
      tool = tool,
      arguments = nil,
      ok = false,
      output = nil,
      error = nil,
    }

    state.current = record

    local args_ok, args_or_error = pcall(resolve_arguments, step.arguments, state)
    if not args_ok then
      record.error = tostring(args_or_error)
    else
      record.arguments = args_or_error or {}

      local call_ok, result_or_error, call_error = pcall(
        client.call_tool,
        client,
        tool,
        record.arguments
      )

      if not call_ok then
        record.error = tostring(result_or_error)
      elseif call_error ~= nil then
        record.error = call_error
        record.output = result_or_error
      else
        record.ok = true
        record.output = result_or_error
      end
    end

    state.steps[#state.steps + 1] = record
    state.steps[name] = record
    state.previous = record

    if record.ok then
      state.output = record.output
      completed[#completed + 1] = {
        index = index,
        name = name,
        tool = tool,
        rollback = step.rollback,
        output = record.output,
        arguments = record.arguments,
      }
    else
      state.ok = false
      failed_step = index
      failure_error = normalize_error(step, record.error)
      state.errors[#state.errors + 1] = failure_error

      if workflow.on_error ~= 'continue' then
        break
      end
    end
  end

  state.current = nil

  if failed_step and workflow.on_error ~= 'continue' then
    local result = {
      ok = false,
      failed_step = failed_step,
      error = failure_error.error,
      steps = state.steps,
      errors = state.errors,
    }

    if workflow.rollback then
      result.rollbacks = run_rollback(client, state, completed, state.errors)
    end

    return nil, result
  end

  local result = {
    ok = state.ok,
    steps = state.steps,
    errors = state.errors,
    output = state.output,
  }

  if failed_step then
    result.failed_step = failed_step
  end

  return result
end

return Chain
