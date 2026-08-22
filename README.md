# lua-utcp

Lua implementation of the Universal Tool Calling Protocol (UTCP), modeled after the official Go/Rust implementations and the UTCP 1.x data model.

UTCP is a native tool-calling protocol: a client discovers a tool manual and then calls the tool through its native transport rather than requiring a wrapper server.

## Requirements

- Lua 5.3 or 5.4
- `lua-socket`
- `lua-cjson` (recommended) or `dkjson`
- optional `luarocks` for installation

## Supported transports

| Transport | Status |
|---|---|
| HTTP | implemented |
| SSE | implemented |
| Streamable HTTP | implemented |
| TCP | implemented |
| UDP | implemented |
| CLI | implemented |
| Text | implemented |
| GraphQL | implemented |
| MCP JSON-RPC over HTTP | implemented |
| gRPC / WebRTC / WebSocket | extension points; require ecosystem-specific Lua runtimes |

The core registry and client are transport independent. New transports implement `call()` and can be registered in `lua/utcp/transports/init.lua`.

## Quick start

```lua
local utcp = require("utcp")

local client = utcp.new({
  providers = {
    {
      name = "demo",
      provider_type = "http",
      url = "http://127.0.0.1:8080",
      tools_url = "http://127.0.0.1:8080/manual"
    }
  }
})

assert(client:discover())
local result, err = client:call_tool("echo", { message = "hello" })
assert(result, err)
print(type(result) == "table" and result.message or result)
```

## Manual

A UTCP manual can be registered directly:

```lua
client:add_manual({
  manual_version = "1.0",
  utcp_version = "1.0",
  tools = {
    {
      name = "echo",
      description = "Echo a message",
      inputs = {
        type = "object",
        properties = { message = { type = "string" } },
        required = { "message" }
      },
      tool_call_template = {
        call_template_type = "http",
        url = "http://127.0.0.1:8080/echo",
        http_method = "POST"
      }
    }
  }
})
```

## Streaming

```lua
client:call_tool_stream("events", {}, function(event)
  print(event.event, event.data)
end)
```

SSE parsing handles `event`, `id`, and multi-line `data` fields and decodes JSON payloads when possible.

## CodeMode

The CodeMode adapter exposes only canonical registry operations, avoiding invented tool names:

```lua
local tools = utcp.codemode.new(client)
local result = tools.call("echo", { message = "hello" })
```

## Design

- `utcp.client` — discovery, canonical registry and tool invocation.
- `utcp.registry` — provider/tool index and tag/name search.
- `utcp.transports.*` — native transport implementations.
- `utcp.json` — JSON backend abstraction.
- `utcp.codemode` — small execution API for Lua-based orchestration.
- `utcp.errors` — structured errors.

## Installation with LuaRocks

```sh
luarocks install lua-utcp-1.0-1.rockspec
```

## Tests

The test suite is intentionally dependency-light. Run:

```sh
make test
```

For transport integration tests:

```sh
make integration
```

## Reference implementations

- Go: https://github.com/universal-tool-calling-protocol/go-utcp
- Rust: https://github.com/universal-tool-calling-protocol/rs-utcp
- Specification: https://github.com/universal-tool-calling-protocol/utcp-specification

## License

MPL-2.0.


## provider.json → UTCP → CodeMode

A provider can be declared as JSON and loaded directly into the canonical UTCP registry:

```lua
local utcp = require('utcp')

local provider = assert(utcp.load_provider('provider.json'))
local client = utcp.Client.new()
assert(client:add_provider(provider))

local codemode = utcp.codemode.new(client)
local execution = assert(codemode:call_tool_chain([[
  return codemode.call_tool('calculator.add', {a = 10, b = 20})
]]))
```

See `provider.json`, `examples/provider_flow.lua`, and `examples/provider_codemode.lua` for the complete flow.

## Example servers

Network transport examples include local Python servers under `examples/servers/`. Run `make servers` to start all demo servers, or use the individual `make server-*` targets.
