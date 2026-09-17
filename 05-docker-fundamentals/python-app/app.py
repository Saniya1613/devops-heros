"""Minimal Hello World HTTP server using only the standard library."""
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", "5000"))


class HelloHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = (
            "<!DOCTYPE html><html>"
            "<head><title>Hello World - Python</title></head>"
            "<body><h1>Hello World from Python</h1>"
            f"<p>http.server on port {PORT}, path {self.path}</p>"
            "</body></html>"
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(body.encode())

    def log_message(self, fmt, *args):
        print(f"[python-app] {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"[python-app] listening on 0.0.0.0:{PORT}", flush=True)
    HTTPServer(("0.0.0.0", PORT), HelloHandler).serve_forever()
