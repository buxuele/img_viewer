"""本地照片查看器的 HTTP 服务。"""

import mimetypes
import subprocess
from pathlib import Path

from fastapi import Body, FastAPI, HTTPException, Query
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .config import (
    DEFAULT_PORT, STATIC_DIR, default_allowed_roots, default_data_dir, default_folder,
)
from .library import image_info, move_to_trash, resolve_folder, resolve_image, scan_folder
from .previews import ensure_preview
from .store import Store

mimetypes.add_type("image/heic", ".heic")
mimetypes.add_type("image/heif", ".heif")
mimetypes.add_type("image/avif", ".avif")
mimetypes.add_type("image/tiff", ".tif")
mimetypes.add_type("image/tiff", ".tiff")


def create_app(data_dir: Path | None = None, allowed_roots: list[Path] | None = None,
               trash_dir: Path | None = None, previews_dir: Path | None = None) -> FastAPI:
    data = Path(data_dir) if data_dir else default_data_dir()
    roots = [Path(item).resolve() for item in (allowed_roots or default_allowed_roots())]
    trash = Path(trash_dir) if trash_dir else Path.home() / ".Trash"
    previews = Path(previews_dir) if previews_dir else data / "previews"
    store = Store(data / "viewer.db")

    app = FastAPI(title="照片查看器", docs_url=None, redoc_url=None)
    app.state.store = store
    app.state.allowed_roots = roots
    app.state.trash_dir = trash

    def folder_or_400(raw: str | None) -> Path:
        try:
            return resolve_folder(raw, roots, default_folder(roots))
        except (ValueError, OSError) as error:
            raise failure(error) from error

    def image_or_400(raw: str) -> Path:
        try:
            return resolve_image(raw, roots)
        except (ValueError, OSError) as error:
            raise failure(error) from error

    def failure(error: Exception) -> HTTPException:
        if isinstance(error, PermissionError):
            return HTTPException(status_code=403, detail=str(error))
        if isinstance(error, FileNotFoundError):
            return HTTPException(status_code=404, detail=str(error))
        return HTTPException(status_code=400, detail=str(error))

    def recent_payload(limit: int = 12) -> list[dict]:
        items = []
        for raw in store.recent(limit):
            path = Path(raw)
            items.append({"path": raw, "name": path.name or raw, "exists": path.is_dir()})
        return items

    @app.get("/api/health")
    def health():
        return {"ok": True, "name": "照片查看器"}

    @app.get("/api/startup")
    def startup():
        return {
            "settings": store.settings(),
            "recent": recent_payload(),
            "default_folder": str(default_folder(roots)),
        }

    @app.get("/api/folders")
    def folders(path: str | None = Query(default=None)):
        folder = folder_or_400(path)
        payload = scan_folder(folder, store.rotation)
        if path and store.settings()["remember_recent"]:
            store.touch_recent(folder)
        return payload

    @app.get("/api/image")
    def image(path: str):
        file = image_or_400(path)
        return FileResponse(file, media_type=mimetypes.guess_type(file.name)[0] or "application/octet-stream",
                            headers={"Cache-Control": "no-cache"})

    @app.get("/api/preview")
    def preview(path: str, size: int = Query(default=480, ge=120, le=3200)):
        file = image_or_400(path)
        target = ensure_preview(file, size, previews)
        media = "image/jpeg" if target.suffix.lower() in {".jpg", ".jpeg"} else (
            mimetypes.guess_type(target.name)[0] or "application/octet-stream")
        return FileResponse(target, media_type=media, headers={"Cache-Control": "max-age=300"})

    @app.get("/api/info")
    def info(path: str):
        file = image_or_400(path)
        return image_info(file, store.rotation(file))

    @app.post("/api/rotation")
    def rotation(payload: dict = Body(...)):
        file = image_or_400(str(payload.get("path", "")))
        angle = payload.get("angle")
        if isinstance(angle, bool) or not isinstance(angle, int):
            raise HTTPException(status_code=400, detail="旋转角度必须是整数")
        try:
            saved = store.set_rotation(file, angle)
        except ValueError as error:
            raise failure(error) from error
        return {"path": str(file), "rotation": saved}

    @app.post("/api/trash")
    def delete_to_trash(payload: dict = Body(...)):
        file = image_or_400(str(payload.get("path", "")))
        if payload.get("confirm") is not True:
            raise HTTPException(status_code=400, detail="删除前需要二次确认")
        try:
            moved = move_to_trash(file, trash)
        except OSError as error:
            raise HTTPException(status_code=500, detail=f"删除失败：{error.strerror or error}") from error
        store.forget_rotation(file)
        return {"path": str(file), "trash": str(moved)}

    @app.post("/api/reveal")
    def reveal(payload: dict = Body(...)):
        file = image_or_400(str(payload.get("path", "")))
        subprocess.Popen(["open", "-R", str(file)])
        return {"ok": True}

    @app.post("/api/open")
    def open_file(payload: dict = Body(...)):
        file = image_or_400(str(payload.get("path", "")))
        subprocess.Popen(["open", str(file)])
        return {"ok": True}

    @app.post("/api/wallpaper")
    def wallpaper(payload: dict = Body(...)):
        file = image_or_400(str(payload.get("path", "")))
        script = f'tell application "Finder" to set desktop picture to POSIX file "{file}"'
        result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            raise HTTPException(status_code=500, detail="设置桌面背景失败，请在系统设置里手动选择")
        return {"ok": True}

    @app.get("/api/recent")
    def recent():
        return {"recent": recent_payload()}

    @app.post("/api/recent")
    def add_recent(payload: dict = Body(...)):
        folder = folder_or_400(str(payload.get("path", "")))
        return {"recent": recent_payload() if store.touch_recent(folder) else []}

    @app.delete("/api/recent")
    def clear_recent(path: str | None = Query(default=None)):
        if path:
            store.drop_recent(Path(path))
        return {"recent": recent_payload()}

    @app.post("/api/pick-folder")
    def pick_folder():
        script = 'POSIX path of (choose folder with prompt "选择照片文件夹")'
        result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=300)
        if result.returncode != 0:
            raise HTTPException(status_code=400, detail="没有选择文件夹")
        chosen = result.stdout.strip().rstrip("/")
        if not chosen:
            raise HTTPException(status_code=400, detail="没有选择文件夹")
        folder = folder_or_400(chosen)
        if store.settings()["remember_recent"]:
            store.touch_recent(folder)
        return {"path": str(folder)}

    @app.put("/api/settings")
    def update_settings(payload: dict = Body(...)):
        try:
            return store.settings() if not payload else store.update_settings(payload)
        except ValueError as error:
            raise failure(error) from error

    @app.get("/api/settings")
    def settings():
        return store.settings()

    app.mount("/", StaticFiles(directory=STATIC_DIR, html=True), name="static")
    return app


app = create_app()
