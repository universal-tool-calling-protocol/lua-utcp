package.path = './lua/?.lua;./lua/?/init.lua;'..package.path

local json = require('utcp.json')
local transports = require('utcp.transports')
local utcp = require('utcp')

-- Ownership and grant type are descriptive metadata. They tell an application
-- to provision a separate OAuth credential for each user; they do not make a
-- transport acquire, refresh, or persist the credential itself.
local user_oauth = {
  auth_type = 'oauth2',
  ownership = 'user',
  grant_type = 'device_code',
}

local transport_configs = {
  {name = 'http', config = {}},
  {name = 'sse', config = {}},
  {name = 'streamable', config = {}},
  {name = 'graphql', config = {}},
  {name = 'mcp', config = {url = 'http://127.0.0.1:8093/mcp'}},
  {name = 'cli', config = {}},
  {name = 'text', config = {}},
  {name = 'tcp', config = {}},
  {name = 'udp', config = {}},
}

for _, entry in ipairs(transport_configs) do
  entry.config.auth = user_oauth
  local metadata, err = transports[entry.name].new(entry.config):auth_metadata()
  assert(metadata, err)
  print(entry.name..': '..assert(json.encode(metadata)))
end

-- A tool can override provider-level authentication. Client:auth_metadata()
-- returns the same effective metadata that is passed to the selected transport.
local client = utcp.new({
  providers = {
    {
      name = 'calendar',
      transport = 'text',
      auth = user_oauth,
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

for _, name in ipairs({'calendar.events', 'calendar.health'}) do
  local metadata, err = client:auth_metadata(name)
  assert(metadata, err)
  print(name..': '..assert(json.encode(metadata)))
end
