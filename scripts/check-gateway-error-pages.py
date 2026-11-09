#!/usr/bin/env python3
"""Exercise rendered Caddy error handlers on loopback, without stopping services."""
import argparse
import http.server
import pathlib
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request


class Upstream(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        status = int(self.path.strip('/'))
        body = b'{"error":"upstream test response"}'
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(body)

    do_POST = do_GET

    def log_message(self, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--caddy', required=True)
    parser.add_argument('--handlers', type=pathlib.Path, required=True)
    parser.add_argument('--proxy', type=pathlib.Path, required=True)
    args = parser.parse_args()
    upstream = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Upstream)
    threading.Thread(target=upstream.serve_forever, daemon=True).start()
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix='flaked-errors-') as directory:
        root = pathlib.Path(directory)
        configuration = root / 'Caddyfile'
        configuration.write_text('''{
 admin off
 auto_https off
 persist_config off
}
http://127.0.0.1:PORT {
HANDLERS
 handle /raised/* {
  error 502
 }
 handle /unreachable {
  reverse_proxy 127.0.0.1:1
 }
 handle {
  reverse_proxy 127.0.0.1:UPSTREAM {
PROXY
  }
 }
}
'''.replace('PORT', str(port)).replace('UPSTREAM', str(upstream.server_port))
            .replace('HANDLERS', args.handlers.read_text())
            .replace('PROXY', args.proxy.read_text()))
        with (root / 'caddy.log').open('w+') as log:
            process = subprocess.Popen([args.caddy, 'run', '--config', str(configuration),
                                        '--adapter', 'caddyfile'], stdout=log, stderr=log)
            try:
                for _ in range(50):
                    if process.poll() is not None:
                        log.seek(0)
                        raise RuntimeError(log.read())
                    try:
                        with socket.create_connection(('127.0.0.1', port), timeout=.1):
                            break
                    except OSError:
                        time.sleep(.1)
                cases = [(f'/{status}', status, 'text/html', 'GET', True)
                         for status in (502, 503, 504)]
                cases += [(f'/{status}', status, 'application/json', 'GET', False)
                          for status in (502, 503, 504)]
                cases += [('/502', 502, 'text/html', 'POST', False),
                          ('/401', 401, 'text/html', 'GET', False),
                          ('/404', 404, 'text/html', 'GET', False),
                          ('/raised/test', 502, 'text/html', 'GET', True),
                          ('/unreachable', 502, 'text/html', 'GET', True),
                          ('/unreachable', 502, 'application/json', 'GET', False)]
                for path, status, accept, method, branded in cases:
                    req = urllib.request.Request(f'http://127.0.0.1:{port}{path}',
                                                 headers={'Accept': accept}, method=method)
                    try:
                        response = urllib.request.urlopen(req, timeout=5)
                    except urllib.error.HTTPError as error:
                        response = error
                    with response:
                        body = response.read().decode()
                        assert response.status == status, (path, response.status)
                        assert ('Taking a little' in body) == branded, (path, accept, method)
                        if branded:
                            assert response.headers['Cache-Control'] == 'no-store'
                            assert "style-src 'unsafe-inline'" in response.headers['Content-Security-Policy']
                        elif path != '/unreachable':
                            assert body == '{"error":"upstream test response"}'
                print(f'PASS {len(cases)} outage, API, POST and authentication-error cases')
            finally:
                process.terminate()
                process.wait(timeout=5)
                upstream.shutdown()
                upstream.server_close()


if __name__ == '__main__':
    main()
