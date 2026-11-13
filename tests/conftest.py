import struct
import sys
import zlib
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def write_png(path: Path, width: int = 8, height: int = 6, color=(200, 60, 90)) -> Path:
    rows = b"".join(b"\x00" + bytes(color) * width for _ in range(height))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(
            ">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    payload = b"\x89PNG\r\n\x1a\n"
    payload += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    payload += chunk(b"IDAT", zlib.compress(rows))
    payload += chunk(b"IEND", b"")
    path.write_bytes(payload)
    return path


@pytest.fixture
def photos(tmp_path: Path) -> Path:
    root = tmp_path / "photos"
    root.mkdir()
    write_png(root / "b10.png")
    write_png(root / "b2.png")
    write_png(root / "a1.png")
    (root / "note.txt").write_text("not an image")
    (root / ".hidden.png").write_bytes(b"hidden")
    (root / "album").mkdir()
    return root


@pytest.fixture
def app_client(tmp_path: Path, photos: Path):
    from fastapi.testclient import TestClient

    from app.main import create_app

    data = tmp_path / "data"
    application = create_app(
        data_dir=data,
        allowed_roots=[tmp_path],
        trash_dir=tmp_path / "trash",
        previews_dir=data / "previews",
    )
    with TestClient(application) as client:
        client.data_dir = data
        client.photos = photos
        yield client
