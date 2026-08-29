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
    ("HTTP", "127.0.0.1", 8080, "tcp"),
    ("SSE", "127.0.0.1", 8090, "tcp"),
    ("Streamable HTTP", "127.0.0.1", 8091, "tcp"),
    ("GraphQL", "127.0.0.1", 8092, "tcp"),
    ("MCP", "127.0.0.1", 8093, "tcp"),
    ("TCP", "127.0.0.1", 9000, "tcp"),
    ("UDP", "127.0.0.1", 9001, "udp"),
]

EXAMPLES = [
    "examples/manual.lua",
    "examples/text.lua",
    "examples/cli.lua",
    # guard.lua deliberately requests interactive human approval; run it via
    # `make example-guard` rather than from this non-interactive playground.
    "examples/codemode.lua",
    "examples/auth_metadata.lua",
    "examples/http.lua",
    "examples/auth_http.lua",
    "examples/sse.lua",
    "examples/streamable_http.lua",
    "examples/tcp.lua",
    "examples/udp.lua",
    "examples/graphql.lua",
    "examples/mcp.lua",
]


def server_is_ready(host, port, protocol):
    if protocol == "udp":
        # UDP has no connection handshake. The bundled server echoes a JSON
        # request, so require a response instead of incorrectly probing it via
        # TCP as earlier versions of this runner did.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.settimeout(0.2)
            probe.sendto(b"{}", (host, port))
            probe.recvfrom(1024)
        return True

    with socket.create_connection((host, port), timeout=0.2):
        return True


def wait_for_ports(timeout=10.0):
    deadline = time.monotonic() + timeout
    pending = list(PORTS)
    while pending and time.monotonic() < deadline:
        remaining = []
        for name, host, port, protocol in pending:
            try:
                server_is_ready(host, port, protocol)
            except OSError:
                remaining.append((name, host, port, protocol))
        pending = remaining
        if pending:
            time.sleep(0.1)
    if pending:
        names = ", ".join(f"{name}:{port}" for name, _, port, _ in pending)
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
