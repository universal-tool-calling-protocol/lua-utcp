
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

The servers are implemented under `examples/servers/` and use only Python's standard library.

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

`provider.json` is a concrete provider declaration. The complete flow is:

```text
provider.json
    ↓
utcp.load_provider()
    ↓
Client:add_provider()
    ↓
canonical UTCP registry
    ↓
utcp.codemode.new(client)
    ↓
codemode.call_tool("calculator.add", args) / codemode.call_tool("calculator.multiply", args)
    ↓
Client:call_tool()
    ↓
HTTP transport
```

Run `lua examples/provider_flow.lua` to inspect the loaded provider and registered CodeMode interfaces. Start an HTTP UTCP provider on `127.0.0.1:8080`, then run `lua examples/provider_codemode.lua` to execute the complete chain.

## Run the complete local playground

Run every local UTCP server and every transport example with one command:

```bash
make examples
```

The command starts HTTP, SSE, Streamable HTTP, GraphQL, MCP, TCP and UDP servers, waits until all ports are ready, executes the examples, and always stops the servers on completion or `Ctrl+C`.

To only keep all example servers running:

```bash
make servers
```
