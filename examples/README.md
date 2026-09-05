
## Local example servers

The repository includes small Python standard-library servers for the network transport examples. They are intentionally dependency-free and are only test/demo servers.

Start every server in one terminal:

```bash
make servers
```

Or start one server:

```bash
make server-http
make server-sse
make server-streamable
make server-tcp
make server-udp
make server-graphql
make server-mcp
make server-websocket
make server-grpc
```

Server endpoints:

| Transport | Endpoint |
|---|---|
| HTTP | `http://127.0.0.1:8080/echo`, `/add`, `/multiply` |
| SSE | `http://127.0.0.1:8090/events` |
| Streamable HTTP | `http://127.0.0.1:8091/call` |
| GraphQL | `http://127.0.0.1:8092/graphql` |
| MCP | `http://127.0.0.1:8093/mcp` |
| TCP | `127.0.0.1:9000` |
| UDP | `127.0.0.1:9001` |
| WebSocket | `ws://127.0.0.1:8765` |
| gRPC | `127.0.0.1:50051` |

The general servers are implemented under `examples/servers/` with Python's
standard library. The gRPC Greeter is `examples/grpc/server.lua` and uses
`lua-grpc` with the bundled schema and descriptor.

## WebSocket, gRPC and WebRTC

`websocket.lua` sends a typed JSON message to an echo endpoint. Start the
dependency-free bundled server with `make server-websocket`. The client defaults
to the secure local-development URL `ws://127.0.0.1:8765`; set
`UTCP_WEBSOCKET_URL` for another endpoint:

```bash
UTCP_WEBSOCKET_URL=wss://example.test/ws make example-websocket
```

`grpc/client.lua` demonstrates unary and server-streaming calls against the bundled
`examples/grpc/server.lua`. Start both sides in separate terminals:

```bash
make server-grpc
make example-grpc
```

The checked-in `helloworld.proto`, Lua service metadata, and embedded descriptor
make this example runnable without `protoc`. Set `UTCP_GRPC_DESCRIPTOR`,
`UTCP_GRPC_MODULE`, and `UTCP_GRPC_TARGET` to use another generated service.
On systems where Lua 5.4 is not installed through Homebrew, set `LUA_BIN` and
optionally `LUA_DIR`; `examples/grpc/run-lua.sh` loads the matching LuaRocks
paths before starting either side.

Add `--stream` when running the Lua file directly to call `WatchHello` after
the unary RPC. `webrtc.lua` shows the binding-neutral DataChannel contract. Set
the adapter module and signaling endpoint before running it:

```bash
UTCP_WEBRTC_MODULE=my_webrtc_adapter \
UTCP_WEBRTC_SIGNALING_URL=wss://signal.example.test/session \
make example-webrtc
```

The adapter module exposes `new(config)` and returns an object with `send` and
`receive`/`recv`; `connect` and `close` are optional.

All three scripts are included in `make examples`. The playground uses their
self-contained smoke adapters so it remains runnable without external gRPC and
WebRTC services. Set `UTCP_RUN_REALTIME_EXAMPLES=1` to use the real endpoint,
descriptor and binding settings instead.

To run only gRPC against the bundled server while WebSocket and WebRTC keep
using their smoke adapters:

```bash
UTCP_RUN_REAL_GRPC=1 make examples
```

The equivalent per-transport switches are `UTCP_RUN_REAL_WEBSOCKET=1` and
`UTCP_RUN_REAL_WEBRTC=1`.

## Authentication ownership examples

`auth_metadata.lua` is self-contained and prints the OAuth2 ownership metadata
for every built-in transport, then shows how a tool-level auth block overrides a
provider-level block:

```bash
make example-auth-metadata
```

`auth_http.lua` uses the local HTTP echo server to demonstrate a user-owned
OAuth2 authorization-code credential. It prints the effective metadata and
sends the supplied access token as a Bearer header. Start the HTTP server first
or use the full playground command:

```bash
make server-http
make example-auth-http
```

For a real provider, set `UTCP_DEMO_ACCESS_TOKEN` and replace the local URL;
token acquisition, refresh, storage, and session state remain application-owned.

## Guard example

`guard.lua` keeps policy enforcement in the client. It explicitly bypasses a
safe local profile read and account-summary tool, returning both results without
policy evaluation. It denies an account deletion; for a payment, it requires an
approval callback, then dispatches and returns the result. No denied or
unapproved review call reaches a native transport.

```bash
make example-guard
```

## HOL Guard example

`hol_guard.lua` wraps a real CLI tool call with the HOL Guard adapter. It
classifies the requested shell command before UTCP dispatches it: safe commands
run, blocked commands do not reach the CLI transport, and review decisions ask
the local user to type `ALLOW`.

Install [HOL Guard](https://github.com/hashgraph-online/hol-guard) first, then
run the example from the repository root:

```bash
make example-hol-guard
```

It checks `git status --short` by default. Override the executable or command
only when you intend to test it:

```bash
HOL_GUARD_BIN=/absolute/path/to/hol-guard \
HOL_GUARD_EXAMPLE_COMMAND='git clean -fd' \
make example-hol-guard
```

The command runs only after the adapter returns `allow`, or the local user
approves a `review` decision. Replace the example callback with an authenticated
approval workflow in production. Review commands require an interactive terminal
and the exact uppercase response `ALLOW`; non-interactive runs intentionally deny
the command rather than approving it implicitly.

# CodeMode example

`codemode.lua` demonstrates the CodeMode execution model. Generated Lua code
gets one controlled UTCP entry point and invokes tools by name:

```lua
local codemode = utcp.codemode.new(client)
local execution, err = codemode:call_tool_chain([[
  local a = codemode.call_tool("calculator.add", {a = 1, b = 2})
  return codemode.call_tool("calculator.multiply", {a = a, b = 10})
]])
```

The sandbox does **not** expose provider namespaces, `await()`, transport objects,
or the underlying UTCP client. Tool access is centralized through:

```lua
codemode.call_tool(tool_name, args)
codemode.list_tools()
codemode.search_tools(query)
codemode.get_tool_interface(tool_name)
```

This keeps tool resolution, validation, transport selection, and auditing inside
the canonical UTCP client/registry.

## provider.json flow

`provider.json` contains separate `calculator` (HTTP) and `filesystem` (CLI)
manuals in one UTCP 1.1 configuration file. The complete flow is:

```text
provider.json
    ↓
Client.new(config_path)
    ↓
canonical UTCP registry
    ↓
utcp.codemode.new(client)
    ↓
codemode.call_tool("calculator.add", args) / codemode.call_tool("filesystem.read", args)
    ↓
Client:call_tool()
    ↓
HTTP or CLI transport
```

Run `lua examples/provider_flow.lua` to inspect both loaded manuals and their
registered CodeMode interfaces. Start an HTTP UTCP provider on
`127.0.0.1:8080`, then run `lua examples/provider_codemode.lua` to execute the
calculator chain.

## Run the complete local playground

Run every local UTCP server and every transport example with one command:

```bash
make examples
```

The command starts the local HTTP, SSE, Streamable HTTP, GraphQL, MCP, TCP, UDP
and WebSocket servers, waits until all ports are ready, executes the examples,
and always stops the servers on completion or `Ctrl+C`. Set
`UTCP_RUN_REAL_GRPC=1` to start the bundled gRPC server and run its real client
as part of the same playground. `UTCP_RUN_REALTIME_EXAMPLES=1` enables every
real-time transport and therefore also requires a configured WebRTC adapter.

To only keep all example servers running:

```bash
make servers
```
