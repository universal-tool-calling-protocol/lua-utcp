# Changelog

## Unreleased

- Support structured authentication ownership metadata (`ownership` and OAuth2
  `grant_type`) from UTCP issue #62.
- Add client access to effective auth metadata without introducing credential
  or session state management.

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
