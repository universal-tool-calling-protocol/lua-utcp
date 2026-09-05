# Lua UTCP implementation notes

This project implements the UTCP 1.1 shape: a manual contains tools, each tool contains a `tool_call_template`, and the template selects a native communication protocol. Client configuration accepts `manual_call_templates`, scoped/global variables and dotenv loaders. Legacy v0.1 names can be normalized with `utcp.migration`.

Every registered tool is stored under `manual_name.tool_name`. A short name is
also accepted when it resolves to one tool. The v1.1
`allowed_communication_protocols` restriction is applied while registering a
manual and is verified again immediately before dispatch. A missing or empty
allowlist defaults to the manual's own protocol.

Authentication blocks also accept the additive ownership metadata proposed in
[UTCP specification issue #62](https://github.com/universal-tool-calling-protocol/utcp-specification/issues/62):
`ownership` (`static` or `user`) and, for OAuth2, `grant_type`
(`client_credentials`, `authorization_code`, `device_code`, or `jwt_bearer`).
The implementation exposes this metadata without tracking credentials or
session state. Every built-in transport preserves it and exposes it through
`auth_metadata()`; only HTTP-based transports serialize supported credentials
as HTTP headers.

The canonical flow is:

1. Construct `utcp.Client` with providers.
2. Discover or register a UTCP manual.
3. Add every discovered tool to one canonical registry.
4. Resolve a tool by exact name or search the registry.
5. Select the transport from `tool_call_template.call_template_type`.
6. Render placeholders and perform the native call.
7. Return decoded JSON when available, otherwise the raw response.

This mirrors the separation visible in the official Go implementation between manuals, tools, repository/registry, providers and transports. The Lua implementation deliberately keeps those boundaries small and dynamically typed.

## Transport contract

Every transport module exports:

```lua
local transport = module.new(config)
transport:call(tool_call_template, arguments)
```

Streaming transports additionally expose a callback-oriented API.

Stateful transports may also expose `register_manual`, `call_stream`, and
`close`. The client reuses and closes WebSocket, gRPC, WebRTC, and MCP sessions.

## Realtime transport bindings

WebSocket uses the WebSocket implementation in `lua-http`. gRPC uses
`Protocol-Lattice/lua-grpc`, including its protobuf descriptors, HTTP/2
transport, metadata and all four RPC shapes. WebRTC uses a host-provided
DataChannel binding because Lua has no portable standard WebRTC runtime; the
adapter contract requires synchronous `send` and `receive`/`recv` operations
and optionally supplies `connect` and `close`.
