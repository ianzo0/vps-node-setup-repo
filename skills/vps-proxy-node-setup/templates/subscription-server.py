#!/usr/bin/env python3
"""Minimal token-gated subscription file server; no directory listing or logging."""
import argparse
import http.server
import pathlib


def main() -> None:
    parser = argparse.ArgumentParser()
    token_group = parser.add_mutually_exclusive_group(required=True)
    token_group.add_argument("--token")
    token_group.add_argument("--token-file")
    parser.add_argument("--file", required=True)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    source = pathlib.Path(args.file)
    token = args.token
    if args.token_file:
        token = pathlib.Path(args.token_file).read_text(encoding="utf-8").strip()
    if not token:
        parser.error("token must not be empty")

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/" + token or not source.is_file():
                self.send_error(404)
                return
            data = source.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *_):
            return

    http.server.ThreadingHTTPServer((args.bind, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
