"""文件夹扫描、文件属性与废纸篓操作。"""

import os
import re
import shutil
import subprocess
from pathlib import Path

from .config import IMAGE_EXTENSIONS, SIPS, inside_roots

_NUMBER = re.compile(r"(\d+)")


def natural_key(text: str):
    return [int(part) if part.isdigit() else part.casefold() for part in _NUMBER.split(text)]


def is_image(path: Path) -> bool:
    return path.suffix.lower() in IMAGE_EXTENSIONS


def resolve_folder(raw: str | None, roots: list[Path], fallback: Path) -> Path:
    if not raw:
        return fallback.resolve()
    candidate = Path(raw).expanduser()
    if not candidate.is_absolute():
        raise ValueError("请提供完整的文件夹路径")
    try:
        resolved = candidate.resolve()
    except OSError as error:
        raise ValueError(f"无法读取该路径：{error.strerror or error}") from error
    if not inside_roots(resolved, roots):
        raise PermissionError("只能打开允许范围内的文件夹")
    if not resolved.is_dir():
        raise NotADirectoryError("该路径不是文件夹")
    return resolved


def resolve_image(raw: str, roots: list[Path]) -> Path:
    if not raw:
        raise ValueError("缺少图片路径")
    candidate = Path(raw).expanduser()
    if not candidate.is_absolute():
        raise ValueError("请提供完整的图片路径")
    try:
        resolved = candidate.resolve()
    except OSError as error:
        raise ValueError(f"无法读取该路径：{error.strerror or error}") from error
    if not inside_roots(resolved, roots):
        raise PermissionError("只能访问允许范围内的文件")
    if not resolved.is_file():
        raise FileNotFoundError("图片不存在或已被移动")
    if not is_image(resolved):
        raise ValueError("该文件不是支持的图片格式")
    return resolved


def scan_folder(folder: Path, rotation_for) -> dict:
    images = []
    folders = []
    with os.scandir(folder) as entries:
        for entry in entries:
            if entry.name.startswith("."):
                continue
            try:
                if entry.is_dir(follow_symlinks=False):
                    folders.append({"name": entry.name, "path": str(Path(entry.path).resolve())})
                    continue
                if not entry.is_file(follow_symlinks=False):
                    continue
            except OSError:
                continue
            path = Path(entry.path)
            if not is_image(path):
                continue
            stat = entry.stat(follow_symlinks=False)
            resolved = str(path.resolve())
            images.append({
                "name": entry.name,
                "path": resolved,
                "size": stat.st_size,
                "mtime": int(stat.st_mtime),
                "rotation": rotation_for(Path(resolved)),
            })
    images.sort(key=lambda item: natural_key(item["name"]))
    folders.sort(key=lambda item: natural_key(item["name"]))
    return {
        "path": str(folder),
        "name": folder.name or str(folder),
        "parent": str(folder.parent) if folder.parent != folder else None,
        "folders": folders,
        "images": images,
        "count": len(images),
    }


def image_info(path: Path, rotation: int) -> dict:
    stat = path.stat()
    width, height = pixel_size(path)
    return {
        "name": path.name,
        "path": str(path),
        "folder": str(path.parent),
        "size": stat.st_size,
        "mtime": int(stat.st_mtime),
        "format": path.suffix.lower().lstrip(".").upper(),
        "width": width,
        "height": height,
        "rotation": rotation,
    }


def pixel_size(path: Path) -> tuple[int | None, int | None]:
    try:
        result = subprocess.run(
            [SIPS, "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
            capture_output=True, text=True, timeout=15,
        )
    except (OSError, subprocess.SubprocessError):
        return None, None
    if result.returncode != 0:
        return None, None
    width = _sips_value(result.stdout, "pixelWidth")
    height = _sips_value(result.stdout, "pixelHeight")
    return width, height


def _sips_value(output: str, key: str) -> int | None:
    for line in output.splitlines():
        if line.strip().startswith(f"{key}:"):
            try:
                return int(line.split(":", 1)[1].strip())
            except ValueError:
                return None
    return None


def move_to_trash(path: Path, trash_dir: Path) -> Path:
    trash_dir.mkdir(parents=True, exist_ok=True)
    target = trash_dir / path.name
    counter = 2
    while target.exists():
        target = trash_dir / f"{path.stem} {counter}{path.suffix}"
        counter += 1
    shutil.move(str(path), str(target))
    return target
