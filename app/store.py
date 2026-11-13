"""SQLite 持久化：选项、旋转角度与最近文件夹。"""

import json
import sqlite3
import time
from pathlib import Path

from .config import DEFAULT_SETTINGS, SETTING_CHOICES


class Store:
    def __init__(self, db_path: Path):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self._create_tables()

    def _create_tables(self) -> None:
        with self.conn:
            self.conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS rotation (
                    path TEXT PRIMARY KEY,
                    angle INTEGER NOT NULL,
                    updated REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS recent (
                    path TEXT PRIMARY KEY,
                    opened REAL NOT NULL
                );
                """
            )

    def close(self) -> None:
        self.conn.close()

    # 选项

    def settings(self) -> dict:
        stored = {}
        for row in self.conn.execute("SELECT key, value FROM settings"):
            stored[row["key"]] = json.loads(row["value"])
        merged = dict(DEFAULT_SETTINGS)
        merged.update({key: value for key, value in stored.items() if key in DEFAULT_SETTINGS})
        return merged

    def update_settings(self, changes: dict) -> dict:
        if not isinstance(changes, dict) or not changes:
            raise ValueError("没有需要保存的选项")
        validated = {key: validate_setting(key, value) for key, value in changes.items()}
        with self.conn:
            for key, value in validated.items():
                self.conn.execute(
                    "INSERT INTO settings(key, value) VALUES(?, ?) "
                    "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                    (key, json.dumps(value)),
                )
        return self.settings()

    # 旋转

    def rotation(self, path: Path) -> int:
        row = self.conn.execute(
            "SELECT angle FROM rotation WHERE path = ?", (str(path),)
        ).fetchone()
        return int(row["angle"]) if row else 0

    def set_rotation(self, path: Path, angle: int) -> int:
        angle = normalize_angle(angle)
        with self.conn:
            self.conn.execute(
                "INSERT INTO rotation(path, angle, updated) VALUES(?, ?, ?) "
                "ON CONFLICT(path) DO UPDATE SET angle = excluded.angle, updated = excluded.updated",
                (str(path), angle, time.time()),
            )
        return angle

    def forget_rotation(self, path: Path) -> None:
        with self.conn:
            self.conn.execute("DELETE FROM rotation WHERE path = ?", (str(path),))

    # 最近文件夹

    def recent(self, limit: int = 12) -> list[str]:
        rows = self.conn.execute(
            "SELECT path FROM recent ORDER BY opened DESC LIMIT ?", (limit,)
        ).fetchall()
        return [row["path"] for row in rows]

    def touch_recent(self, path: Path, limit: int = 12) -> list[str]:
        with self.conn:
            self.conn.execute(
                "INSERT INTO recent(path, opened) VALUES(?, ?) "
                "ON CONFLICT(path) DO UPDATE SET opened = excluded.opened",
                (str(path), time.time()),
            )
            self.conn.execute(
                "DELETE FROM recent WHERE path NOT IN "
                "(SELECT path FROM recent ORDER BY opened DESC LIMIT ?)",
                (limit,),
            )
        return self.recent(limit)

    def drop_recent(self, path: Path) -> list[str]:
        with self.conn:
            self.conn.execute("DELETE FROM recent WHERE path = ?", (str(path),))
        return self.recent()


def normalize_angle(angle: int) -> int:
    if angle % 90 != 0:
        raise ValueError("旋转角度必须是 90 的整数倍")
    return angle % 360


def validate_setting(key: str, value):
    if key not in DEFAULT_SETTINGS:
        raise ValueError(f"未知选项：{key}")
    if key in SETTING_CHOICES:
        if value not in SETTING_CHOICES[key]:
            choices = "、".join(SETTING_CHOICES[key])
            raise ValueError(f"选项 {key} 只能是 {choices}")
        return value
    if key == "slideshow_interval":
        if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= 60:
            raise ValueError("幻灯片间隔必须是 1 到 60 之间的整数秒")
        return value
    if key == "grid_page_size":
        if isinstance(value, bool) or not isinstance(value, int) or not 12 <= value <= 96:
            raise ValueError("每页数量必须是 12 到 96 之间的整数")
        return value
    if not isinstance(value, bool):
        raise ValueError(f"选项 {key} 必须是开关值")
    return value
