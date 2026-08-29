package.path = './lua/?.lua;./lua/?/init.lua;'..package.path

local utcp = require('utcp')
local auth = utcp.auth

local api_key_metadata = assert(auth.metadata({auth_type = 'api_key'}))
assert(api_key_metadata.auth_type == 'api_key')
assert(api_key_metadata.ownership == 'static')
assert(api_key_metadata.grant_type == nil)

local oauth_metadata = assert(auth.metadata({
  auth_type = 'oauth2',
  ownership = 'user',
  grant_type = 'authorization_code',
}))
assert(oauth_metadata.ownership == 'user')
assert(oauth_metadata.grant_type == 'authorization_code')

local default_oauth = assert(auth.metadata({auth_type = 'oauth2'}))
assert(default_oauth.ownership == 'static')
assert(default_oauth.grant_type == 'client_credentials')

local legacy_metadata = assert(auth.metadata({type = 'bearer'}))
assert(legacy_metadata.auth_type == 'bearer')
assert(legacy_metadata.ownership == 'static')

local _, ownership_err = auth.metadata({auth_type = 'api_key', ownership = 'tenant'})
assert(ownership_err:match('ownership'))
local _, grant_err = auth.metadata({auth_type = 'api_key', grant_type = 'authorization_code'})
assert(grant_err:match('only valid'))
local _, oauth_grant_err = auth.metadata({auth_type = 'oauth2', grant_type = 'implicit'})
assert(oauth_grant_err:match('grant_type'))

local headers = auth.apply({}, {
  auth_type = 'oauth2',
  ownership = 'user',
  grant_type = 'authorization_code',
  access_token = 'user-token',
})
assert(headers.Authorization == 'Bearer user-token')

local transports = require('utcp.transports')
local transport_auth = {
  auth_type = 'oauth2',
  ownership = 'user',
  grant_type = 'device_code',
}
local transport_configs = {
  http = {},
  sse = {},
  streamable = {},
  graphql = {},
  mcp = {url = 'http://unused'},
  cli = {},
  text = {},
  tcp = {},
  udp = {},
}
for name, config in pairs(transport_configs) do
  config.auth = transport_auth
  local metadata = assert(transports[name].new(config):auth_metadata())
  assert(metadata.auth_type == 'oauth2', name..' must preserve auth_type')
  assert(metadata.ownership == 'user', name..' must preserve ownership')
  assert(metadata.grant_type == 'device_code', name..' must preserve grant_type')
end

local client = utcp.new({
  providers = {
    {
      name = 'calendar',
      transport = 'text',
      auth = {auth_type = 'oauth2', ownership = 'user', grant_type = 'device_code'},
      tools = {
        {name = 'events', tool_call_template = {call_template_type = 'text', path = 'unused'}},
        {
          name = 'health',
          tool_call_template = {
            call_template_type = 'text',
            path = 'unused',
            auth = {auth_type = 'api_key'},
          },
        },
      },
    },
  },
})

local events_metadata = assert(client:auth_metadata('calendar.events'))
assert(events_metadata.auth_type == 'oauth2')
assert(events_metadata.ownership == 'user')
assert(events_metadata.grant_type == 'device_code')

local health_metadata = assert(client:auth_metadata('calendar.health'))
assert(health_metadata.auth_type == 'api_key')
assert(health_metadata.ownership == 'static')
assert(health_metadata.grant_type == nil)

local missing_metadata = client:auth_metadata('missing')
assert(missing_metadata == nil)

local original_text_new = transports.text.new
local text_constructions = 0
transports.text.new = function()
  text_constructions = text_constructions + 1
  return {call = function(_, _, args) return args end}
end

local invalid_client = utcp.new()
invalid_client:add_manual({tools = {{
  name = 'invalid_auth',
  tool_call_template = {
    call_template_type = 'text',
    auth = {auth_type = 'oauth2', ownership = 'other'},
  },
}}})
local result, call_err = invalid_client:call_tool('invalid_auth', {})
assert(result == nil)
assert(call_err:match('ownership'))
assert(text_constructions == 0, 'invalid auth metadata must reject before dispatch')
transports.text.new = original_text_new

print('authentication metadata tests: ok')
