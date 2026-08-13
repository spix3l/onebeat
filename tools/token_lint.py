#!/usr/bin/env python3
"""Token lint (FR-UX-02, OB-1-03 §3).

"Every colour, size and spacing value resolves to a token" is only true if it is
checked. This fails the build on a literal colour or a raw dimension in widget
code, and names the line.

Scope: app/lib/src/ui/** and app/lib/main.dart. The token definitions themselves
(app/lib/src/design/) and generated code are exempt — they are where the numbers
are allowed to live.

Usage: python3 tools/token_lint.py [--verbose]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
LINT_ROOTS = [REPO_ROOT / "app" / "lib" / "src" / "ui", REPO_ROOT / "app" / "lib" / "main.dart"]
EXEMPT_DIRS = {"design", "generated"}

Rule = tuple[str, re.Pattern[str], str]

RULES: list[Rule] = [
    (
        "literal-colour",
        re.compile(r"\bColor\(\s*0x[0-9a-fA-F]{6,8}\s*\)"),
        "use a colour token (OneBeatTheme.of(context).color.*)",
    ),
    (
        "material-colour",
        re.compile(r"\bColors\.[a-zA-Z]"),
        "Material colours are not tokens; use OneBeatTheme.of(context).color.*",
    ),
    (
        "colour-opacity",
        re.compile(r"\.withOpacity\(|\.withValues\("),
        "derive translucent colours in tokens.dart, not at the call site",
    ),
    (
        "raw-edge-insets",
        re.compile(r"EdgeInsets\.(all|symmetric|only|fromLTRB)\([^)]*?\b\d+(\.\d+)?\b"),
        "use tokens.spacing.*",
    ),
    (
        "raw-font-size",
        re.compile(r"fontSize:\s*\d"),
        "use a type token (tokens.type.*)",
    ),
    (
        "raw-border-radius",
        re.compile(r"BorderRadius\.circular\(\s*\d|Radius\.circular\(\s*\d"),
        "use tokens.radius.*",
    ),
    (
        "raw-duration",
        re.compile(r"Duration\(\s*(milliseconds|seconds)\s*:\s*\d"),
        "use tokens.motion.*",
    ),
]

# Numeric literals are allowed where they are not a visual dimension: indices,
# counts, string padding, maths. The rule below only catches sizing properties.
SIZE_RULE = (
    "raw-size",
    re.compile(r"\b(width|height|size|elevation|strokeWidth|letterSpacing)\s*:\s*\d+(\.\d+)?\b"),
    "use tokens.size.* / tokens.spacing.*",
)
RULES.append(SIZE_RULE)

ALLOW_COMMENT = "// token-lint-ok:"


def files_to_lint() -> list[Path]:
    files: list[Path] = []
    for root in LINT_ROOTS:
        if root.is_file():
            files.append(root)
        elif root.is_dir():
            for path in sorted(root.rglob("*.dart")):
                if EXEMPT_DIRS.intersection(path.parts):
                    continue
                files.append(path)
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    violations: list[str] = []
    checked = 0

    for path in files_to_lint():
        checked += 1
        for number, line in enumerate(path.read_text().splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("//") or ALLOW_COMMENT in line:
                continue
            for name, pattern, advice in RULES:
                match = pattern.search(line)
                if match:
                    relative = path.relative_to(REPO_ROOT)
                    violations.append(
                        f"{relative}:{number}: {name}: '{match.group(0).strip()}' — {advice}"
                    )

    if args.verbose:
        print(f"Checked {checked} widget file(s).")

    if violations:
        print("Token lint FAILED:")
        for violation in violations:
            print(f"  {violation}")
        print()
        print("Every colour, size and spacing value in widget code must resolve to a")
        print("token (FR-UX-02). Add the value to app/lib/src/design/tokens.dart and")
        print("use it from there. If a number genuinely is not a visual dimension,")
        print(f"annotate the line with '{ALLOW_COMMENT} why'.")
        return 1

    print(f"Token lint passed: {checked} widget file(s) clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
