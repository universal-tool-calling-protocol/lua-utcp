local json = require('utcp.json')

local M = {}
local T = {}
T.__index = T

function T.new(cfg)
  return setmetatable(cfg or {}, T)
end

local function shellquote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function json_or_string(value)
  if type(value) == 'table' then
    local encoded, err = json.encode(value)
    assert(encoded, err)
    return encoded
  end

  if value == nil then
    return ''
  end

  return tostring(value)
end

local function lookup(args, key)
  local value = args and args[key]
  if value ~= nil then
    return value
  end

  local current = args
  for part in key:gmatch('[^%.]+') do
    if type(current) ~= 'table' then
      return nil
    end
    current = current[part]
  end

  return current
end

-- CLI manuals use UTCP_ARG_<name>_UTCP_END placeholders inside command
-- strings. Replace each placeholder with a shell-quoted argument. Tables are
-- JSON encoded so nested UTCP inputs can be passed safely to a CLI process.
local function render_command(command, args)
  return (command:gsub('UTCP_ARG_([%w_%.%-]+)_UTCP_END', function(key)
    local value = lookup(args, key)
    assert(value ~= nil, 'missing CLI argument: ' .. key)
    return shellquote(json_or_string(value))
  end))
end

local function command_from_template(template, config)
  if template.command then
    return template.command
  end

  if template.commands then
    assert(#template.commands > 0, 'cli commands cannot be empty')
    local command = template.commands[1]
    if type(command) == 'table' then
      return command.command or command.cmd
    end
    return command
  end

  if config.command then
    return config.command
  end

  if config.commands then
    assert(#config.commands > 0, 'cli commands cannot be empty')
    local command = config.commands[1]
    if type(command) == 'table' then
      return command.command or command.cmd
    end
    return command
  end

  return nil
end

function T:call(t, args)
  t = t or {}
  args = args or {}

  local cmd = command_from_template(t, self)
  assert(cmd, 'cli command is required')

  local rendered = render_command(cmd, args)
  local parts = {}

  if t.working_dir or self.working_dir then
    parts[#parts + 1] = 'cd'
    parts[#parts + 1] = shellquote(t.working_dir or self.working_dir)
    parts[#parts + 1] = '&&'
  end

  parts[#parts + 1] = rendered

  for _, value in ipairs(t.args or self.args or {}) do
    parts[#parts + 1] = shellquote(
      type(value) == 'string' and value or json_or_string(value)
    )
  end

  if t.pass_args or self.pass_args then
    for key, value in pairs(args) do
      parts[#parts + 1] = shellquote('--' .. key)
      parts[#parts + 1] = shellquote(json_or_string(value))
    end
  end

  local process = assert(
    io.popen(table.concat(parts, ' ') .. ' 2>&1', 'r')
  )

  local output = process:read('*a')
  local _, _, code = process:close()

  if code and code ~= 0 then
    return nil, output
  end

  local decoded = json.decode(output)
  return decoded or output
end

function M.new(cfg)
  return T.new(cfg)
end

M.Transport = T

return M
