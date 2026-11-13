from pathlib import Path

from app.store import Store


def test_health(app_client):
    assert app_client.get("/api/health").json()["ok"] is True


def test_startup_returns_defaults_and_folder(app_client):
    payload = app_client.get("/api/startup").json()
    assert payload["settings"]["fit_on_open"] is True
    assert payload["settings"]["slideshow_interval"] == 5
    assert payload["default_folder"]
    assert payload["recent"] == []


def test_folder_listing_is_natural_sorted(app_client):
    payload = app_client.get("/api/folders", params={"path": str(app_client.photos)}).json()
    names = [item["name"] for item in payload["images"]]
    assert names == ["a1.png", "b2.png", "b10.png"]
    assert payload["count"] == 3
    assert payload["name"] == "photos"


def test_folder_listing_records_recent(app_client):
    app_client.get("/api/folders", params={"path": str(app_client.photos)})
    recent = app_client.get("/api/recent").json()["recent"]
    assert recent[0]["name"] == "photos"
    assert recent[0]["exists"] is True


def test_folder_outside_roots_is_refused(app_client, tmp_path: Path):
    outside = tmp_path.parent / "elsewhere"
    outside.mkdir(exist_ok=True)
    response = app_client.get("/api/folders", params={"path": str(outside)})
    assert response.status_code == 403


def test_settings_update_and_validation(app_client):
    updated = app_client.put("/api/settings", json={"background": "black"}).json()
    assert updated["background"] == "black"
    assert app_client.get("/api/settings").json()["background"] == "black"

    bad_value = app_client.put("/api/settings", json={"background": "pink"})
    assert bad_value.status_code == 400
    assert "只能是" in bad_value.json()["detail"]

    bad_key = app_client.put("/api/settings", json={"unknown": True})
    assert bad_key.status_code == 400


def test_settings_persist_across_restart(app_client):
    app_client.put("/api/settings", json={"slideshow_interval": 9})
    store = Store(app_client.data_dir / "viewer.db")
    assert store.settings()["slideshow_interval"] == 9
    store.close()


def test_rotation_is_stored_not_written(app_client):
    image = app_client.photos / "a1.png"
    before = image.read_bytes()
    response = app_client.post("/api/rotation", json={"path": str(image), "angle": 90})
    assert response.json()["rotation"] == 90
    assert image.read_bytes() == before

    payload = app_client.get("/api/folders", params={"path": str(app_client.photos)}).json()
    target = next(item for item in payload["images"] if item["name"] == "a1.png")
    assert target["rotation"] == 90

    invalid = app_client.post("/api/rotation", json={"path": str(image), "angle": 45})
    assert invalid.status_code == 400


def test_image_and_info_are_served(app_client):
    image = app_client.photos / "a1.png"
    response = app_client.get("/api/image", params={"path": str(image)})
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"
    assert len(response.content) > 50

    info = app_client.get("/api/info", params={"path": str(image)}).json()
    assert info["width"] == 8
    assert info["height"] == 6
    assert info["format"] == "PNG"


def test_missing_image_is_404(app_client):
    response = app_client.get("/api/image", params={"path": str(app_client.photos / "none.png")})
    assert response.status_code == 404


def test_preview_cache_reuses_and_invalidates(app_client):
    image = app_client.photos / "b2.png"
    cache = app_client.data_dir / "previews"
    first = app_client.get("/api/preview", params={"path": str(image), "size": 200})
    assert first.status_code == 200
    assert first.headers["content-type"].startswith("image/jpeg")
    files = sorted(cache.glob("*.jpg"))
    assert len(files) == 1

    app_client.get("/api/preview", params={"path": str(image), "size": 200})
    assert sorted(cache.glob("*.jpg")) == files

    image.touch()
    app_client.get("/api/preview", params={"path": str(image), "size": 200})
    assert len(list(cache.glob("*.jpg"))) == 2


def test_remember_recent_can_be_disabled(app_client):
    app_client.put("/api/settings", json={"remember_recent": False})
    app_client.get("/api/folders", params={"path": str(app_client.photos)})
    assert app_client.get("/api/recent").json()["recent"] == []


def test_slideshow_settings_are_validated(app_client):
    saved = app_client.put("/api/settings", json={
        "slideshow_interval": 3,
        "slideshow_theme": "white",
        "slideshow_loop": False,
        "slideshow_shuffle": True,
    }).json()
    assert saved["slideshow_interval"] == 3
    assert saved["slideshow_theme"] == "white"
    assert saved["slideshow_loop"] is False
    assert saved["slideshow_shuffle"] is True

    assert app_client.put("/api/settings", json={"slideshow_theme": "blue"}).status_code == 400
    assert app_client.put("/api/settings", json={"slideshow_interval": 0}).status_code == 400


def test_trash_requires_confirmation_and_moves_file(app_client):
    image = app_client.photos / "b10.png"
    refused = app_client.post("/api/trash", json={"path": str(image)})
    assert refused.status_code == 400
    assert image.exists()

    accepted = app_client.post("/api/trash", json={"path": str(image), "confirm": True})
    assert accepted.status_code == 200
    assert not image.exists()
    assert Path(accepted.json()["trash"]).exists()
    assert Path(accepted.json()["trash"]).parent.name == "trash"


def test_text_file_is_refused(app_client):
    response = app_client.get("/api/image", params={"path": str(app_client.photos / "note.txt")})
    assert response.status_code == 400
