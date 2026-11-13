from pathlib import Path

import pytest

from app.library import is_image, move_to_trash, natural_key, scan_folder


def test_natural_sort_orders_numbers_by_value():
    names = ["图10.jpg", "图2.jpg", "图1.jpg"]
    assert sorted(names, key=natural_key) == ["图1.jpg", "图2.jpg", "图10.jpg"]


def test_image_extensions_are_case_insensitive():
    assert is_image(Path("a.JPG"))
    assert is_image(Path("b.heic"))
    assert not is_image(Path("c.txt"))


def test_scan_folder_lists_only_images_sorted_and_skips_hidden(photos: Path):
    result = scan_folder(photos, lambda path: 90 if path.name == "b2.png" else 0)
    assert [item["name"] for item in result["images"]] == ["a1.png", "b2.png", "b10.png"]
    assert result["count"] == 3
    assert [item["name"] for item in result["folders"]] == ["album"]
    assert result["images"][1]["rotation"] == 90
    assert all(item["path"].startswith(str(photos.resolve())) for item in result["images"])


def test_move_to_trash_never_overwrites(tmp_path: Path):
    source_dir = tmp_path / "source"
    source_dir.mkdir()
    trash = tmp_path / "trash"
    trash.mkdir()
    (trash / "shot.png").write_bytes(b"old")
    source = source_dir / "shot.png"
    source.write_bytes(b"new")

    moved = move_to_trash(source, trash)

    assert not source.exists()
    assert (trash / "shot.png").read_bytes() == b"old"
    assert moved.name == "shot 2.png"
    assert moved.read_bytes() == b"new"
