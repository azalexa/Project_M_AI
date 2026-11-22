import json
import os
import ssl
import unittest
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from threading import Thread
from unittest.mock import patch

from api import server


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.http = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        self.thread = Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.thread.join()

    def get(self, path):
        connection = HTTPConnection("127.0.0.1", self.http.server_port, timeout=3)
        try:
            connection.request("GET", path)
            response = connection.getresponse()
            return response.status, json.loads(response.read())
        finally:
            connection.close()

    def test_health_reports_configured_environment(self):
        with patch.dict(os.environ, {"MECHMASTER_ENVIRONMENT": "prod"}):
            self.assertEqual(self.get("/health"), (200, {
                "status": "healthy",
                "service": "mechmaster-api",
                "environment": "prod",
            }))

    def test_readiness_fails_when_tls_fails(self):
        with patch.dict(os.environ, {"POSTGRES_HOST": "db.example"}):
            with patch.object(server, "check_postgres_tls", side_effect=ssl.SSLError):
                self.assertEqual(self.get("/readyz"), (503, {"postgres_tls": "unavailable"}))

    def test_readiness_succeeds_when_tls_succeeds(self):
        with patch.dict(os.environ, {"POSTGRES_HOST": "db.example"}):
            with patch.object(server, "check_postgres_tls") as probe:
                self.assertEqual(self.get("/readyz"), (200, {"postgres_tls": "reachable"}))
                probe.assert_called_once_with("db.example")


if __name__ == "__main__":
    unittest.main()
