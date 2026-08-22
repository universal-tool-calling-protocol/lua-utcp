#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        n=int(self.headers.get('Content-Length','0')); body=json.loads(self.rfile.read(n) or b'{}')
        if self.path != '/call': self.send_error(404); return
        result={'result':body.get('value',body)}
        data=json.dumps(result).encode(); self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self,*args): pass
if __name__=='__main__':
    print('Streamable HTTP server listening on http://127.0.0.1:8091/call')
    ThreadingHTTPServer(('127.0.0.1',8091),Handler).serve_forever()
