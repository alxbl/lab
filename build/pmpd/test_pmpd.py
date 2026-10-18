"""Run with: python3 -m unittest build/pmpd/test_pmpd.py (requires `requests`)."""
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs

PMPD = Path(__file__).with_name('pmpd.py')
MAPPED_PORT = 5555


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class FakeGluetunAndQbt(BaseHTTPRequestHandler):
    """Serves the gluetun control server and qbt WebUI endpoints pmpd uses."""

    updates = []
    updated = threading.Event()

    def log_message(self, *args):
        pass

    def _reply(self, body):
        body = body.encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/v1/portforward':
            self._reply(json.dumps({'port': MAPPED_PORT}))
        elif self.path == '/api/v2/app/preferences':
            self._reply(json.dumps({'listen_port': 1}))

    def do_POST(self):
        body = self.rfile.read(int(self.headers['Content-Length'])).decode()
        if self.path == '/api/v2/auth/login':
            self._reply('Ok.')
        elif self.path == '/api/v2/app/setPreferences':
            type(self).updates.append(json.loads(parse_qs(body)['json'][0]))
            type(self).updated.set()
            self._reply('')


class PmpdStartupRaceTest(unittest.TestCase):
    def setUp(self):
        FakeGluetunAndQbt.updates = []
        FakeGluetunAndQbt.updated.clear()
        self.port = free_port()
        self.config = tempfile.NamedTemporaryFile('w', suffix='.toml', delete=False)
        self.config.write('username = "u"\npassword = "p"\n')
        self.config.close()
        url = f'http://127.0.0.1:{self.port}'
        self.proc = subprocess.Popen(
            [sys.executable, '-u', str(PMPD)],
            env={**os.environ, 'GLUETUN_CONFIG_PATH': self.config.name,
                 'GLUETUN_API_URL': url, 'QBT_WEBUI_URL': url,
                 'QBT_WEBUI_PASSWORD': 'x', 'PMPD_RETRY_SECONDS': '0.2'},
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    def tearDown(self):
        self.proc.kill()
        self.proc.stdout.close()
        os.unlink(self.config.name)

    def test_retries_until_services_are_up_then_syncs_port(self):
        # Nothing is listening yet: pmpd must survive and keep retrying.
        self.assertIsNone(self._wait_exit(1.5), 'pmpd exited while services were down')

        server = HTTPServer(('127.0.0.1', self.port), FakeGluetunAndQbt)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            self.assertTrue(FakeGluetunAndQbt.updated.wait(10), 'listen port never updated')
        finally:
            server.shutdown()
            server.server_close()

        self.assertEqual(FakeGluetunAndQbt.updates[0]['listen_port'], MAPPED_PORT)
        self.proc.kill()
        self.assertIn('retrying', self.proc.stdout.read())

    def _wait_exit(self, timeout):
        try:
            return self.proc.wait(timeout)
        except subprocess.TimeoutExpired:
            return None


if __name__ == '__main__':
    unittest.main()
