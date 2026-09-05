local json = require('utcp.json')
local auth = require('utcp.auth')

local M = {}
local T = {}
T.__index = T

function T.new(cfg)
  return setmetatable(cfg or {}, T)
end

function T:auth_metadata()
  return auth.metadata(self.auth)
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

local function get_commands(t, self)
  local commands = t.commands or self.commands
  if type(commands) == 'table' and commands[1] then return commands end
  local command = t.command or self.command
  if command then return {{command = command, append_to_final_output = true}} end
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

  local commands = get_commands(t, self)

  assert(
    commands,
    'cli command or commands is required'
  )

  local working_dir =
    t.working_dir
    or self.working_dir
  local environment = t.env_vars or self.env_vars or {}
  local outputs = {}

  for index, entry in ipairs(commands) do
    local spec = type(entry) == 'table' and entry or {command = entry}
    local command = assert(spec.command, 'cli commands[' .. index .. '].command is required')

    if command:find('UTCP_ARG_') then
      command = expand_command(command, args)
    elseif #commands == 1 then
      local parts = {command}
      for _, value in ipairs(t.args or self.args or {}) do
        parts[#parts + 1] = shellquote(encode_arg(value))
      end
      if t.pass_args or self.pass_args then
        for key, value in pairs(args) do
          parts[#parts + 1] = shellquote('--' .. key)
          parts[#parts + 1] = shellquote(encode_arg(value))
        end
      end
      command = table.concat(parts, ' ')
    end

    local env_parts = {}
    for key, value in pairs(environment) do
      assert(tostring(key):match('^[%a_][%w_]*$'), 'invalid CLI environment variable name')
      env_parts[#env_parts + 1] = tostring(key) .. '=' .. shellquote(value)
    end
    table.sort(env_parts)
    if #env_parts > 0 then command = table.concat(env_parts, ' ') .. ' ' .. command end
    if working_dir and working_dir ~= '' then
      command = 'cd ' .. shellquote(working_dir) .. ' && ' .. command
    end
    command = command .. ' 2>&1'

    local pipe, pipe_err = io.popen(command, 'r')
    if not pipe then return nil, pipe_err or 'failed to start CLI command' end
    local output = pipe:read('*a')
    local ok, _, code = pipe:close()
    if not ok or (code and code ~= 0) then return nil, output end
    if spec.append_to_final_output == true
        or (spec.append_to_final_output == nil and index == #commands) then
      outputs[#outputs + 1] = output
    end
  end

  local output = table.concat(outputs)

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
