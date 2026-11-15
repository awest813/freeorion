#!/usr/bin/env python3
"""Reject theme literals in the fork's Godot UI (UI_OVERHAUL_PLAN.md §7.3).

Colours, spacings and font sizes come from the design tokens
(ui/tokens/FOTokens.gd) through the theme (ui/theme/). This check fails on:

* theme_override_* entries in .tscn files outside ui/theme/ (upstream's
  root-level scenes are exempt: the fork leaves them unedited);
* add_theme_constant_override / add_theme_font_size_override with a
  numeric literal other than 0 in GDScript UI code;
* add_theme_color_override with a Color(...) literal, and Color("#...") or
  Color.html(...) anywhere in GDScript UI code.

Style files (ui/theme/, ui/tokens/, map/MapStyle.gd) may hold literals. A
line ending in "# lint-ok: theme-literal" is accepted, for the rare case
that needs one.

Usage: check_theme_literals.py [godot4 directory]
"""

import re
import sys
from pathlib import Path

UI_DIRS = ("shell", "ui", "screens", "panels", "map")
STYLE_FILES = ("ui/theme/", "ui/tokens/", "map/MapStyle.gd")
WAIVER = "# lint-ok: theme-literal"

TSCN_OVERRIDE = re.compile(r"^theme_override_(colors|constants|font_sizes|fonts|styles)/")
SIZE_OVERRIDE = re.compile(
    r"add_theme_(constant|font_size)_override\([^,]+,\s*-?(?!0\b)\d+(\.\d+)?\s*\)"
)
COLOR_OVERRIDE = re.compile(r"add_theme_color_override\([^,]+,\s*Color\(")
HEX_COLOR = re.compile(r"Color\(\s*\"#|Color\.html\(")


def strip_comment(line: str) -> str:
    """\a line without its comment; a # inside a string isn't one."""
    quote = ""
    for index, char in enumerate(line):
        if quote:
            if char == quote and line[index - 1] != "\\":
                quote = ""
        elif char in "\"'":
            quote = char
        elif char == "#":
            return line[:index]
    return line


def is_style_file(relative: str) -> bool:
    return any(relative.startswith(prefix) for prefix in STYLE_FILES)


def check(root: Path) -> list[str]:
    problems = []
    for path in sorted(root.rglob("*.tscn")):
        relative = path.relative_to(root).as_posix()
        # Upstream's scenes sit at the root and add-ons are third-party.
        if "/" not in relative or relative.startswith(("addons/", "ui/theme/")):
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if TSCN_OVERRIDE.match(line) and not line.rstrip().endswith(WAIVER):
                problems.append(f"{relative}:{number}: theme override in a scene: {line.strip()}")
    for folder in UI_DIRS:
        for path in sorted((root / folder).rglob("*.gd")):
            relative = path.relative_to(root).as_posix()
            if is_style_file(relative):
                continue
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                code = strip_comment(line) if WAIVER not in line else ""
                for pattern, what in (
                    (SIZE_OVERRIDE, "numeric size override"),
                    (COLOR_OVERRIDE, "colour literal in an override"),
                    (HEX_COLOR, "colour literal"),
                ):
                    if pattern.search(code):
                        problems.append(f"{relative}:{number}: {what}; use FOUi.tokens: {line.strip()}")
    return problems


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
    problems = check(root)
    for problem in problems:
        print(problem)
    print(f"{len(problems)} theme literal(s) found" if problems else "No theme literals.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
