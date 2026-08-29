LUA ?= lua
# Keep the project sources first, then expose pure-Lua dependencies from the
# active LuaRocks tree. This is evaluated by make because its exported
# LUA_PATH overrides any value set by a calling shell.
LUAROCKS_PATH_ARGS := $(if $(strip $(LUAROCKS_TREE)),--tree="$(LUAROCKS_TREE)")
LUAROCKS_LUA_PATH := $(shell luarocks $(LUAROCKS_PATH_ARGS) path --lr-path 2>/dev/null)
LUA_PATH := ./lua/?.lua;./lua/?/init.lua;$(LUAROCKS_LUA_PATH);;
export LUA_PATH

.PHONY: test examples examples-local integration check zip servers server-http server-sse server-streamable server-tcp server-udp server-graphql server-mcp \
 example-http example-sse example-streamable example-tcp example-udp example-guard example-hol-guard \
 benchmark \
 example-graphql example-mcp example-cli example-text example-codemode example-provider-flow example-provider-codemode \
 example-openrouter-codemode example-openrouter-codemode-chat example-openrouter-codemode-repair

test:
	$(LUA) tests/test_core.lua
	$(LUA) tests/test_codemode.lua
	$(LUA) tests/test_provider_json.lua
	$(LUA) tests/test_client_lookup.lua
	$(LUA) tests/test_mcp.lua
	$(LUA) tests/test_template.lua
	$(LUA) tests/test_transports.lua
	$(LUA) tests/test_cli.lua
	$(LUA) tests/test_hol_guard.lua

examples-local:
	$(LUA) examples/manual.lua
	$(LUA) examples/text.lua
	$(LUA) examples/cli.lua
	$(LUA) examples/guard.lua
	$(LUA) examples/codemode.lua

examples:
	python3 examples/run_examples.py $(LUA)

example-http:
	$(LUA) examples/http.lua
example-sse:
	$(LUA) examples/sse.lua
example-streamable:
	$(LUA) examples/streamable_http.lua
example-tcp:
	$(LUA) examples/tcp.lua
example-udp:
	$(LUA) examples/udp.lua
example-graphql:
	$(LUA) examples/graphql.lua
example-mcp:
	$(LUA) examples/mcp.lua
example-cli:
	$(LUA) examples/cli.lua
example-text:
	$(LUA) examples/text.lua
example-guard:
	$(LUA) examples/guard.lua
example-hol-guard:
	$(LUA) examples/hol_guard.lua
example-codemode:
	$(LUA) examples/codemode.lua
example-provider-flow:
	$(LUA) examples/provider_flow.lua
example-provider-codemode:
	$(LUA) examples/provider_codemode.lua
example-openrouter-codemode:
	$(LUA) examples/openrouter_codemode.lua
example-openrouter-codemode-chat:
	$(LUA) examples/openrouter_codemode_chat.lua
example-openrouter-codemode-repair:
	$(LUA) examples/openrouter_codemode_repair.lua
example-codemode-openrouter-refactor-readme:
	$(LUA) examples/codemode_openrouter_refactor_readme.lua

integration:
	python3 tests/run_http_integration.py "$(LUA)"

check: test integration

benchmark:
	$(LUA) benchmarks/transport_cache.lua

zip:
	zip -qr lua-utcp.zip lua lua-utcp-1.4-1.rockspec lua-utcp-1.4-1.src.rock README.md Makefile tests examples spec LICENSE NOTICE.md CHANGELOG.md

example-provider-test:
	$(LUA) tests/test_provider_json.lua
	$(LUA) tests/test_mcp.lua

example-codemode-test:
	$(LUA) tests/test_codemode.lua
	$(LUA) tests/test_provider_json.lua
	$(LUA) tests/test_mcp.lua

servers:
	python3 examples/servers/run.py all
server-http:
	python3 examples/servers/run.py http
server-sse:
	python3 examples/servers/run.py sse
server-streamable:
	python3 examples/servers/run.py streamable
server-tcp:
	python3 examples/servers/run.py tcp
server-udp:
	python3 examples/servers/run.py udp
server-graphql:
	python3 examples/servers/run.py graphql
server-mcp:
	python3 examples/servers/run.py mcp
