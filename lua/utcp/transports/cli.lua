local json = require('utcp.json')

local M = {}
local T = {}
T.__index = T

function T.new(cfg)
  return setmetatable(cfg or {}, T)
end

local function shellquote(value)
  value = tostring(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function encode_arg(value)
  if type(value) == 'table' then
    return json.encode(value)
  elseif type(value) == 'boolean' then
    return value and 'true' or 'false'
  end

  return tostring(value)
end

local function expand_command(command, args)
  return command:gsub(
    'UTCP_ARG_([A-Za-z_][A-Za-z0-9_]*)_UTCP_END',
    function(name)
      local value = args and args[name]

      assert(
        value ~= nil,
        'missing CLI argument: ' .. name
      )

      return shellquote(encode_arg(value))
    end
  )
end

local function get_command(t, self)
  -- Direct command.
  if t and t.command then
    return t.command
  end

  if self.command then
    return self.command
  end

  -- UTCP CLI template:
  --
  -- tool_call_template = {
  --   commands = {
  --     {
  --       command = "..."
  --     }
  --   }
  -- }
  local commands = t and t.commands

  if type(commands) == 'table' and commands[1] then
    if type(commands[1]) == 'string' then
      return commands[1]
    end

    if type(commands[1]) == 'table' then
      return commands[1].command
    end
  end

  return nil
end

function T:call(t, args)
  t = t or {}
  args = args or {}

  local command = get_command(t, self)

  assert(
    command,
    'cli command is required'
  )

  --
  -- UTCP placeholder mode.
  --
  -- Example:
  --
  -- go-harness-filesystem --root .
  --   UTCP_ARG_tool_UTCP_END
  --   UTCP_ARG_inputs_UTCP_END
  --
  if command:find('UTCP_ARG_') then
    command = expand_command(command, args)
  else
    --
    -- Traditional CLI argument mode.
    --
    local parts = { command }

    for _, value in ipairs(t.args or self.args or {}) do
      parts[#parts + 1] = shellquote(
        encode_arg(value)
      )
    end

    if t.pass_args or self.pass_args then
      for key, value in pairs(args) do
        parts[#parts + 1] = shellquote('--' .. key)
        parts[#parts + 1] = shellquote(
          encode_arg(value)
        )
      end
    end

    command = table.concat(parts, ' ')
  end

  --
  -- Optional working directory.
  --
  local working_dir =
    t.working_dir
    or self.working_dir

  if working_dir and working_dir ~= '' then
    command =
      'cd '
      .. shellquote(working_dir)
      .. ' && '
      .. command
  end

  command = command .. ' 2>&1'

  local pipe, pipe_err = io.popen(command, 'r')

  if not pipe then
    return nil, pipe_err or 'failed to start CLI command'
  end

  local output = pipe:read('*a')

  local ok, reason, code = pipe:close()

  if not ok or (code and code ~= 0) then
    return nil, output
  end

  local decoded = json.decode(output)

  if decoded ~= nil then
    return decoded
  end

  return output
end

function M.new(cfg)
  return T.new(cfg)
end

M.Transport = T

return M