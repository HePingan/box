"""
CORS proxy server for Flutter Web development.

Serves static Flutter web files from build/web/ and proxies
novel API requests via /api-proxy/ to bypass browser CORS restrictions.

Usage: python proxy_server.py [port]
"""

import http.server
import urllib.request
import urllib.error
import json
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
WEB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'web')


class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    """Serves static files and proxies /api-proxy/ requests."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def end_headers(self):
        # Prevent browser caching so fresh builds are loaded
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        super().end_headers()

    def do_GET(self):
        if self.path.startswith('/api-proxy/'):
            print(f'[PROXY] GET {self.path}')
            self._proxy_request('GET')
        else:
            super().do_GET()

    def do_POST(self):
        if self.path.startswith('/api-proxy/'):
            self._proxy_request('POST', self._read_body())
        else:
            super().do_POST()

    def do_OPTIONS(self):
        """Handle CORS preflight for proxy requests."""
        if self.path.startswith('/api-proxy/'):
            self.send_response(200)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', '*')
            self.send_header('Access-Control-Max-Age', '86400')
            self.end_headers()
        else:
            super().do_OPTIONS()

    def _read_body(self):
        length = int(self.headers.get('Content-Length', 0))
        return self.rfile.read(length) if length > 0 else None

    def _proxy_request(self, method, body=None):
        """Forward request to target API server.

        URL format: /api-proxy/{scheme}/{host}/{path}
        Example: /api-proxy/http/api.longchunbajiao.com/search?keyword=test
        """
        try:
            # Parse target from path
            # Strip /api-proxy/ prefix
            remainder = self.path[len('/api-proxy/'):]

            # Extract scheme (http or https)
            slash_idx = remainder.find('/')
            if slash_idx < 0:
                # No path part — use /
                scheme = remainder
                host_and_path = '/'
            else:
                scheme = remainder[:slash_idx]
                host_and_path = remainder[slash_idx:]

            # host_and_path = /api.longchunbajiao.com/search?keyword=test
            # Split host from path
            if host_and_path.startswith('/'):
                host_and_path = host_and_path[1:]

            # Find the first / or ? to split host from path
            end_of_host = len(host_and_path)
            for sep in ['/', '?']:
                idx = host_and_path.find(sep)
                if idx >= 0 and idx < end_of_host:
                    end_of_host = idx

            host = host_and_path[:end_of_host]
            path_and_query = host_and_path[end_of_host:] if end_of_host < len(host_and_path) else '/'

            target_url = f'{scheme}://{host}{path_and_query}'

            # Copy relevant headers
            headers = {}
            skip_headers = {'host', 'connection', 'origin', 'referer',
                            'content-length', 'accept-encoding'}
            for key, value in self.headers.items():
                if key.lower() not in skip_headers:
                    headers[key] = value

            # Try the specified scheme; fall back to HTTP if HTTPS fails
            response = None
            try:
                req = urllib.request.Request(target_url, data=body, headers=headers, method=method)
                response = urllib.request.urlopen(req, timeout=10)
            except Exception as e1:
                if scheme == 'https':
                    # Fall back to HTTP
                    fallback_url = f'http://{host}{path_and_query}'
                    try:
                        req = urllib.request.Request(fallback_url, data=body, headers=headers, method=method)
                        response = urllib.request.urlopen(req, timeout=10)
                    except Exception:
                        raise e1  # Re-raise original error if fallback also fails
                else:
                    raise

            response_body = response.read()
            response_headers = dict(response.headers)

            self.send_response(response.status)
            self.send_header('Access-Control-Allow-Origin', '*')

            for key, value in response_headers.items():
                if key.lower() not in ('transfer-encoding', 'connection', 'content-encoding'):
                    self.send_header(key, value)

            self.end_headers()
            self.wfile.write(response_body)

        except urllib.error.HTTPError as e:
            print(f'[PROXY] HTTP Error {e.code} for {target_url}')
            self.send_response(e.code)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            body = e.read() if e.fp else b''
            self.wfile.write(body)
        except Exception as e:
            print(f'[PROXY] ERROR: {e} for {target_url}')
            self.send_response(502)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}, ensure_ascii=False).encode())


if __name__ == '__main__':
    print(f'Serving {WEB_DIR} on port {PORT}')
    print(f'Proxy endpoint: http://localhost:{PORT}/api-proxy/')
    import socket
    server = None
    try:
        class DualStackServer(http.server.HTTPServer):
            address_family = socket.AF_INET6
            allow_reuse_address = True
            def server_bind(self):
                self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
                super().server_bind()
        server = DualStackServer(('::', PORT), ProxyHandler)
    except Exception:
        server = http.server.HTTPServer(('0.0.0.0', PORT), ProxyHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nShutting down.')
        server.shutdown()
