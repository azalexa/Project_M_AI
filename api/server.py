import json
import os
import socket
import ssl
import struct
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def check_postgres_tls(host):
    context = ssl.create_default_context()
    with socket.create_connection((host, 5432), timeout=3) as connection:
        connection.sendall(struct.pack("!II", 8, 80877103))
        if connection.recv(1) != b"S":
            raise OSError("PostgreSQL did not accept TLS.")
        with context.wrap_socket(connection, server_hostname=host):
            pass


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/health", "/healthz"):
            self.reply(
                200,
                {
                    "status": "healthy",
                    "service": "mechmaster-api",
                    "environment": os.getenv("MECHMASTER_ENVIRONMENT", "local"),
                },
            )
        elif self.path == "/readyz":
            try:
                check_postgres_tls(os.environ["POSTGRES_HOST"])
            except (OSError, KeyError) as error:
                self.log_error("PostgreSQL connectivity check failed (%s).", type(error).__name__)
                self.reply(503, {"postgres_tls": "unavailable"})
            else:
                self.reply(200, {"postgres_tls": "reachable"})
        else:
            self.reply(404, {"status": "not_found"})

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", int(os.getenv("PORT", "8080"))), Handler).serve_forever()
