import re
from pathlib import Path

STATIC = Path(__file__).resolve().parent.parent / "app" / "static"

EMOJI = re.compile("[\U0001F300-\U0001FAFF\u2600-\u26FF\u2700-\u27BF]")


def test_page_serves_the_viewer_shell(app_client):
    response = app_client.get("/")
    assert response.status_code == 200
    assert "照片查看器" in response.text
    assert "打开文件夹" in response.text


def test_static_assets_load(app_client):
    assert app_client.get("/style.css").status_code == 200
    assert app_client.get("/app.js").status_code == 200
    assert app_client.get("/favicon.svg").status_code == 200
    html = app_client.get("/").text
    for asset in ["/style.css", "/app.js", "/favicon.svg"]:
        assert asset in html, asset


def test_required_elements_exist(app_client):
    html = (STATIC / "index.html").read_text()
    for element_id in [
        "library", "viewer", "grid", "pager", "stage", "photo",
        "prev-button", "next-button", "zoom-slider", "zoom-out", "zoom-in",
        "zoom-label", "counter", "window-title",
        "fit-button", "rotate-left", "rotate-right", "delete-button",
        "confirm-dialog", "confirm-delete", "slideshow", "slideshow-photo",
    ]:
        assert f'id="{element_id}"' in html, element_id
    assert 'aria-label="上一张"' in html
    assert 'aria-label="下一张"' in html


def test_styles_keep_text_readable():
    css = (STATIC / "style.css").read_text()
    sizes = [int(value) for value in re.findall(r"font-size:\s*(\d+)px", css)]
    assert sizes and min(sizes) >= 13
    assert "font-size: 15px" in css


def test_sources_have_no_emoji():
    for name in ["index.html", "style.css", "app.js"]:
        text = (STATIC / name).read_text()
        assert not EMOJI.search(text), name


def test_page_size_is_thirty_so_more_than_thirty_paginates():
    from app.config import DEFAULT_SETTINGS

    assert DEFAULT_SETTINGS["grid_page_size"] == 30
    script = (STATIC / "app.js").read_text()
    assert "grid_page_size || 30" in script
    assert "第 ${state.page} / ${totalPages} 页" in script


def test_mouse_and_keyboard_wiring():
    script = (STATIC / "app.js").read_text()
    for marker in [
        'addEventListener("wheel"', "zoomAt(", "pointerdown", "pointermove",
        "dblclick", "ArrowLeft", "ArrowRight", "PageUp", "PageDown",
        "Delete", "F11", 'rotate(90)', 'rotate(-90)', "/api/rotation",
        "/api/trash", 'addEventListener("keydown"',
    ]:
        assert marker in script, marker


def test_library_and_viewer_are_wired():
    script = (STATIC / "app.js").read_text()
    for marker in ["/api/folders", "/api/preview", "openFolder", "openViewer", "navigate", "pageNumbers"]:
        assert marker in script, marker
    assert "第 ${state.index + 1} 张 / 共 ${state.images.length} 张" in script
