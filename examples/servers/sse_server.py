#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json, time
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/events': self.send_error(404); return
        self.send_response(200); self.send_header('Content-Type','text/event-stream'); self.send_header('Cache-Control','no-cache'); self.end_headers()
        for i in range(3):
            payload=json.dumps({'sequence':i,'message':f'hello-{i}'})
            self.wfile.write(f'id: {i}\nevent: message\ndata: {payload}\n\n'.encode()); self.wfile.flush(); time.sleep(.1)
    def log_message(self,*args): pass
if __name__=='__main__':
    print('SSE server listening on http://127.0.0.1:8090/events')
    ThreadingHTTPServer(('127.0.0.1',8090),Handler).serve_forever()
