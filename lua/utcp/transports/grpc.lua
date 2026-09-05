local auth = require('utcp.auth')

local M, T = {}, {}
T.__index = T

local function copy_into(target, source)
  for key, value in pairs(source or {}) do target[key] = value end
  return target
end

local function load_grpc(self)
  if self.grpc_module then return self.grpc_module end
  local ok, module = pcall(require, 'grpc')
  if not ok then
    return nil, 'lua-grpc is required for gRPC (use Lua 5.3 or 5.4): ' .. tostring(module)
  end
  return module
end

local function target_for(config)
  local target = config.target or config.address or config.endpoint or config.url
  if type(target) == 'string' then
    target = target:gsub('^grpcs?://', '')
  elseif config.host and config.port then
    target = tostring(config.host) .. ':' .. tostring(config.port)
  end
  return target
end

local function method_from_module(module, service_name, method_name)
  if type(module) ~= 'table' then return nil end
  local service = module[service_name] or module.services and module.services[service_name]
  if not service and module.service_name and module.methods then service = module end
  if not service or not service.methods then return nil end
  return service.methods[method_name]
    or service.methods[(method_name or ''):gsub('^%l', string.upper)]
end

function T.new(config)
  return setmetatable(config or {}, T)
end

function T:auth_metadata()
  return auth.metadata(self.auth)
end

function T:_method(config)
  if type(config.method_descriptor) == 'table' then return config.method_descriptor end
  local descriptor_module = config.descriptor_module or self.descriptor_module
  if type(descriptor_module) == 'string' then
    local ok, loaded = pcall(require, descriptor_module)
    if not ok then return nil, 'cannot load gRPC descriptor module: ' .. tostring(loaded) end
    descriptor_module = loaded
  end
  local service_name = config.service or config.service_name or self.service or self.service_name
  local method_name = config.method or config.method_name or self.method or self.method_name
  local generated = method_from_module(descriptor_module, service_name, method_name)
  if generated then return generated end
  if not service_name or not method_name then return nil, 'gRPC service and method are required' end
  if not config.input_type or not config.output_type then
    return nil, 'gRPC input_type and output_type are required without a generated descriptor module'
  end
  return {
    name = method_name,
    full_name = service_name .. '.' .. method_name,
    path = config.path or '/' .. service_name .. '/' .. method_name,
    input_type = config.input_type,
    output_type = config.output_type,
    client_streaming = config.client_streaming == true,
    server_streaming = config.server_streaming == true,
    interceptors = {
      client = (config.client_streaming or config.server_streaming) and 'stream' or 'unary',
      server = (config.client_streaming or config.server_streaming) and 'stream' or 'unary',
    },
    options = config.method_options or {},
  }
end

function T:_connection(config)
  if self._connection_value then return self._connection_value, self._grpc end
  local grpc, load_err = load_grpc(self)
  if not grpc then return nil, load_err end
  local descriptor = config.descriptor_set or config.descriptor_set_path or self.descriptor_set or self.descriptor_set_path
  if descriptor and not self._descriptors_loaded then
    local ok, err = grpc.load_descriptor_set(descriptor)
    if not ok then return nil, err end
    self._descriptors_loaded = true
  end
  local target = target_for(config)
  if not target then return nil, 'gRPC target is required' end
  local options = copy_into({}, self.grpc_options)
  copy_into(options, config.grpc_options)
  for _, key in ipairs({'insecure', 'compression', 'tls', 'ca_file', 'server_name'}) do
    if config[key] ~= nil then options[key] = config[key]
    elseif self[key] ~= nil then options[key] = self[key] end
  end
  local connection, dial_err = grpc.dial(target, options)
  if not connection then return nil, dial_err end
  self._connection_value, self._grpc = connection, grpc
  return connection, grpc
end

function T:_context(config)
  local _, grpc_or_err = self:_connection(config)
  if not self._connection_value then return nil, grpc_or_err end
  local metadata = {}
  copy_into(metadata, self.metadata)
  copy_into(metadata, config.metadata)
  local headers = auth.apply({}, config.auth or self.auth)
  for key, value in pairs(headers) do metadata[key:lower()] = tostring(value) end
  return grpc_or_err.context({timeout = config.timeout or self.timeout or 30, metadata = metadata})
end

local function request_messages(args, config)
  local messages = args[config.messages_field or 'messages'] or args.requests
  if messages == nil and args[1] ~= nil then messages = args end
  if type(messages) ~= 'table' then messages = {args} end
  return messages
end

local function receive_all(stream, on_event)
  local responses = {}
  while true do
    local response, err = stream:recv()
    if err then return nil, err end
    if response == nil then break end
    if on_event then
      local ok, keep_going = pcall(on_event, response)
      if not ok then return nil, 'gRPC event callback error: ' .. tostring(keep_going) end
      if keep_going == false then break end
    else
      responses[#responses + 1] = response
    end
  end
  if on_event then return true end
  return responses
end

function T:_call(config, args, on_event)
  local connection, connection_err = self:_connection(config)
  if not connection then return nil, connection_err end
  local method, method_err = self:_method(config)
  if not method then return nil, method_err end
  local context, context_err = self:_context(config)
  if not context then return nil, context_err end
  local options = config.call_options or {}

  if not method.client_streaming and not method.server_streaming then
    local response, err = connection:invoke(context, method, args, options)
    if err then return nil, err end
    if on_event then
      local ok, callback_err = pcall(on_event, response)
      if not ok then return nil, 'gRPC event callback error: ' .. tostring(callback_err) end
      return true
    end
    return response
  end

  local initial = method.client_streaming and nil or args
  local stream, stream_err = connection:new_stream(context, method, initial, options)
  if not stream then return nil, stream_err end
  if method.client_streaming then
    for _, message in ipairs(request_messages(args, config)) do
      local sent, send_err = stream:send(message)
      if not sent then return nil, send_err end
    end
    local closed, close_err = stream:close_send()
    if not closed then return nil, close_err end
  end
  if method.server_streaming then return receive_all(stream, on_event) end
  local response, receive_err = stream:recv()
  if receive_err then return nil, receive_err end
  if on_event then
    local ok, callback_err = pcall(on_event, response)
    if not ok then return nil, 'gRPC event callback error: ' .. tostring(callback_err) end
    return true
  end
  return response
end

function T:call(call_template, args)
  return self:_call(call_template or self, args or {})
end

function T:call_stream(call_template, args, on_event)
  if type(on_event) ~= 'function' then return nil, 'gRPC streaming requires an event callback' end
  return self:_call(call_template or self, args or {}, on_event)
end

function T:register_manual(call_template)
  return self:call(call_template or self, (call_template or self).manual_args or {})
end

function T:close()
  if self._connection_value and self._connection_value.close then
    local ok, err = self._connection_value:close()
    self._connection_value = nil
    return ok, err
  end
  return true
end

function M.new(config) return T.new(config) end
M.Transport = T
return M
