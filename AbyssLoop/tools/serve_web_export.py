#!/usr/bin/env python3
"""Serve an exported Abyss Loop Web build locally with correct WASM MIME type."""
from __future__ import annotations

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys


class WebExportHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript; charset=utf-8",
    }

    def log_message(self, format: str, *args: object) -> None:  # noqa: A003
        sys.stderr.write((format % args) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path("../AbyssLoop_WebExport"), help="Folder with exported index.html/.js/.wasm/.pck")
    parser.add_argument("--host", default="127.0.0.1", help="Defaults to localhost to avoid exposing the dev server to the network")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()
    root = args.directory.expanduser().resolve()
    required = [root / "index.html", root / "index.js", root / "index.wasm", root / "index.pck"]
    missing = [path.name for path in required if not path.is_file() or path.stat().st_size == 0]
    if missing:
        print("ERROR: Web export is incomplete; missing or empty: " + ", ".join(missing), file=sys.stderr)
        print("Run tools/export_web.sh or export a Web preset to index.html first.", file=sys.stderr)
        return 2
    handler = partial(WebExportHandler, directory=str(root))
    server = ThreadingHTTPServer((args.host, args.port), handler)
    host, port = server.server_address[:2]
    print(f"Abyss Loop Web preview: http://{host}:{port}/")
    print(f"Serving: {root}")
    print("Press Ctrl+C to stop. For the automated smoke test, use tools/web_browser_smoke_test.py.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping Web preview.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
