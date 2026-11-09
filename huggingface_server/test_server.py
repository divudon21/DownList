"""Local integration tests. Run: python -m unittest discover -s huggingface_server -p 'test_*.py'"""
import io
import json
import os
import socketserver
import tempfile
import threading
import unittest
import zipfile
from http.server import BaseHTTPRequestHandler

from fastapi.testclient import TestClient

import app

PAYLOAD = b'abcdefgh' * 65536


class Handler(BaseHTTPRequestHandler):
    received = None
    def log_message(self, *args):
        pass

    def do_HEAD(self):
        self.send_response(200)
        self.send_header('Content-Length', str(len(PAYLOAD)))
        self.end_headers()

    def do_GET(self):
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/file.mp4')
            self.end_headers()
            return
        if self.path == '/missing':
            self.send_response(404)
            self.end_headers()
            return
        range_header = self.headers.get('Range')
        if range_header:
            a, b = range_header[6:].split('-')
            start, end = int(a), int(b)
            body = PAYLOAD[start:end + 1]
            self.send_response(206)
            self.send_header('Content-Range', f'bytes {start}-{end}/{len(PAYLOAD)}')
        else:
            body = PAYLOAD
            self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Content-Disposition', 'attachment; filename="sample.mp4"')
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers['Content-Length'])
        Handler.received = self.rfile.read(length)
        body = json.dumps({'status': 'ok', 'data': {'downloadPage': 'https://gofile.io/d/Example'}}).encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class ServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        app.DATA_DIR = cls.tmp.name
        app.STATE_FILE = os.path.join(cls.tmp.name, '.tasks_state.json')
        app.ALLOW_PRIVATE_URLS = True
        app.DISK_SAFETY_MARGIN = 0
        app.MIN_SIZE_FOR_PARALLEL = 1000
        cls.server = socketserver.ThreadingTCPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f'http://127.0.0.1:{cls.server.server_address[1]}'
        os.environ['GOFILE_UPLOAD_ENDPOINT'] = cls.base + '/uploadfile'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.tmp.cleanup()

    def setUp(self):
        self.client = TestClient(app.app)
        self.client.__enter__()
        self.client.post('/delete_all')

    def tearDown(self):
        self.client.__exit__(None, None, None)

    def upload(self, name, data):
        r = self.client.post('/upload', files={'file': (name, data)})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()['task_id']

    def test_download_stream_rename_delete_and_reload(self):
        r = self.client.post('/start_download', json={'url': self.base + '/redirect'})
        self.assertEqual(r.status_code, 200, r.text)
        tid = r.json()['task_id']
        task = self.client.get('/status/' + tid).json()
        self.assertEqual(task['status'], 'completed', task)
        self.assertEqual(task['downloaded'], len(PAYLOAD))
        self.assertEqual(self.client.get('/stream/' + tid).content, PAYLOAD)
        self.assertEqual(self.client.head('/stream/' + tid).headers['content-length'], str(len(PAYLOAD)))
        r = self.client.get('/stream/' + tid, headers={'Range': 'bytes=-12'})
        self.assertEqual((r.status_code, r.content), (206, PAYLOAD[-12:]))
        self.assertEqual(self.client.get('/stream/' + tid, headers={'Range': 'bytes=9999999-'}).status_code, 416)
        r = self.client.post('/rename/' + tid, json={'new_name': 'renamed'})
        self.assertEqual(r.json()['task']['original_filename'], 'renamed.mp4')
        app.load_state_on_startup()
        self.assertEqual(self.client.get('/status/' + tid).json()['original_filename'], 'renamed.mp4')
        self.assertEqual(self.client.delete('/delete/' + tid).status_code, 200)
        self.assertEqual(self.client.get('/status/' + tid).status_code, 404)

    def test_gofile_transfer_and_multipart(self):
        r = self.client.post('/start_gofile_transfer', json={'url': self.base + '/file.mp4'})
        tid = r.json()['task_id']
        task = self.client.get('/status/' + tid).json()
        self.assertEqual(task['status'], 'completed', task)
        self.assertEqual(task['gofile_url'], 'https://gofile.io/d/Example')
        self.assertTrue(task['local_deleted'])
        self.assertIn(PAYLOAD, Handler.received)
        self.assertFalse(os.path.exists(task['file_path']))

    def test_zip_and_slip(self):
        for name in ('ok.txt', '../../escape.txt'):
            buffer = io.BytesIO()
            with zipfile.ZipFile(buffer, 'w') as archive:
                archive.writestr(name, 'content')
            tid = self.upload('archive.zip', buffer.getvalue())
            self.assertEqual(self.client.get('/list_zip/' + tid).json()['total_files'], 1)
            self.client.post('/extract_zip/' + tid)
            task = self.client.get('/status/' + tid).json()
            self.assertEqual(task['status'], 'extraction_error' if name.startswith('..') else 'extracted')
            if name == 'ok.txt':
                self.assertEqual(len(self.client.get('/extracted_files/' + tid).json()['files']), 1)

    def test_status_and_private_url_validation(self):
        status = self.client.get('/server_status').json()
        self.assertGreater(status['ram_total'], 0)
        self.assertGreaterEqual(status['uptime_seconds'], 0)
        app.ALLOW_PRIVATE_URLS = False
        try:
            self.assertEqual(self.client.post('/start_download', json={'url': self.base + '/file.mp4'}).status_code, 400)
        finally:
            app.ALLOW_PRIVATE_URLS = True
        tid = self.client.post('/start_download', json={'url': self.base + '/missing'}).json()['task_id']
        self.assertIn('HTTP 404', self.client.get('/status/' + tid).json()['error'])
        self.client.post('/delete_all')
        self.assertEqual(self.client.get('/history').json()['history'], [])


if __name__ == '__main__':
    unittest.main()
