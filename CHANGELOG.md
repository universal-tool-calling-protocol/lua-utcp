# Changelog

## Unreleased

- Add WebSocket calls and streaming over `lua-http`, including persistent
  connections, authentication headers, subprotocols and secure URL checks.
- Add unary and streaming gRPC calls through `Protocol-Lattice/lua-grpc`.
- Add a WebRTC DataChannel transport contract for native or embedded bindings.
- Implement UTCP 1.1 protocol restrictions at registration and dispatch time,
  `manual_call_templates`, qualified tool names, variable loaders, lifecycle
  methods and v0.1 migration helpers.
- Execute complete multi-command CLI templates with working-directory and
  environment support.
- Split the example configuration into independent HTTP calculator and CLI
  filesystem manuals in one UTCP 1.1 file.
- Add examples for WebSocket, bundled gRPC client/server and WebRTC DataChannel
  adapters, including portable smoke execution in the complete playground.

## 1.7.0

- Support structured authentication ownership metadata (`ownership` and OAuth2
  `grant_type`) from UTCP issue #62.
- Add client access to effective auth metadata without introducing credential
  or session state management.
- Expose effective auth metadata through every built-in transport; HTTP-based
  transports apply available OAuth2 credentials as Bearer headers.
- Add runnable examples for auth metadata across all transports and an
  authenticated HTTP call, plus regression coverage for the metadata API.
- Make the local example runner probe UDP correctly and skip the interactive
  Guard example.

## 1.6.0

- Add the HOL Guard command-safety adapter, including an interactive example
  and regression coverage for allow, deny, review, and malformed verdicts.
- Improve the LuaRocks and CI environment setup used by the adapter and test
  suite.

## 1.5.0

- Improve the GraphQL, TCP, UDP, and text transports, including more reliable
  error handling and configuration support.
- Add local HTTP integration coverage and strengthen transport and CLI tests.
- Refresh packaging metadata, documentation, and the safe Guard example.

## 1.4.0

- Add client-side guard evaluation and approval support for tool calls.
- Add provider-qualified tool lookup and stateful transport caching.
- Improve CodeMode isolation and structured execution errors.

## 1.3.0

- Cache constructed transports for repeated tool calls and cache the registry's ordered tool list.
- Cache LuaSocket HTTP dependencies and preserve valid decoded false values from transport responses.
- Improve CLI JSON request handling, including the canonical filesystem examples and regression coverage.
- Add CodeMode OpenRouter repair-loop and README-refactoring examples.

## 1.2.0

- Packaging-only release; this tag contains the same source revision as 1.1.0.

## 1.1.0

- Add the CodeMode error-repair loop and OpenRouter CodeMode examples.
- Preserve typed HTTP template values and improve transport failure and timeout handling.
- Add CI coverage for Lua 5.3 and 5.4, plus HTTP, SSE, and Streamable HTTP reliability tests.

## 1.0.0

- Initial Lua UTCP implementation.
- Canonical manual/tool registry.
- HTTP, SSE, Streamable HTTP, TCP, UDP, CLI, Text, GraphQL and MCP transports.
- JSON backend abstraction.
- Authentication helpers.
- CodeMode-facing registry API.
- LuaRocks packaging.
