#!/usr/bin/env python3
"""Serve the persistent viewer and read-only JSON API. Example: x1301-web.py"""
import json, os, sys
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from x1301lib import read_json

RUN=Path(os.environ.get("X1301_RUN", "/run/x1301")); VAR=Path(os.environ.get("X1301_VAR", "/var/lib/x1301")); ROOT=Path(__file__).with_name("web")
ROUTES={"/api/v1/status": RUN/"runtime.json", "/api/v1/devices": VAR/"devices.json", "/api/v1/profiles": VAR/"profiles.d", "/api/v1/ports": VAR/"ports.json", "/api/v1/capabilities": VAR/"capabilities.json"}
class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        route=self.path.split("?",1)[0]
        if route == "/api/v1/stream": return self.reply(read_json(RUN/"runtime.json", {}).get("stream", {}))
        if route in ROUTES:
            target=ROUTES[route]
            data=([read_json(p,{}) for p in sorted(target.glob("*.json"))] if target.is_dir() else read_json(target,{})); return self.reply(data)
        if route == "/": self.path="/index.html"
        return super().do_GET()
    def reply(self,data):
        body=json.dumps(data,indent=2).encode(); self.send_response(200); self.send_header("Content-Type","application/json"); self.send_header("Cache-Control","no-store"); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self,fmt,*args): sys.stderr.write("x1301-web: "+fmt%args+"\n")
def main():
    os.chdir(ROOT); state=read_json(RUN/"runtime.json",{}); port=int(state.get("ports",{}).get("control_http",8080)); ThreadingHTTPServer((os.environ.get("X1301_WEB_BIND","0.0.0.0"),port),Handler).serve_forever()
if __name__ == "__main__": main()
