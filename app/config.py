"""应用级常量与路径规则。"""

import os
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent
STATIC_DIR = Path(__file__).resolve().parent / "static"

IMAGE_EXTENSIONS = frozenset({
    ".jpg", ".jpeg", ".jfif", ".png", ".gif", ".bmp", ".webp",
    ".tif", ".tiff", ".heic", ".heif", ".avif",
})

DEFAULT_SETTINGS = {
    "fit_on_open": True,
    "always_show_menu": False,
    "remember_recent": True,
    "wheel_zoom": True,
    "double_click_zoom": True,
    "background": "light",
    "slideshow_interval": 5,
    "slideshow_loop": True,
    "slideshow_shuffle": False,
    "slideshow_theme": "black",
    "grid_page_size": 30,
}

SETTING_CHOICES = {
    "background": ("light", "gray", "black"),
    "slideshow_theme": ("black", "white", "gradient"),
}

DEFAULT_PORT = 8770
SIPS = "/usr/bin/sips"


def default_data_dir() -> Path:
    return APP_ROOT / "data"


def default_allowed_roots() -> list[Path]:
    override = os.environ.get("IMG_VIEWER_ROOTS")
    if override:
        return [Path(item).expanduser().resolve() for item in override.split(os.pathsep) if item]
    roots = [Path.home(), Path("/Volumes")]
    return [root for root in roots if root.exists()]


def default_folder(allowed_roots: list[Path]) -> Path:
    pictures = Path.home() / "Pictures"
    if pictures.is_dir() and inside_roots(pictures, allowed_roots):
        return pictures
    return allowed_roots[0]


def inside_roots(candidate: Path, roots: list[Path]) -> bool:
    target = candidate.resolve()
    for root in roots:
        try:
            target.relative_to(root.resolve())
            return True
        except ValueError:
            continue
    return False
