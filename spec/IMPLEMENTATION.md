# Lua UTCP implementation notes

This project follows the current UTCP 1.x shape: a manual contains tools, each tool contains a `tool_call_template`, and the template selects a native communication protocol.

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

## Limitations

Some Go/Rust transports depend on runtime ecosystems that do not have a portable standard Lua implementation. gRPC, WebRTC and WebSocket are therefore extension points rather than fake implementations. This prevents silently claiming protocol compatibility while using an incompatible wire format.
