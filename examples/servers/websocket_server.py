#!/usr/bin/env python3
"""Small dependency-free WebSocket text echo server for the Lua example."""
import base64
import hashlib
import os
import socketserver
import struct

HOST = "127.0.0.1"
PORT = int(os.environ.get("UTCP_WEBSOCKET_PORT", "8765"))
MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def read_exact(stream, size):
    data = bytearray()
    while len(data) < size:
        chunk = stream.read(size - len(data))
        if not chunk:
            return None
        data.extend(chunk)
    return bytes(data)


def read_frame(stream):
    head = read_exact(stream, 2)
    if not head:
        return None, None
    opcode = head[0] & 0x0F
    masked = bool(head[1] & 0x80)
    length = head[1] & 0x7F
    if length == 126:
        length = struct.unpack("!H", read_exact(stream, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", read_exact(stream, 8))[0]
    mask = read_exact(stream, 4) if masked else None
    payload = read_exact(stream, length) or b""
    if mask:
        payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    return opcode, payload


def write_frame(stream, opcode, payload=b""):
    head = bytes((0x80 | opcode,))
    length = len(payload)
    if length < 126:
        head += bytes((length,))
    elif length < 65536:
        head += bytes((126,)) + struct.pack("!H", length)
    else:
        head += bytes((127,)) + struct.pack("!Q", length)
    stream.write(head + payload)
    stream.flush()


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        request_line = self.rfile.readline().decode("latin-1").strip()
        if not request_line:
            return
        headers = {}
        while True:
            line = self.rfile.readline().decode("latin-1")
            if line in ("\r\n", "\n", ""):
                break
            key, _, value = line.partition(":")
            headers[key.strip().lower()] = value.strip()

        key = headers.get("sec-websocket-key")
        if not key:
            return
        accept = base64.b64encode(hashlib.sha1((key + MAGIC).encode()).digest()).decode()
        self.wfile.write(
            (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
            ).encode("latin-1")
        )
        self.wfile.flush()

        while True:
            opcode, payload = read_frame(self.rfile)
            if opcode is None:
                return
            if opcode == 0x8:
                write_frame(self.wfile, 0x8, payload)
                return
            if opcode == 0x9:
                write_frame(self.wfile, 0xA, payload)
            elif opcode in (0x1, 0x2):
                write_frame(self.wfile, opcode, payload)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True


if __name__ == "__main__":
    print(f"WebSocket echo server listening on ws://{HOST}:{PORT}")
    Server((HOST, PORT), Handler).serve_forever()
