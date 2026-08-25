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
  command = command:gsub(
    'UTCP_ARG_JSON_UTCP_END',
    function()
      return shellquote(json.encode(args or {}))
    end
  )

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
  if t and t.command then
    return t.command
  end

  if self.command then
    return self.command
  end

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

local function decode_output(output)
  -- CLI tools may return JSON or plain text. Do not let a JSON parser
  -- exception turn a valid text result into a transport failure.
  local ok, decoded = pcall(json.decode, output)

  if ok and decoded ~= nil then
    return decoded
  end

  return output
end

function T:call(t, args)
  t = t or {}
  args = args or {}

  local command = get_command(t, self)

  assert(
    command,
    'cli command is required'
  )

  if command:find('UTCP_ARG_') then
    command = expand_command(command, args)
  else
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

  -- Explicit output_type wins. Otherwise preserve backwards compatibility:
  -- decode JSON when possible and return raw text otherwise.
  local output_type = t.output_type or self.output_type

  if output_type == 'text' or output_type == 'string' then
    return output
  end

  return decode_output(output)
end

function M.new(cfg)
  return T.new(cfg)
end

M.Transport = T

return M
