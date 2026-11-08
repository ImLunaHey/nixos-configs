#!/usr/bin/env python3
"""Install the pinned plugin bundle while Jellyfin is stopped (ExecStartPre)."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tarfile
import tempfile


def manifest(directory):
    return json.loads((directory / "meta.json").read_text())


def binaries(directory):
    return {
        str(path.relative_to(directory)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in directory.rglob("*")
        if path.is_file() and path.name != "meta.json"
    }


def install(source, state, backup_root, uid, gid):
    desired = {path.name: path for path in source.iterdir() if path.is_dir()}
    if not desired or any(not (path / "meta.json").is_file() for path in desired.values()):
        raise ValueError("Incomplete plugin bundle")
    managed = {manifest(path)["guid"].lower() for path in desired.values()}
    # Themerr changed its plugin ID between the installed 2024 and 2026 releases.
    managed.add("84b59a39-bde4-42f4-adbd-c39882cbb772")
    plugins = state / "config/plugins"
    plugins.mkdir(parents=True, exist_ok=True)
    replace = []
    for existing in plugins.iterdir():
        if not existing.is_dir() or not (existing / "meta.json").is_file():
            continue
        if manifest(existing)["guid"].lower() in managed:
            if existing.name not in desired or binaries(existing) != binaries(desired[existing.name]):
                replace.append(existing)
    missing = [name for name in desired if not (plugins / name).exists()]
    if replace or missing:
        backup_root.mkdir(parents=True, exist_ok=True, mode=0o700)
        backup = Path(tempfile.mkdtemp(prefix="before-plugin-change-", dir=backup_root))
        # ExecStartPre runs after the previous container has stopped. Preserve a
        # consistent database as well as credentials, watch history and plugins.
        with tarfile.open(backup / "state.tar", "w") as archive:
            for name in ("config", "cache"):
                if (state / name).exists():
                    archive.add(state / name, arcname=name)
        print(f"Jellyfin rollback backup: {backup / 'state.tar'}", flush=True)
        for existing in replace:
            shutil.move(str(existing), backup / existing.name)
        for name, package in desired.items():
            destination = plugins / name
            if not destination.exists():
                shutil.copytree(package, destination)
                for path in [destination, *destination.rglob("*")]:
                    os.chown(path, uid, gid)
                    path.chmod(0o755 if path.is_dir() else 0o644)
    # Jellyfin mutates meta.json at runtime. Restore the declarative version and
    # disable automatic plugin updates without discarding configuration files.
    for name, package in desired.items():
        target = plugins / name / "meta.json"
        shutil.copyfile(package / "meta.json", target)
        os.chown(target, uid, gid)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--state", type=Path, default=Path("/var/lib/jellyfin"))
    parser.add_argument("--backup-root", type=Path, default=Path("/var/backups/jellyfin"))
    parser.add_argument("--uid", type=int, default=100000)
    parser.add_argument("--gid", type=int, default=100000)
    args = parser.parse_args()
    install(args.source, args.state, args.backup_root, args.uid, args.gid)
