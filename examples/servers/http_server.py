#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os

HOST = '127.0.0.1'
PORT = int(os.environ.get('UTCP_HTTP_PORT', '8080'))


class Handler(BaseHTTPRequestHandler):
    def _json(self, value, code=200, content_type='application/json'):
        data = json.dumps(value).encode()
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except BrokenPipeError:
            pass

    def do_POST(self):
        try:
            n = int(self.headers.get('Content-Length', '0'))
            raw = self.rfile.read(n)
            body = json.loads(raw or b'{}')
        except json.JSONDecodeError as exc:
            self._json({'error': f'invalid JSON: {exc}'}, 400)
            return

        if not isinstance(body, dict):
            self._json({'error': 'request body must be a JSON object'}, 400)
            return

        if self.path == '/echo':
            self._json({'message': body.get('message', '')})
            return

        if self.path in ('/add', '/multiply'):
            a = body.get('a', 0)
            b = body.get('b', 0)

            if not isinstance(a, (int, float)) or isinstance(a, bool):
                self._json({'error': 'a must be a number'}, 400)
                return
            if not isinstance(b, (int, float)) or isinstance(b, bool):
                self._json({'error': 'b must be a number'}, 400)
                return

            value = a + b if self.path == '/add' else a * b
            self._json({'result': value})
            return

        self._json({'error': 'not found'}, 404)

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    print(f'HTTP provider listening on http://{HOST}:{PORT}')
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
