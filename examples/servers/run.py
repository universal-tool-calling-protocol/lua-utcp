#!/usr/bin/env python3
"""Run one or all local UTCP example servers."""
import argparse
import pathlib
import signal
import subprocess
import sys
import time

SERVERS = {
    "http": "http_server.py",
    "sse": "sse_server.py",
    "streamable": "streamable_server.py",
    "graphql": "graphql_server.py",
    "mcp": "mcp_server.py",
    "tcp": "tcp_server.py",
    "udp": "udp_server.py",
}

ROOT = pathlib.Path(__file__).resolve().parent


def run_one(name: str) -> int:
    return subprocess.run([sys.executable, str(ROOT / SERVERS[name])]).returncode


def run_all() -> int:
    processes = [
        subprocess.Popen(
            [sys.executable, str(ROOT / script)],
            stdout=sys.stdout,
            stderr=sys.stderr,
        )
        for script in SERVERS.values()
    ]

    stopping = False

    def stop(*_):
        nonlocal stopping
        if stopping:
            return
        stopping = True
        for process in processes:
            if process.poll() is None:
                process.terminate()
        deadline = time.time() + 3
        while time.time() < deadline:
            if all(p.poll() is not None for p in processes):
                return
            time.sleep(0.05)
        for process in processes:
            if process.poll() is None:
                process.kill()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    try:
        while True:
            exited = [p for p in processes if p.poll() is not None]
            if exited:
                failed = [p.returncode for p in exited if p.returncode not in (0, -signal.SIGTERM, -signal.SIGINT)]
                if failed:
                    stop()
                    return failed[0]
            if stopping:
                return 0
            time.sleep(0.1)
    except KeyboardInterrupt:
        stop()
        return 0
    finally:
        stop()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("server", choices=[*SERVERS, "all"])
    args = parser.parse_args()
    return run_all() if args.server == "all" else run_one(args.server)


if __name__ == "__main__":
    raise SystemExit(main())
