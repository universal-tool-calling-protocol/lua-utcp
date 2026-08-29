# lua-utcp

**UTCP for Lua — native tool calling, multiple transports, and LLM-ready CodeMode.**

`lua-utcp` is a Lua implementation of the [Universal Tool Calling Protocol (UTCP)](https://github.com/universal-tool-calling-protocol/utcp-specification). It enables Lua applications to discover tools from providers, maintain a canonical registry, and invoke them directly via their native transport, eliminating the need for wrapper servers or provider-specific adapters.

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

## Features

*   **Native Tool Calling**: Invoke tools through their native transport without introducing a wrapper protocol server.
*   **Canonical Registry**: Tools have a stable, unified name and schema across all transports.
*   **Transport Independence**: Supports HTTP, SSE, Streamable HTTP, TCP, UDP, CLI, Text, GraphQL, and MCP.
*   **CodeMode Ready**: Enables LLMs to generate Lua code that exclusively calls registered UTCP tools.
*   **LLM Friendly**: Compatible with OpenAI-compatible APIs, including OpenRouter via `lua-openai`.
*   **Minimal Lua API**: Designed for embedding within applications and agents.
*   **Structured Errors**: Provides programmatic handling for tool and transport failures.

## Requirements

*   Lua 5.3 or 5.4
*   `lua-socket`
*   `lua-cjson` (recommended) or `dkjson`
*   LuaRocks (optional, but recommended for installation)

## Installation

### LuaRocks

```sh
luarocks install lua-utcp-1.3-1.rockspec
```

### From Source

```sh
git clone https://github.com/universal-tool-calling-protocol/lua-utcp.git
cd lua-utcp
make test
```

## Quick Start

This example demonstrates creating a client with an HTTP provider, discovering its manual, and calling a tool:

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

The key benefit is that the application invokes the `echo` tool via the canonical UTCP registry, abstracting away the underlying transport mechanism.

## Supported Transports

| Transport             | Status           |
| :-------------------- | :--------------- |
| HTTP                  | ✅ Implemented   |
| SSE                   | ✅ Implemented   |
| Streamable HTTP       | ✅ Implemented   |
| TCP                   | ✅ Implemented   |
| UDP                   | ✅ Implemented   |
| CLI                   | ✅ Implemented   |
| Text                  | ✅ Implemented   |
| GraphQL               | ✅ Implemented   |
| MCP JSON-RPC over HTTP| ✅ Implemented   |
| gRPC                  | Extension point  |
| WebRTC                | Extension point  |
| WebSocket             | Extension point  |

The core client and registry are transport-agnostic. New transports can be implemented and registered via `lua/utcp/transports/init.lua`.

## Defining a UTCP Manual Directly

You can register a manual without relying on remote discovery:

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

This makes the tool accessible through the same canonical registry used for discovered providers.

## Streaming

Streaming tools can be consumed incrementally:

```lua
client:call_tool_stream("events", {}, function(event)
  print(event.event, event.data)
end)
```

The SSE parser handles `event`, `id`, and multi-line `data` fields, decoding JSON payloads when possible.

## CodeMode

CodeMode is the LLM-focused execution layer of `lua-utcp`. It provides a constrained Lua environment where models generate code that interacts with the canonical UTCP registry, rather than directly producing transport-specific calls.

```lua
local codemode = utcp.codemode.new(client)

local result = codemode.call_tool("echo", {
  message = "hello"
})
```

The CodeMode API exposes only canonical tool operations, preventing the LLM from generating invalid transport calls or accessing undefined tool endpoints.

### CodeMode Tool Chain

Generated Lua programs can orchestrate multiple registered tools:

```lua
local execution = assert(codemode:call_tool_chain([[
  local a = codemode.call_tool("calculator.add", { a = 10, b = 20 })
  return a
]]))
```

The execution flow is as follows:

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

This separation is particularly beneficial for agent runtimes, allowing the LLM to focus on expressing computation while UTCP manages tool discovery and invocation.

## OpenRouter + CodeMode Integration

`lua-utcp` includes examples demonstrating the integration of CodeMode with OpenAI-compatible LLM APIs via [`lua-openai`](https://github.com/leafo/lua-openai).

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

Or execute the chat-session variant:

```sh
make example-openrouter-codemode-chat
```

The complete architecture for this integration is:

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

The LLM receives the discovered UTCP tool catalog and is prompted to generate Lua CodeMode. The generated code invokes registered tools using `codemode.call_tool(...)` without direct access to transport objects.

Refer to the following examples:

*   `examples/openrouter_codemode.lua`
*   `examples/openrouter_codemode_chat.lua`

## Provider JSON → UTCP → CodeMode Flow

Providers can also be defined in JSON and loaded into the canonical registry:

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

*   `provider.json`
*   `examples/provider_flow.lua`
*   `examples/provider_codemode.lua`

## Architecture

The implementation is structured into modular layers:

```text
utcp
├── client       # Discovery and invocation logic
├── registry     # Canonical provider/tool index
├── transports   # Native transport implementations
├── codemode     # Constrained Lua execution API
├── json         # JSON backend abstraction
└── errors       # Structured error handling
```

### Core Modules

*   `utcp.client`: Handles provider discovery, manual registration, and tool invocation.
*   `utcp.registry`: Manages the indexing and lookup of providers and tools by name and tag.
*   `utcp.transports.*`: Contains implementations for various native transports.
*   `utcp.codemode`: Provides the Lua execution environment and canonical tool access for LLMs.
*   `utcp.json`: Abstracts the underlying JSON library.
*   `utcp.errors`: Defines the structure for error handling.

## Examples and Local Servers

Network-related examples utilize local servers located in `examples/servers/`.

To start all demo servers:

```sh
make servers
```

Alternatively, start individual servers using `make server-*` targets.

## Testing

Run the unit and core test suite:

```sh
make test
```

Execute transport integration tests:

```sh
make integration
```

## Project Structure

```
lua-utcp/
├── lua/                    # Library implementation
├── tests/                  # Unit and transport tests
├── examples/               # Usage and CodeMode examples
├── examples/servers/       # Local demo tool servers
├── provider.json            # Example provider definition file
├── Makefile
└── lua-utcp-*.rockspec
```

## Related Projects

*   [UTCP specification](https://github.com/universal-tool-calling-protocol/utcp-specification)
*   [Go UTCP](https://github.com/universal-tool-calling-protocol/go-utcp)
*   [Rust UTCP](https://github.com/universal-tool-calling-protocol/rs-utcp)

## License

MPL-2.0.
