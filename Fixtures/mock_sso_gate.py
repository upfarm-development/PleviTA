#!/usr/bin/env python3
"""A fake SSO gate in front of mock_server.py.

Stands in for Pangolin (or any reverse proxy doing cookie/redirect SSO) so the
in-app browser login can be exercised without a real one. It reproduces the
behaviour that actually broke a TestFlight build:

  * With no session cookie, *every* path — `/api/` included — is answered
    `200 text/html` with a login page. Not a 401, not a redirect to a JSON
    error: a page, at an API path, with a success status. That is what made
    the app say "Couldn't understand the server's response", and it is what
    `TAClient.looksLikeWebPage` now catches.
  * Signing in sets a session cookie, after which every request is proxied
    straight through to the real mock server.

Run both, then point the app at the gate:

    python3 Fixtures/mock_server.py 8081
    python3 Fixtures/mock_sso_gate.py 8099 8081

The login page has no password on purpose — the app is the thing under test,
not the identity provider. Any credentials are accepted.
"""

from __future__ import annotations

import http.cookies
import http.server
import sys
import urllib.error
import urllib.request

SESSION_COOKIE = "gate_session"
SESSION_VALUE = "let-me-in"

LOGIN_PAGE = """<!DOCTYPE html>
<html>
<head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Sign in</title></head>
<body style="font-family: -apple-system, sans-serif; margin: 3rem 1.5rem; text-align: center;">
  <h1 style="font-size: 1.5rem;">Mock SSO Gate</h1>
  <p style="color: #666;">Standing in for Pangolin. Any credentials work.</p>
  <form method="POST" action="/__gate/login" style="margin-top: 2rem;">
    <input name="username" placeholder="Username" value="tester"
           style="display:block; width:100%; max-width:320px; margin:0 auto .75rem; padding:.9rem; font-size:1rem;">
    <input name="password" type="password" placeholder="Password" value="hunter2"
           style="display:block; width:100%; max-width:320px; margin:0 auto 1.25rem; padding:.9rem; font-size:1rem;">
    <button type="submit"
            style="padding:.9rem 2.5rem; font-size:1rem; background:#0a84ff; color:#fff; border:0; border-radius:8px;">
      Sign In
    </button>
  </form>
</body>
</html>
"""


class GateHandler(http.server.BaseHTTPRequestHandler):
    upstream_port = 8081

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        sys.stderr.write("mock_sso_gate: " + (format % args) + "\n")

    # -- session ---------------------------------------------------------
    def _has_session(self) -> bool:
        raw = self.headers.get("Cookie")
        if not raw:
            return False
        jar = http.cookies.SimpleCookie()
        jar.load(raw)
        morsel = jar.get(SESSION_COOKIE)
        return morsel is not None and morsel.value == SESSION_VALUE

    def _send_login_page(self) -> None:
        body = LOGIN_PAGE.encode()
        # 200, not 401 — the whole point. A gate that answered 401 with JSON
        # would be indistinguishable from Tube Archivist's own 401.
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # -- proxying --------------------------------------------------------
    def _proxy(self, method: str) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        payload = self.rfile.read(length) if length else None

        url = f"http://127.0.0.1:{self.upstream_port}{self.path}"
        request = urllib.request.Request(url=url, data=payload, method=method)
        for header in ("Authorization", "Content-Type", "Accept", "Cookie"):
            value = self.headers.get(header)
            if value:
                request.add_header(header, value)

        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                body = response.read()
                self.send_response(response.status)
                for key, value in response.headers.items():
                    if key.lower() in ("transfer-encoding", "content-length", "connection"):
                        continue
                    self.send_header(key, value)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        except urllib.error.HTTPError as error:
            body = error.read()
            self.send_response(error.code)
            for key, value in error.headers.items():
                if key.lower() in ("transfer-encoding", "content-length", "connection"):
                    continue
                self.send_header(key, value)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as exc:  # upstream down
            self.send_response(502)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(f"upstream unreachable: {exc}".encode())

    # -- verbs -----------------------------------------------------------
    def do_GET(self) -> None:  # noqa: N802
        if not self._has_session():
            self._send_login_page()
            return
        self._proxy("GET")

    def do_POST(self) -> None:  # noqa: N802
        if self.path == "/__gate/login":
            length = int(self.headers.get("Content-Length") or 0)
            self.rfile.read(length)
            self.send_response(303)
            # HttpOnly, like a real gate's session cookie — which is also why
            # the app has to read it out of WKWebView's own cookie store
            # rather than from JavaScript.
            self.send_header("Set-Cookie", f"{SESSION_COOKIE}={SESSION_VALUE}; Path=/; HttpOnly")
            self.send_header("Location", "/")
            self.end_headers()
            return
        if not self._has_session():
            self._send_login_page()
            return
        self._proxy("POST")

    def do_DELETE(self) -> None:  # noqa: N802
        if not self._has_session():
            self._send_login_page()
            return
        self._proxy("DELETE")


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
    GateHandler.upstream_port = int(sys.argv[2]) if len(sys.argv) > 2 else 8081
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), GateHandler)
    print(f"mock_sso_gate: http://127.0.0.1:{port} -> 127.0.0.1:{GateHandler.upstream_port}", file=sys.stderr)
    server.serve_forever()


if __name__ == "__main__":
    main()
