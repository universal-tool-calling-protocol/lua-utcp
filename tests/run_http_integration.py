#!/usr/bin/env python3
"""Run the Lua HTTP integration test against the bundled example server."""

import os
import shlex
import socket
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / "examples" / "servers" / "http_server.py"


def unused_local_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def server_is_ready(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.1):
            return True
    except OSError:
        return False


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: run_http_integration.py <lua>", file=sys.stderr)
        return 2

    port = unused_local_port()
    env = os.environ.copy()
    env["UTCP_HTTP_PORT"] = str(port)
    server = subprocess.Popen(
        [sys.executable, str(SERVER)],
        cwd=ROOT,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if server.poll() is not None:
                stderr = server.stderr.read() if server.stderr else ""
                print(f"HTTP example server exited early: {stderr}", file=sys.stderr)
                return server.returncode or 1
            if server_is_ready(port):
                break
            time.sleep(0.05)
        else:
            print("HTTP example server did not start within 5 seconds", file=sys.stderr)
            return 1

        test_env = env.copy()
        test_env["UTCP_HTTP_URL"] = f"http://127.0.0.1:{port}/echo"
        return subprocess.run(
            [*shlex.split(sys.argv[1]), "tests/test_http.lua"], cwd=ROOT, env=test_env
        ).returncode
    finally:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()


if __name__ == "__main__":
    raise SystemExit(main())
