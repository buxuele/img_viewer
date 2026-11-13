"""预览缓存：用 macOS 自带 sips 生成缩小图，按路径、大小与修改时间失效。"""

import hashlib
import os
import subprocess
from pathlib import Path

from .config import SIPS


def cache_key(path: Path, max_edge: int) -> str:
    stat = path.stat()
    raw = f"{path.resolve()}|{stat.st_size}|{stat.st_mtime_ns}|{max_edge}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()


def ensure_preview(path: Path, max_edge: int, cache_dir: Path) -> Path:
    cache_dir.mkdir(parents=True, exist_ok=True)
    target = cache_dir / f"{cache_key(path, max_edge)}.jpg"
    if target.is_file() and target.stat().st_size > 0:
        return target
    temporary = cache_dir / f"{target.stem}.part"
    command = [
        SIPS, "-Z", str(max_edge),
        "-s", "format", "jpeg",
        "-s", "formatOptions", "82",
        str(path), "--out", str(temporary),
    ]
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return path
    if result.returncode != 0 or not temporary.is_file():
        temporary.unlink(missing_ok=True)
        return path
    os.replace(temporary, target)
    return target
