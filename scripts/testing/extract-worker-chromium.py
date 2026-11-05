#!/usr/bin/env python3
"""Extract only a bounded, non-symlinked Chrome-for-Testing archive."""
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import zipfile


def extract(archive: str, destination: str) -> None:
    dest = Path(destination)
    with zipfile.ZipFile(archive) as source:
        entries = source.infolist()
        if len(entries) > 30000 or sum(item.file_size for item in entries) > 1_000_000_000:
            raise ValueError("Chromium archive exceeds bounds")
        names: set[str] = set()
        for item in entries:
            path = PurePosixPath(item.filename)
            mode = item.external_attr >> 16
            if (path.is_absolute() or not path.parts or path.parts[0] != "chrome-linux64"
                    or ".." in path.parts or stat.S_ISLNK(mode) or item.filename in names):
                raise ValueError("Unsafe Chromium archive entry")
            names.add(item.filename)
        dest.mkdir(mode=0o700)
        for item in entries:
            target = dest.joinpath(*PurePosixPath(item.filename).parts)
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with source.open(item) as incoming, target.open("xb") as outgoing:
                shutil.copyfileobj(incoming, outgoing, length=1024 * 1024)
            mode = item.external_attr >> 16
            target.chmod(0o755 if mode & 0o111 else 0o644)
    executable = dest / "chrome-linux64" / "chrome"
    if not executable.is_file():
        raise ValueError("Chromium executable missing")
    os.chmod(executable, 0o755)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Provide archive and fresh destination")
    extract(sys.argv[1], sys.argv[2])
