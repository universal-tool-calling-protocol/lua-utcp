#!/usr/bin/env python3
"""Start the complete local UTCP playground, run examples, then clean up."""
import pathlib
import socket
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
SERVERS = ROOT / "examples" / "servers" / "run.py"

PORTS = [
    ("HTTP", "127.0.0.1", 8080),
    ("SSE", "127.0.0.1", 8090),
    ("Streamable HTTP", "127.0.0.1", 8091),
    ("GraphQL", "127.0.0.1", 8092),
    ("MCP", "127.0.0.1", 8093),
    ("TCP", "127.0.0.1", 9000),
    ("UDP", "127.0.0.1", 9001),
]

EXAMPLES = [
    "examples/manual.lua",
    "examples/text.lua",
    "examples/cli.lua",
    "examples/guard.lua",
    "examples/codemode.lua",
    "examples/http.lua",
    "examples/sse.lua",
    "examples/streamable_http.lua",
    "examples/tcp.lua",
    "examples/udp.lua",
    "examples/graphql.lua",
    "examples/mcp.lua",
]


def wait_for_ports(timeout=10.0):
    deadline = time.monotonic() + timeout
    pending = list(PORTS)
    while pending and time.monotonic() < deadline:
        remaining = []
        for name, host, port in pending:
            try:
                with socket.create_connection((host, port), timeout=0.2):
                    pass
            except OSError:
                remaining.append((name, host, port))
        pending = remaining
        if pending:
            time.sleep(0.1)
    if pending:
        names = ", ".join(f"{name}:{port}" for name, _, port in pending)
        raise RuntimeError(f"timed out waiting for example servers: {names}")


def main():
    lua = sys.argv[1] if len(sys.argv) > 1 else "lua"
    server = subprocess.Popen([sys.executable, str(SERVERS), "all"])
    try:
        print("Starting local UTCP servers...")
        wait_for_ports()
        print("All UTCP servers are ready. Running examples...\n")
        env = dict(__import__("os").environ)
        env["LUA_PATH"] = f"{ROOT / 'lua' / '?.lua'};{ROOT / 'lua' / '?/init.lua'};;"
        for relative in EXAMPLES:
            print(f"=== {relative} ===")
            completed = subprocess.run([lua, str(ROOT / relative)], cwd=ROOT, env=env)
            if completed.returncode != 0:
                return completed.returncode
            print()
        return 0
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
        print("Local UTCP servers stopped.")


if __name__ == "__main__":
    raise SystemExit(main())
