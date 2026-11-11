"""STAND-IN minimo de `websockets` (RFC6455, texto) APENAS para testes quando o pacote real nao pode ser instalado.
Nao usar em producao. Em producao: pip install -r server_python/requirements.txt"""
import asyncio, base64, hashlib, os, struct
from . import exceptions
from .exceptions import ConnectionClosed
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

class Conn:
    def __init__(self, r, w, mask): self.r, self.w, self.mask, self.closed = r, w, mask, False
    async def _frame(self):
        try:
            h = await self.r.readexactly(2)
            op, ln = h[0] & 15, h[1] & 127
            if ln == 126: ln = struct.unpack(">H", await self.r.readexactly(2))[0]
            elif ln == 127: ln = struct.unpack(">Q", await self.r.readexactly(8))[0]
            key = await self.r.readexactly(4) if h[1] & 128 else None
            data = await self.r.readexactly(ln)
        except (asyncio.IncompleteReadError, ConnectionError): raise ConnectionClosed()
        if key: data = bytes(b ^ key[i % 4] for i, b in enumerate(data))
        return op, data
    async def recv(self):
        while True:
            op, data = await self._frame()
            if op == 1: return data.decode()
            if op == 8: self.closed = True; raise ConnectionClosed()
    def __aiter__(self): return self
    async def __anext__(self):
        try: return await self.recv()
        except ConnectionClosed: raise StopAsyncIteration
    async def send(self, text, op=1):
        if self.closed: raise ConnectionClosed()
        d = text.encode() if isinstance(text, str) else text
        ln = len(d); hdr = bytes([0x80 | op])
        m = 128 if self.mask else 0
        hdr += bytes([m | ln]) if ln < 126 else bytes([m | 126]) + struct.pack(">H", ln)
        if self.mask:
            k = os.urandom(4); d = k and bytes(b ^ k[i % 4] for i, b in enumerate(d)); hdr += k
        self.w.write(hdr + d); await self.w.drain()
    async def close(self, code=1000, reason=""):
        if not self.closed:
            self.closed = True
            try: await self.send(struct.pack(">H", code), 8)
            except Exception: pass
            self.w.close()

class _Serve:
    def __init__(self, handler, host, port): self.handler, self.host, self.port = handler, host, port
    async def __aenter__(self):
        async def cb(r, w):
            req = (await r.readuntil(b"\r\n\r\n")).decode()
            key = [l.split(": ")[1] for l in req.split("\r\n") if l.lower().startswith("sec-websocket-key")][0]
            acc = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
            w.write(f"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {acc}\r\n\r\n".encode()); await w.drain()
            try: await self.handler(Conn(r, w, False))
            finally: w.close()
        self.srv = await asyncio.start_server(cb, self.host, self.port); return self
    async def __aexit__(self, *a): self.srv.close()
def serve(handler, host, port, **kw): return _Serve(handler, host, port)

class _Connect:
    def __init__(self, uri): self.uri = uri
    async def __aenter__(self):
        hp = self.uri.split("//")[1]; h, p = hp.split(":")
        r, w = await asyncio.open_connection(h, int(p))
        w.write(f"GET / HTTP/1.1\r\nHost: {hp}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {base64.b64encode(os.urandom(16)).decode()}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode()); await w.drain()
        await r.readuntil(b"\r\n\r\n"); self.c = Conn(r, w, True); return self.c
    async def __aexit__(self, *a): await self.c.close()
def connect(uri, **kw): return _Connect(uri)
