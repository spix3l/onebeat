#!/usr/bin/env python3
"""Licence audit (NFR-09, OB-1-02 §3).

OneBeat is MIT and must stay MIT-compatible for everyone who ships it. Copyleft —
including LGPL, which is the one people assume is fine — fails the build, and the
offending package is named so the failure is actionable.

Checks two dependency surfaces:
  * third_party/<name>/  — each vendored directory must carry a licence file
    whose text matches an allowed licence;
  * app/pubspec.lock     — every resolved Dart package, resolved against the
    licence recorded in the local pub cache.

Usage: python3 tools/license_audit.py [--verbose]
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Permissive licences we accept without further thought.
ALLOWED = {
    "MIT",
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "Zlib",
    "Unlicense",
    "CC0-1.0",
    "public-domain",
    # Fonts. OFL-1.1 is permissive for embedding and redistribution, which is
    # all we do with it; it is allowed for font assets only (see FONT_ONLY).
    "OFL-1.1",
}

FONT_ONLY = {"OFL-1.1"}

# Named explicitly so the failure message can say *which* copyleft licence.
DENIED = {
    "GPL-2.0",
    "GPL-3.0",
    "LGPL-2.1",
    "LGPL-3.0",
    "AGPL-3.0",
    "MPL-2.0",
    "CDDL-1.0",
    "EPL-2.0",
    "SSPL-1.0",
}

# Ordered: the first match wins, and the copyleft patterns come first so that a
# dual-licensed file cannot be waved through by its permissive half.
SIGNATURES: list[tuple[str, str]] = [
    ("AGPL-3.0", r"GNU AFFERO GENERAL PUBLIC LICENSE"),
    ("LGPL-3.0", r"GNU LESSER GENERAL PUBLIC LICENSE.{0,200}Version 3"),
    ("LGPL-2.1", r"GNU LESSER GENERAL PUBLIC LICENSE.{0,200}Version 2\.1"),
    ("LGPL-2.1", r"GNU LIBRARY GENERAL PUBLIC LICENSE"),
    ("GPL-3.0", r"GNU GENERAL PUBLIC LICENSE.{0,200}Version 3"),
    ("GPL-2.0", r"GNU GENERAL PUBLIC LICENSE.{0,200}Version 2"),
    ("MPL-2.0", r"Mozilla Public License Version 2\.0"),
    ("CDDL-1.0", r"COMMON DEVELOPMENT AND DISTRIBUTION LICENSE"),
    ("EPL-2.0", r"Eclipse Public License"),
    ("SSPL-1.0", r"Server Side Public License"),
    ("OFL-1.1", r"SIL OPEN FONT LICENSE"),
    ("Apache-2.0", r"Apache License.{0,200}Version 2\.0"),
    ("ISC", r"Permission to use, copy, modify, and/or distribute this software"),
    ("BSD-3-Clause", r"Neither the name of .{0,120} may be used to endorse"),
    ("BSD-2-Clause", r"Redistribution and use in source and binary forms"),
    ("Zlib", r"This software is provided 'as-is', without any express or implied"),
    ("CC0-1.0", r"CC0 1\.0 Universal|Creative Commons Zero"),
    ("Unlicense", r"This is free and unencumbered software released into the public domain"),
    ("public-domain", r"public domain|placed in the public domain"),
    ("MIT", r"Permission is hereby granted, free of charge"),
]

LICENCE_FILE_NAMES = re.compile(
    r"^(LICEN[CS]E|COPYING|OFL|UNLICENSE)(\.(txt|md))?$", re.IGNORECASE
)


def identify(text: str) -> str | None:
    """Return the first licence whose signature appears in *text*."""
    condensed = " ".join(text.split())
    for name, pattern in SIGNATURES:
        if re.search(pattern, condensed, re.IGNORECASE | re.DOTALL):
            return name
    return None


def find_licence_file(directory: Path) -> Path | None:
    for path in sorted(directory.rglob("*")):
        if path.is_file() and LICENCE_FILE_NAMES.match(path.name):
            return path
    return None


class Finding:
    def __init__(self, package: str, licence: str | None, source: str, ok: bool, why: str):
        self.package = package
        self.licence = licence
        self.source = source
        self.ok = ok
        self.why = why


def audit_vendored() -> list[Finding]:
    findings: list[Finding] = []
    third_party = REPO_ROOT / "third_party"
    if not third_party.is_dir():
        return findings

    for entry in sorted(third_party.iterdir()):
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        # fonts/ holds one directory per family, each with its own licence.
        directories = (
            [d for d in sorted(entry.iterdir()) if d.is_dir()]
            if entry.name == "fonts"
            else [entry]
        )
        for directory in directories:
            name = str(directory.relative_to(third_party))
            licence_file = find_licence_file(directory)
            if licence_file is None:
                findings.append(
                    Finding(name, None, "third_party", False, "no LICENSE file in the directory")
                )
                continue
            licence = identify(licence_file.read_text(errors="replace"))
            findings.append(evaluate(name, licence, "third_party", is_font="fonts" in str(directory)))
    return findings


def audit_dart() -> list[Finding]:
    findings: list[Finding] = []
    lock = REPO_ROOT / "app" / "pubspec.lock"
    if not lock.is_file():
        return findings

    cache = Path(os.environ.get("PUB_CACHE", Path.home() / ".pub-cache"))
    package = None
    version = None
    source = None
    for line in lock.read_text().splitlines():
        if re.match(r"^  [A-Za-z0-9_]+:$", line):
            package = line.strip().rstrip(":")
            version = None
            source = None
        elif package and line.strip().startswith("version:"):
            version = line.split('"')[1] if '"' in line else line.split(":", 1)[1].strip()
        elif package and line.strip().startswith("source:"):
            source = line.split(":", 1)[1].strip()

        if package and version and source:
            if source == "hosted":
                directory = cache / "hosted" / "pub.dev" / f"{package}-{version}"
                licence_file = find_licence_file(directory) if directory.is_dir() else None
                if licence_file is None:
                    findings.append(
                        Finding(
                            f"{package} {version}",
                            None,
                            "pub",
                            True,
                            "not in the local pub cache; verified in CI where it is",
                        )
                    )
                else:
                    licence = identify(licence_file.read_text(errors="replace"))
                    findings.append(evaluate(f"{package} {version}", licence, "pub"))
            else:
                # sdk / path packages: Flutter itself, BSD-3-Clause.
                findings.append(
                    Finding(f"{package} ({source})", "BSD-3-Clause", "pub", True, "Flutter SDK")
                )
            package = version = source = None
    return findings


def evaluate(name: str, licence: str | None, source: str, is_font: bool = False) -> Finding:
    if licence is None:
        return Finding(name, None, source, False, "licence text not recognised")
    if licence in DENIED:
        return Finding(name, licence, source, False, f"{licence} is copyleft and is not allowed")
    if licence in FONT_ONLY and not is_font:
        return Finding(
            name, licence, source, False, f"{licence} is only allowed for font assets"
        )
    if licence not in ALLOWED:
        return Finding(name, licence, source, False, f"{licence} is not on the allowlist")
    return Finding(name, licence, source, True, "")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    findings = audit_vendored() + audit_dart()
    failures = [f for f in findings if not f.ok]

    if args.verbose or failures:
        for finding in findings:
            mark = "ok  " if finding.ok else "FAIL"
            licence = finding.licence or "unknown"
            print(f"{mark} {finding.package:<44} {licence:<14} {finding.why}")

    print()
    if failures:
        print(f"Licence audit FAILED for {len(failures)} package(s):")
        for finding in failures:
            print(f"  - {finding.package}: {finding.why}")
        print()
        print("Every dependency must be MIT, Apache-2.0, BSD, ISC, Zlib or public domain")
        print("(NFR-09). Replace the dependency, or vendor an equivalent under a")
        print("permissive licence.")
        return 1

    print(f"Licence audit passed: {len(findings)} package(s) checked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
