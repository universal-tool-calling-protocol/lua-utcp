# lua-utcp

**UTCP for Lua — native tool calling, multiple transports, and LLM-ready CodeMode.**

`lua-utcp` is a Lua implementation of the [Universal Tool Calling Protocol (UTCP)](https://github.com/universal-tool-calling-protocol/utcp-specification).

It lets a Lua application discover tools from providers, keep them in a canonical registry, and call them directly through their native transport. No wrapper server or provider-specific adapter is required.

```text
                 UTCP manual / provider
                         │
                         ▼
                  ┌─────────────┐
                  │   Registry  │
                  └──────┬──────┘
                         │
                 canonical tool
                         │
                         ▼
                  ┌─────────────┐
                  │    Client   │
                  └──────┬──────┘
                         │
              native transport
                         │
                         ▼
                    Tool server
```

## Why lua-utcp?

- **Native tool calling** — call tools through their native transport instead of introducing a wrapper protocol server.
- **Canonical registry** — discovered tools have one stable name and schema regardless of transport.
- **Transport independent** — HTTP, SSE, Streamable HTTP, TCP, UDP, CLI, Text, GraphQL, and MCP are supported.
- **CodeMode ready** — let an LLM generate Lua that invokes only registered UTCP tools.
- **LLM friendly** — works with OpenAI-compatible APIs, including OpenRouter through `lua-openai`.
- **Small Lua API** — designed to be embedded in applications and agents.
- **Structured errors** — tool and transport failures can be handled programmatically.

## Requirements

- Lua 5.3 or 5.4
- `lua-socket`
- `lua-cjson` (recommended) or `dkjson`
- LuaRocks is optional, but recommended for installation

## Installation

### LuaRocks

```sh
luarocks install lua-utcp-1.0-1.rockspec
```

### From source

```sh
git clone https://github.com/universal-tool-calling-protocol/lua-utcp.git
cd lua-utcp
make test
```

## Quick start

Create a client with an HTTP provider, discover its manual, and call a tool:

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

local result, err = client:call_tool("echo", {
  message = "hello"
})

assert(result, err)
print(type(result) == "table" and result.message or result)
```

The important part is that the application calls `echo` through the canonical UTCP registry. The underlying transport is an implementation detail.

## Supported transports

| Transport | Status |
| --- | --- |
| HTTP | ✅ Implemented |
| SSE | ✅ Implemented |
| Streamable HTTP | ✅ Implemented |
| TCP | ✅ Implemented |
| UDP | ✅ Implemented |
| CLI | ✅ Implemented |
| Text | ✅ Implemented |
| GraphQL | ✅ Implemented |
| MCP JSON-RPC over HTTP | ✅ Implemented |
| gRPC | Extension point |
| WebRTC | Extension point |
| WebSocket | Extension point |

The core client and registry are transport independent. A transport implements the required call/stream behavior and can be registered through `lua/utcp/transports/init.lua`.

## Define a UTCP manual directly

You can register a manual without remote discovery:

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
        properties = {
          message = { type = "string" }
        },
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

This makes the tool available through the same canonical registry used by discovered providers.

## Streaming

Streaming tools can be consumed incrementally:

```lua
client:call_tool_stream("events", {}, function(event)
  print(event.event, event.data)
end)
```

SSE parsing supports `event`, `id`, and multi-line `data` fields. JSON event payloads are decoded when possible.

## CodeMode

CodeMode is the LLM-oriented execution layer of `lua-utcp`.

Instead of asking a model to produce provider-specific HTTP requests, shell commands, or transport calls, the model generates Lua and uses the canonical UTCP registry:

```lua
local codemode = utcp.codemode.new(client)

local result = codemode.call_tool("echo", {
  message = "hello"
})
```

The CodeMode interface deliberately exposes **canonical tool operations**, not the underlying client or transport implementation. This gives the model a constrained execution surface and prevents it from inventing transport calls or tool endpoints.

### CodeMode tool chain

A generated Lua program can orchestrate multiple registered tools:

```lua
local execution = assert(codemode:call_tool_chain([[
  local a = codemode.call_tool("calculator.add", { a = 10, b = 20 })
  return a
]]))
```

The flow is:

```text
LLM
 │
 │ generates Lua
 ▼
CodeMode
 │
 │ call_tool(name, args)
 ▼
Canonical UTCP registry
 │
 ▼
Native transport
 │
 ▼
Tool server
```

This separation is especially useful for agent runtimes: the LLM decides **what computation to express**, while UTCP remains responsible for **which tools actually exist and how they are called**.

## OpenRouter + CodeMode

`lua-utcp` includes examples showing how to combine CodeMode with an OpenAI-compatible LLM API through [`lua-openai`](https://github.com/leafo/lua-openai).

Install the optional dependency and configure your API key:

```sh
luarocks install lua-openai
export OPENROUTER_API_KEY=sk-or-...
```

Start the example HTTP tool server:

```sh
make server-http
```

Run the generated-CodeMode example:

```sh
make example-openrouter-codemode
```

Or run the chat-session variant:

```sh
make example-openrouter-codemode-chat
```

The complete architecture is:

```text
OpenRouter / lua-openai
        │
        │ generate Lua
        ▼
   CodeMode sandbox
        │
        │ canonical tool call
        ▼
   UTCP registry
        │
        ▼
   Native transport
        │
        ▼
     Tool server
```

The model receives the discovered UTCP tool catalog and is instructed to emit Lua CodeMode. Generated code can invoke registered tools through `codemode.call_tool(...)`, but does not need direct access to transport objects.

See:

- `examples/openrouter_codemode.lua`
- `examples/openrouter_codemode_chat.lua`

## Provider JSON → UTCP → CodeMode

Providers can also be described in JSON and loaded into the canonical registry:

```lua
local utcp = require("utcp")

local provider = assert(utcp.load_provider("provider.json"))

local client = utcp.Client.new()
assert(client:add_provider(provider))

local codemode = utcp.codemode.new(client)

local execution = assert(codemode:call_tool_chain([[
  return codemode.call_tool("calculator.add", {
    a = 10,
    b = 20
  })
]]))
```

Related examples:

- `provider.json`
- `examples/provider_flow.lua`
- `examples/provider_codemode.lua`

## Architecture

The implementation is intentionally split into small layers:

```text
utcp
├── client       discovery + invocation
├── registry     canonical provider/tool index
├── transports   native transport implementations
├── codemode     constrained Lua execution API
├── json         JSON backend abstraction
└── errors       structured error handling
```

### Core modules

- `utcp.client` — provider discovery, manual registration, and tool invocation.
- `utcp.registry` — provider/tool indexing and name/tag lookup.
- `utcp.transports.*` — transport implementations.
- `utcp.codemode` — Lua execution and canonical tool access.
- `utcp.json` — JSON backend abstraction.
- `utcp.errors` — structured errors.

## Examples and local servers

Network examples use local servers under `examples/servers/`.

Start the demo servers with:

```sh
make servers
```

Or start an individual server with one of the `make server-*` targets.

## Testing

Run the unit and core test suite:

```sh
make test
```

Run transport integration tests:

```sh
make integration
```

## Project structure

```text
lua-utcp/
├── lua/                    # library implementation
├── tests/                  # unit and transport tests
├── examples/               # usage and CodeMode examples
├── examples/servers/       # local demo tool servers
├── provider.json            # provider flow example
├── Makefile
└── lua-utcp-*.rockspec
```

## Related projects

- [UTCP specification](https://github.com/universal-tool-calling-protocol/utcp-specification)
- [Go UTCP](https://github.com/universal-tool-calling-protocol/go-utcp)
- [Rust UTCP](https://github.com/universal-tool-calling-protocol/rs-utcp)

## License

MPL-2.0.
