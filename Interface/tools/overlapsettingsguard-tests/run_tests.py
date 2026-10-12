"""Run the OverlapSettingsGuard tests in Lua 5.1 (the game's Lua).

    uv run --with lupa python tools/overlapsettingsguard-tests/run_tests.py
"""

import sys
from pathlib import Path

from lupa import lua51


def main() -> int:
    tests_root = Path(__file__).resolve().parent
    addon_root = tests_root.parents[1] / "AddOns" / "OverlapSettingsGuard"
    lua = lua51.LuaRuntime()
    lua.globals().ADDON_ROOT = addon_root.as_posix() + "/"
    lua.globals().TESTS_ROOT = tests_root.as_posix() + "/"
    lua.globals().INSTALLED_ADDONS = lua.table_from({
        folder.name: True for folder in addon_root.parent.iterdir() if folder.is_dir()
    })
    lua.globals().ADDON_FILES = lua.table_from([
        line.strip()
        for line in (addon_root / "OverlapSettingsGuard.toc").read_text(encoding="utf-8").splitlines()
        if line.strip().endswith(".lua")
    ])
    source = (tests_root / "tests.lua").read_text(encoding="utf-8")
    failures = lua.execute(source)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
