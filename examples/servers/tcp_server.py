#!/usr/bin/env python3
import socket
import json

HOST = '127.0.0.1'
PORT = 9000


def handle_conn(conn):
    buf = b''
    while b'\n' not in buf:
        chunk = conn.recv(4096)
        if not chunk:
            # Peer closed before sending a complete line; nothing to do.
            return
        buf += chunk

    line, _, rest = buf.partition(b'\n')
    # NOTE: any bytes in `rest` (pipelined requests) are discarded;
    # this server handles one request per connection by design.

    try:
        req = json.loads(line or b'{}')
        conn.sendall((json.dumps({'result': req}) + '\n').encode())
    except json.JSONDecodeError as exc:
        conn.sendall((json.dumps({'error': f'invalid JSON: {exc}'}) + '\n').encode())
    except Exception as exc:
        conn.sendall((json.dumps({'error': str(exc)}) + '\n').encode())


with socket.socket() as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, PORT))
    s.listen()
    print(f'TCP server listening on {HOST}:{PORT}')
    while True:
        conn, addr = s.accept()
        with conn:
            try:
                handle_conn(conn)
            except (ConnectionResetError, BrokenPipeError):
                pass
