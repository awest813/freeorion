#!/usr/bin/env python3
"""
Check that every graphic path referenced by content scripts exists under the art directory.

Usage: check/checkArtPaths.py [default_dir]

Exit status is 1 if any referenced image is missing.
"""

import re
import sys
from pathlib import Path

RE_GRAPHIC = re.compile(r'\bgraphic\s*=\s*"([^"]+)"')

# Files whose graphic values are resolved relative to a subdirectory of the art dir,
# rather than the art dir itself (see ClientUI::CategoryIcon in UI/ClientUI.cpp).
RELATIVE_ROOTS = {
    "Categories.inf.py": Path("icons/tech/categories"),
}


def main(default_dir: Path) -> int:
    art_dir = default_dir / "data" / "art"
    scripting_dir = default_dir / "scripting"
    missing = []
    checked = 0

    for script in sorted(scripting_dir.rglob("*")):
        if not script.is_file() or script.suffix not in (".py", ".txt"):
            continue
        root = art_dir / RELATIVE_ROOTS.get(script.name, Path())
        text = script.read_text(encoding="utf-8")
        for match in RE_GRAPHIC.finditer(text):
            value = match.group(1)
            if not value:
                continue
            checked += 1
            if not (root / value).is_file():
                line = text.count("\n", 0, match.start()) + 1
                missing.append(f"{script.relative_to(default_dir.parent)}:{line}: missing {value}")

    for entry in missing:
        print(entry)
    print(f"Checked {checked} graphic references, {len(missing)} missing.")
    return 1 if missing else 0


if __name__ == "__main__":
    default = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "default"
    sys.exit(main(default))
