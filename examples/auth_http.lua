package.path = './lua/?.lua;./lua/?/init.lua;'..package.path

local json = require('utcp.json')
local utcp = require('utcp')

-- Substitute a real, user-scoped access token in production. The bundled echo
-- server accepts this demo value and lets the example run without a secret.
local client = utcp.new({
  providers = {
    {
      name = 'authenticated_echo',
      transport = 'http',
      url = os.getenv('UTCP_HTTP_URL') or 'http://127.0.0.1:8080/echo',
      auth = {
        auth_type = 'oauth2',
        ownership = 'user',
        grant_type = 'authorization_code',
        access_token = os.getenv('UTCP_DEMO_ACCESS_TOKEN') or 'demo-access-token',
      },
      tools = {
        {
          name = 'echo',
          description = 'Echo an authenticated request',
          inputs = {type = 'object'},
          tool_call_template = {
            call_template_type = 'http',
            http_method = 'POST',
          },
        },
      },
    },
  },
})

local metadata, metadata_err = client:auth_metadata('authenticated_echo.echo')
assert(metadata, metadata_err)
print('effective auth metadata:', assert(json.encode(metadata)))

local result, err = client:call_tool('authenticated_echo.echo', {
  message = 'hello from an OAuth2 user credential',
})
assert(result, err)
print('HTTP result:', assert(json.encode(result)))
