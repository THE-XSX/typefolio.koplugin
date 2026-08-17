#!/usr/bin/env python3
"""Build the installable KOReader plugin ZIP.

KOReader plugins are installed by unzipping into `koreader/plugins/`, so the archive
must carry its own plugin root folder — `<name>.koplugin/main.lua`, not `main.lua`.
An archive whose files sit at the root scatters them across the plugins directory and
the plugin never loads. That is exactly what a bare `zip -r … .` from inside the repo
produces, which is why this script exists instead of a one-line command in the docs.

Usage:  python3 tools/package.py [-o OUTPUT]

Stdlib only, no `zip` binary needed, so it runs the same on Windows, macOS and Linux.
Packs the working tree rather than `git archive`, because the runtime modules are not
all committed yet; every packed file is listed so an unintended one is easy to spot.
"""

import argparse
import os
import re
import sys
import zipfile

# Directories that must never reach a release archive. Matched against path segments,
# so a nested `tests/` or `__pycache__/` anywhere in the tree is caught too.
EXCLUDE_DIRS = {
    ".git",
    ".github",
    ".agents",
    ".claude",
    ".idea",
    ".vscode",
    "__pycache__",
    "tests",
    "node_modules",
}

# Editor droppings and build leftovers. `*.zip` keeps the previous archive from being
# packed into the new one when the output lands in the repo root. `*.py` covers this
# script itself: the plugin is pure Lua, so nothing Python ever belongs on the device.
EXCLUDE_SUFFIXES = (".zip", ".py", ".pyc", ".pyo", ".orig", ".rej", ".swp", ".swo", "~")
EXCLUDE_NAMES = {".DS_Store", "Thumbs.db", "desktop.ini", ".gitignore", ".gitattributes"}

# Files the plugin cannot load without. Checked inside the finished archive.
REQUIRED = ("_meta.lua", "main.lua")


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def collect(root):
    """Every file to pack, as paths relative to `root`, sorted for a stable archive."""
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDE_DIRS)
        for name in sorted(filenames):
            if name in EXCLUDE_NAMES or name.endswith(EXCLUDE_SUFFIXES):
                continue
            abs_path = os.path.join(dirpath, name)
            found.append(os.path.relpath(abs_path, root).replace(os.sep, "/"))
    return found


def meta_version(root):
    path = os.path.join(root, "_meta.lua")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        match = re.search(r'version\s*=\s*"([^"]+)"', handle.read())
    return match.group(1) if match else None


def readme_version(root):
    """Newest version in the README changelog.

    The two plugins spell their headings differently (`### v3.0.4 (2026-08-11)` versus
    `### 2026-08-11 (v3.0.4)`), so pull the first `vX.Y.Z` out of the first `###`
    heading that has one rather than pinning either layout.
    """
    path = os.path.join(root, "README.md")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("###"):
                match = re.search(r"v(\d+\.\d+\.\d+)", line)
                if match:
                    return match.group(1)
    return None


def verify(archive, prefix, files):
    """Re-open the finished archive and check it against the install requirements."""
    problems = []
    with zipfile.ZipFile(archive) as zf:
        names = zf.namelist()
        bad = zf.testzip()
        if bad is not None:
            problems.append("corrupt entry: %s" % bad)

    stray = [n for n in names if not n.startswith(prefix)]
    if stray:
        problems.append(
            "%d entries are not under %s (e.g. %s)" % (len(stray), prefix, stray[0])
        )

    for name in names:
        segments = name.split("/")[1:]
        hit = EXCLUDE_DIRS.intersection(segments)
        if hit:
            problems.append("excluded directory %s present: %s" % (sorted(hit)[0], name))
        leaf = segments[-1] if segments else ""
        if leaf in EXCLUDE_NAMES or (leaf and leaf.endswith(EXCLUDE_SUFFIXES)):
            problems.append("excluded file present: %s" % name)

    for required in REQUIRED:
        if prefix + required not in names:
            problems.append("missing %s" % (prefix + required))

    if len(names) != len(files):
        problems.append("packed %d entries but collected %d" % (len(names), len(files)))

    return problems


def main():
    root = repo_root()
    plugin = os.path.basename(root)

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-o",
        "--output",
        default=os.path.join(root, plugin + ".zip"),
        help="archive path (default: <repo>/%s.zip)" % plugin,
    )
    parser.add_argument(
        "-l", "--list", action="store_true", help="list every packed file"
    )
    args = parser.parse_args()

    if not plugin.endswith(".koplugin"):
        sys.stderr.write(
            "error: repository folder is %r; KOReader needs it to end in .koplugin,\n"
            "       since the folder name becomes the archive's plugin root.\n" % plugin
        )
        return 1

    prefix = plugin + "/"
    files = collect(root)
    if not files:
        sys.stderr.write("error: nothing to pack under %s\n" % root)
        return 1

    output = os.path.abspath(args.output)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as zf:
        for rel in files:
            zf.write(os.path.join(root, rel), prefix + rel)

    problems = verify(output, prefix, files)
    if problems:
        sys.stderr.write("error: %s failed verification\n" % os.path.basename(output))
        for problem in problems:
            sys.stderr.write("  - %s\n" % problem)
        return 1

    if args.list:
        for rel in files:
            print("  " + prefix + rel)

    meta = meta_version(root)
    readme = readme_version(root)
    print(
        "%s: %d files, %.0f KiB, all under %s"
        % (os.path.basename(output), len(files), os.path.getsize(output) / 1024, prefix)
    )
    print("  _meta.lua version %s / README changelog %s" % (meta or "?", readme or "?"))

    # A mismatch is a release blocker per DEVELOPMENT_SPEC, but the archive itself is
    # valid, so warn instead of failing: whoever is mid-release may not have written
    # the changelog entry yet.
    if meta and readme and meta != readme:
        print(
            "  warning: version mismatch — DEVELOPMENT_SPEC requires _meta.lua, the "
            "README changelog and the git tag to agree before tagging."
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
