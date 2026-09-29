"""Fail if a generated tree differs from the committed one.

`assets/` is generated from `art/` and is a committed product: a hand edit
inside it is drift, not work.

PNGs are compared by decoded RGBA pixels, not bytes: the atlas is re-encoded by
Pillow, and zlib builds differ across platforms while the pixels stay identical.
Every other file must match byte for byte.

Every kind of drift is one line naming the path: a product git does not track
yet (untracked), one that is staged but the commit has never held (new product),
one the build changed, one it removed. None of them is a crash: a new product
has no HEAD version to compare with, and that is exactly what its line says.
"""
from __future__ import annotations

import argparse
import io
import subprocess
import sys
from pathlib import Path

from PIL import Image

from build_assets import ROOT


def git(root: Path, *args: str) -> bytes:
    return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True).stdout


def pixels(data: bytes) -> tuple:
    with Image.open(io.BytesIO(data)) as image:
        return image.size, image.convert("RGBA").tobytes()


def drift(root: Path, targets: list[str]) -> tuple[list[str], list[str]]:
    """Every difference from HEAD under `targets`, as (drift lines, notes that are not drift)."""
    # --name-status says whether HEAD holds the path at all, so a new product is
    # never looked up in HEAD; --no-renames keeps every entry one path long.
    status = git(root, "diff", "--name-status", "--no-renames", "-z", "HEAD", "--", *targets).decode().split("\0")
    untracked = git(root, "ls-files", "--others", "--exclude-standard", "-z", "--", *targets).decode().split("\0")
    problems = [f"untracked: {path}" for path in untracked if path]
    notes = []
    entries = [field for field in status if field]
    for letter, path in zip(entries[0::2], entries[1::2]):
        file = root / path
        if letter == "A":
            problems.append(f"new product (not in HEAD), commit it: {path}")
        elif letter == "D" or not file.exists():
            problems.append(f"deleted: {path}")
        elif path.endswith(".png") and pixels(git(root, "show", f"HEAD:{path}")) == pixels(file.read_bytes()):
            notes.append(f"same pixels, different PNG encoding: {path}")
        else:
            problems.append(f"modified: {path}")
    return problems, notes


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", default=["assets"], help="trees to check, relative to the repo")
    targets = parser.parse_args(argv).paths
    problems, notes = drift(root, targets)
    for note in notes:
        print(note)
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print("Generated art differs from the commit; rerun `make art` and commit the result.", file=sys.stderr)
        return 1
    print(f"CLEAN: {', '.join(target + '/' for target in targets)} matches the commit")
    return 0


if __name__ == "__main__":
    sys.exit(main())
