local M = {}

local aliases = {
  streamable_http = 'streamable',
  http_stream = 'streamable',
  streamable = 'streamable',
  http = 'http',
  sse = 'sse',
  tcp = 'tcp',
  udp = 'udp',
  cli = 'cli',
  file = 'text',
  text = 'text',
  graphql = 'graphql',
  gql = 'graphql',
  mcp = 'mcp',
  websocket = 'websocket',
  ws = 'websocket',
  grpc = 'grpc',
  webrtc = 'webrtc',
}

function M.normalize(value)
  if type(value) ~= 'string' then return nil end
  value = value:lower():gsub('%-', '_')
  if not value:match('^[%a_][%w_]*$') then return nil end
  return aliases[value] or value
end

function M.type(config, fallback)
  config = config or {}
  return M.normalize(
    config.call_template_type
      or config.provider_type
      or config.transport
      or config.type
      or fallback
  )
end

function M.allowed(call_template)
  local own = M.type(call_template, 'http')
  if not own then return nil, 'unsupported UTCP transport' end

  local configured = call_template and call_template.allowed_communication_protocols
  local allowed = {}
  if type(configured) == 'table' and #configured > 0 then
    for _, value in ipairs(configured) do
      local normalized = M.normalize(value)
      if not normalized then
        return nil, 'unsupported allowed communication protocol: ' .. tostring(value)
      end
      allowed[normalized] = true
    end
  else
    allowed[own] = true
  end
  return allowed
end

function M.is_allowed(call_template, tool_protocol)
  if not call_template then return true end
  local allowed, err = M.allowed(call_template)
  if not allowed then return nil, err end
  local normalized = M.normalize(tool_protocol) or tool_protocol
  return allowed[normalized] == true, allowed
end

function M.display_allowed(allowed)
  local values = {}
  for value in pairs(allowed or {}) do values[#values + 1] = value end
  table.sort(values)
  return table.concat(values, ', ')
end

M.aliases = aliases
return M
