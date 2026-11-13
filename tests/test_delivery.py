from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_just_run_script_covers_startup():
    script = ROOT / "just_run.sh"
    assert script.is_file()
    assert script.stat().st_mode & 0o111
    text = script.read_text()
    for marker in ["PORT=8770", "python3.14", "/api/health", 'open "http://127.0.0.1:$PORT"', "exec "]:
        assert marker in text, marker
    assert "nohup" not in text
    assert "disown" not in text


def test_entry_documents_exist():
    assert (ROOT / "README.md").is_file()
    assert (ROOT / "开发记录.md").is_file()
    assert (ROOT / "docs" / "使用说明.md").is_file()


def test_screenshots_are_recorded():
    shots = sorted((ROOT / "效果图").glob("*.png"))
    assert len(shots) >= 5
    assert all(shot.stat().st_size > 10000 for shot in shots)


def test_site_icons_and_manifest_are_served(app_client):
    for asset in ["/favicon.svg", "/icon-180.png", "/icon-192.png", "/icon-512.png", "/manifest.webmanifest"]:
        response = app_client.get(asset)
        assert response.status_code == 200, asset
    manifest = app_client.get("/manifest.webmanifest").json()
    assert manifest["name"] == "照片查看器"
    assert len(manifest["icons"]) == 2
