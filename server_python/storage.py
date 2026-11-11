"""Armazenamento persistente do servidor (contas, personagens, sessões, estado do mundo, social).

O servidor guarda cinco documentos JSON (`accounts`, `characters`, `sessions`, `world_state`, `social`). Este módulo
decide ONDE ficam, sem mudar o resto do servidor:

  file:<pasta>        ficheiros JSON (omissão: server_python/data) — desenvolvimento local, VPS com disco próprio
  sqlite:<ficheiro>   um ficheiro SQLite — local / testes
  postgres://…        PostgreSQL (DATABASE_URL) — produção em hosts cujo disco é apagado a cada reinício (Render, Railway…)

Escolha: ANGOLA_STORAGE, senão DATABASE_URL, senão file:server_python/data.
Só se escrevem documentos que mudaram. Falhar a LER é fatal (nunca se arranca vazio por cima de dados existentes).

Migrar dados locais para a base de dados:
    python server_python/storage.py copy file:server_python/data "$DATABASE_URL"
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys
import threading
import time
from pathlib import Path

DOCS = ("accounts", "characters", "sessions", "world_state", "social")
DEFAULT_DIR = Path(__file__).parent / "data"
TABLE = "angola_docs"


class StorageError(RuntimeError):
    pass


def dumps(doc: dict) -> str:
    return json.dumps(doc, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


class Store:
    kind = "?"

    def __init__(self) -> None:
        self._last: dict[str, str] = {}
        self._lock = threading.Lock()

    # --- interface pública
    def load(self, name: str) -> dict:
        raw = self._read(name)
        if raw is None:
            return {}
        try:
            doc = json.loads(raw)
        except ValueError as e:
            raise StorageError(f"documento '{name}' ilegível em {self.describe()}: {e}") from e
        if not isinstance(doc, dict):
            raise StorageError(f"documento '{name}' não é um objeto JSON")
        self._last[name] = dumps(doc)
        return doc

    def changed(self, docs: dict[str, dict]) -> dict[str, str]:
        """Serializa (no thread principal — os dicts mudam entretanto) e devolve só o que mudou."""
        out = {}
        for name, doc in docs.items():
            s = dumps(doc)
            if self._last.get(name) != s:
                out[name] = s
        return out

    def write(self, serialized: dict[str, str]) -> None:
        if not serialized:
            return
        with self._lock:
            self._write(serialized)
            self._last.update(serialized)

    def save(self, docs: dict[str, dict]) -> int:
        ch = self.changed(docs)
        self.write(ch)
        return len(ch)

    def describe(self) -> str:
        return self.kind

    @property
    def durable_on_ephemeral_hosts(self) -> bool:
        return False

    # --- a implementar
    def _read(self, name: str) -> str | None:
        raise NotImplementedError

    def _write(self, serialized: dict[str, str]) -> None:
        raise NotImplementedError


class FileStore(Store):
    kind = "file"

    def __init__(self, folder: str | os.PathLike) -> None:
        super().__init__()
        self.dir = Path(folder)
        self.dir.mkdir(parents=True, exist_ok=True)

    def describe(self) -> str:
        return f"file:{self.dir}"

    def _read(self, name: str) -> str | None:
        p = self.dir / f"{name}.json"
        return p.read_text(encoding="utf-8") if p.exists() else None

    def _write(self, serialized: dict[str, str]) -> None:
        for name, s in serialized.items():
            p = self.dir / f"{name}.json"
            tmp = p.with_suffix(".tmp")
            tmp.write_text(json.dumps(json.loads(s), ensure_ascii=False, indent=2), encoding="utf-8")
            os.replace(tmp, p)


class SqliteStore(Store):
    kind = "sqlite"

    def __init__(self, path: str) -> None:
        super().__init__()
        self.path = path
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.execute(f"CREATE TABLE IF NOT EXISTS {TABLE} (name TEXT PRIMARY KEY, data TEXT NOT NULL, updated_at REAL NOT NULL)")
        self.db.commit()

    def describe(self) -> str:
        return f"sqlite:{self.path}"

    def _read(self, name: str) -> str | None:
        row = self.db.execute(f"SELECT data FROM {TABLE} WHERE name = ?", (name,)).fetchone()
        return row[0] if row else None

    def _write(self, serialized: dict[str, str]) -> None:
        now = time.time()
        with self.db:      # uma transação para todos os documentos
            self.db.executemany(f"INSERT INTO {TABLE} (name, data, updated_at) VALUES (?, ?, ?) "
                                f"ON CONFLICT(name) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at",
                                [(n, s, now) for n, s in serialized.items()])


class PostgresStore(Store):
    kind = "postgres"

    def __init__(self, url: str) -> None:
        super().__init__()
        try:
            import psycopg  # noqa: F401
        except ImportError as e:
            raise StorageError("DATABASE_URL definido mas falta o pacote psycopg (pip install -r server_python/requirements.txt)") from e
        self.url = url
        self.conn = None
        self._connect()
        with self.conn.cursor() as cur:
            cur.execute(f"CREATE TABLE IF NOT EXISTS {TABLE} (name TEXT PRIMARY KEY, data JSONB NOT NULL, "
                        f"updated_at TIMESTAMPTZ NOT NULL DEFAULT now())")

    def describe(self) -> str:
        host = self.url.split("@")[-1].split("/")[0] if "@" in self.url else "?"
        return f"postgres:{host}"          # nunca imprimir a palavra-passe

    @property
    def durable_on_ephemeral_hosts(self) -> bool:
        return True

    def _connect(self) -> None:
        import psycopg
        if self.conn is not None:
            try:
                self.conn.close()
            except Exception:
                pass
        self.conn = psycopg.connect(self.url, autocommit=True, connect_timeout=15)

    def _retry(self, fn):
        """Bases de dados geridas (Neon, Render…) fecham ligações paradas: religa uma vez."""
        import psycopg
        try:
            return fn()
        except (psycopg.OperationalError, psycopg.InterfaceError):
            self._connect()
            return fn()

    def _read(self, name: str) -> str | None:
        def q():
            with self.conn.cursor() as cur:
                cur.execute(f"SELECT data::text FROM {TABLE} WHERE name = %s", (name,))
                row = cur.fetchone()
                return row[0] if row else None
        return self._retry(q)

    def _write(self, serialized: dict[str, str]) -> None:
        def q():
            with self.conn.transaction():
                with self.conn.cursor() as cur:
                    cur.executemany(f"INSERT INTO {TABLE} (name, data, updated_at) VALUES (%s, %s::jsonb, now()) "
                                    f"ON CONFLICT (name) DO UPDATE SET data = excluded.data, updated_at = now()",
                                    list(serialized.items()))
        self._retry(q)


def open_store(spec: str | None = None) -> Store:
    spec = spec or os.environ.get("ANGOLA_STORAGE") or os.environ.get("DATABASE_URL") or ""
    if spec.startswith(("postgres://", "postgresql://")):
        return PostgresStore(spec)
    if spec.startswith("sqlite:"):
        return SqliteStore(spec[len("sqlite:"):].removeprefix("//"))
    if spec.startswith("file:"):
        return FileStore(spec[len("file:"):])
    if spec:
        raise StorageError(f"ANGOLA_STORAGE/DATABASE_URL não reconhecido: {spec.split(':')[0]}:…")
    return FileStore(os.environ.get("ANGOLA_DATA_DIR") or DEFAULT_DIR)


def _cli(argv: list[str]) -> int:
    if len(argv) == 3 and argv[0] == "copy":
        src, dst = open_store(argv[1]), open_store(argv[2])
        docs = {n: src.load(n) for n in DOCS}
        dst.write({n: dumps(d) for n, d in docs.items() if d})
        print(f"copiado {src.describe()} -> {dst.describe()}: " + ", ".join(f"{n}={len(d)}" for n, d in docs.items()))
        return 0
    if len(argv) == 2 and argv[0] == "info":
        st = open_store(argv[1])
        for n in DOCS:
            print(f"{n}: {len(st.load(n))} entradas")
        return 0
    print(__doc__)
    print("uso: storage.py copy <origem> <destino>   |   storage.py info <armazenamento>")
    return 2


if __name__ == "__main__":
    sys.exit(_cli(sys.argv[1:]))
