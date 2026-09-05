#!/bin/sh
set -eu

lua_dir=${LUA_DIR:-}
lua_bin=${LUA_BIN:-}
lua_version=${LUA_VERSION:-5.4}

if [ -z "$lua_bin" ] && [ -x /opt/homebrew/opt/lua@5.4/bin/lua ]; then
  lua_dir=${lua_dir:-/opt/homebrew/opt/lua@5.4}
  lua_bin="$lua_dir/bin/lua"
fi

if [ -z "$lua_bin" ] && command -v lua5.4 >/dev/null 2>&1; then
  lua_bin=$(command -v lua5.4)
fi

if [ -z "$lua_bin" ] && [ -n "$lua_dir" ]; then
  lua_bin="$lua_dir/bin/lua"
fi

if [ -z "$lua_bin" ] || [ ! -x "$lua_bin" ]; then
  echo "Lua $lua_version was not found." >&2
  echo "Set LUA_BIN to the interpreter and optionally LUA_DIR to its prefix." >&2
  exit 1
fi

if [ -z "$lua_dir" ]; then
  resolved_bin=$(command -v "$lua_bin" 2>/dev/null || printf '%s' "$lua_bin")
  lua_dir=$(CDPATH= cd -- "$(dirname "$resolved_bin")/.." && pwd)
fi

eval "$(luarocks --lua-version="$lua_version" --lua-dir="$lua_dir" path)"
exec "$lua_bin" "$@"
