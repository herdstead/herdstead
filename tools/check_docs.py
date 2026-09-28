#!/usr/bin/env python3
"""Check that the documents a reader starts from point at things that exist.

Standard library only. `make docs-check` runs it, and so do `make check` and CI.
Over README.md, AGENTS.md, docs/MANUAL.md (the user manual README points to)
and docs/MACHINES.md (which the manual hands its machines section to), two
checks:

- Every backticked repo path exists. A span is a repo path when its first
  component is something at the repo root (`scripts/office.gd`, `docs/`,
  `.github/workflows/ci.yml`, with `res://` read as the root), or when it is a
  bare file name with a source extension (`project.godot`, `pack.json`), which
  has to exist somewhere in the tree. Not checked: globs, placeholders (`<id>`,
  `…`), URLs, `user://`, `~`, absolute system paths, environment variables,
  `.git/` and git-ignored output such as `build/…`. So `1/density` is prose,
  not a path; a path whose first component is misspelt goes unnoticed.
- Every `make <target>` they mention, in backticks or on a command line in a
  code block, is a target the Makefile defines.

    python3 tools/check_docs.py
    python3 tools/check_docs.py docs/WORLD_MODEL.md    (any other document)
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCUMENTS = ("README.md", "AGENTS.md", "docs/MANUAL.md", "docs/MACHINES.md")
# Bare file names with these extensions are files a reader could open in the
# tree; anything else bare (`Herdstead.app`, `events.subscribe`) is not.
SOURCE_EXTENSIONS = {
    "cfg", "gd", "godot", "import", "json", "md", "png", "py", "sh",
    "tres", "tscn", "ttf", "txt", "uid", "yaml", "yml",
}
# Walked for bare names; nothing a document names lives in them.
SKIPPED_DIRS = {".git", ".godot", ".venv", "__pycache__", "build"}
SPAN = re.compile(r"(`+)(.+?)\1")
TARGET_LINE = re.compile(r"^([a-z][a-z0-9-]*)\s*:(?!=)")
# `make` where a shell command starts, in a code block.
MAKE_COMMAND = re.compile(r"(?:^|&&|\|\||;|\(|\$\()\s*make\b([^#;&|)`]*)")
UNCHECKED_PREFIXES = ("http://", "https://", "user://", "~", "/", "$", "-", ".git/")


def makefile_targets():
    targets = set()
    with open(os.path.join(ROOT, "Makefile"), encoding="utf-8") as makefile:
        for line in makefile:
            match = TARGET_LINE.match(line)
            if match:
                targets.add(match.group(1))
    return targets


def tree_names():
    """Every file and directory name in the tree, for bare names."""
    names = set()
    for directory, subdirectories, files in os.walk(ROOT):
        subdirectories[:] = [name for name in subdirectories if name not in SKIPPED_DIRS]
        names.update(subdirectories)
        names.update(files)
    return names


def git_ignored(path):
    """True when git would ignore `path`; false outside a git checkout."""
    try:
        result = subprocess.run(
            ["git", "-C", ROOT, "check-ignore", "-q", "--no-index", path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        return False
    return result.returncode == 0


def make_targets(command):
    """The targets named after `make`: words, up to the first that is not one."""
    found = []
    for word in command.split():
        if "=" in word or word.startswith("-"):
            continue
        if not re.fullmatch(r"[a-z][a-z0-9-]*", word):
            break
        found.append(word)
    return found


def repo_path(span):
    """The repo-relative path a span names, or None when it names no repo path."""
    text = span.strip()
    if text.startswith("res://"):
        text = text[len("res://"):]
        if not text:
            return None
    elif text.startswith(UNCHECKED_PREFIXES) or "://" in text:
        return None
    text = text.split("#", 1)[0]
    if not text or re.search(r"[\s<>*?\[\]{}…=:%'\",()]", text) or "..." in text:
        return None
    if re.fullmatch(r"\.[A-Za-z0-9]+", text):
        return None  # a file type, `.tscn`
    return text


def check(document, targets, names):
    problems = []
    paths = 0
    makes = 0
    fenced = False
    if not os.path.isfile(os.path.join(ROOT, document)):
        return ["%s: the document itself is missing" % document], 0, 0
    with open(os.path.join(ROOT, document), encoding="utf-8") as source:
        lines = source.read().splitlines()
    for number, line in enumerate(lines, 1):
        where = "%s:%d" % (document, number)
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        commands = []
        spans = [match.group(2) for match in SPAN.finditer(line)]
        commands.extend(span[len("make"):] for span in spans if span == "make" or span.startswith("make "))
        if fenced:
            code = SPAN.sub("", line)
            commands.extend(match.group(1) for match in MAKE_COMMAND.finditer(code))
        for command in commands:
            for target in make_targets(command):
                makes += 1
                if target not in targets:
                    problems.append("%s: `make %s`: the Makefile has no target %s" % (where, target, target))
        if fenced:
            continue
        for span in spans:
            path = repo_path(span)
            if path is None:
                continue
            first = path.split("/", 1)[0]
            if "/" in path:
                if not os.path.exists(os.path.join(ROOT, first)) or git_ignored(path):
                    continue
                paths += 1
                if not os.path.exists(os.path.join(ROOT, path)):
                    problems.append("%s: `%s` does not exist" % (where, span))
            elif "." in path and path.rsplit(".", 1)[1] in SOURCE_EXTENSIONS:
                paths += 1
                if path not in names:
                    problems.append("%s: `%s` is not a file anywhere in the tree" % (where, span))
    return problems, paths, makes


def main():
    # Other documents can be named on the command line, relative to the root.
    documents = tuple(sys.argv[1:]) or DOCUMENTS
    targets = makefile_targets()
    names = tree_names()
    problems = []
    paths = 0
    makes = 0
    for document in documents:
        found, checked_paths, checked_makes = check(document, targets, names)
        problems.extend(found)
        paths += checked_paths
        makes += checked_makes
    for problem in problems:
        print("DOCS_PROBLEM: " + problem)
    if problems:
        print("DOCS_FAILED: %d problems in %s" % (len(problems), ", ".join(documents)))
        return 1
    print("DOCS_OK: %d repo paths and %d make targets in %s" % (paths, makes, ", ".join(documents)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
