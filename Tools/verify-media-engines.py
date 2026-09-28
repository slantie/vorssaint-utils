#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
"""Verify a staged or signed app's media-engine bundle before distribution."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--refresh-signed-hashes", action="store_true",
                        help="Record distribution signatures after signing, before sealing the app")
    args = parser.parse_args()
    root = args.root.resolve()
    manifest = json.loads((root / "manifest.json").read_text())
    if manifest.get("target") != "arm64-apple-macos14" or manifest.get("schema") != 1:
        raise SystemExit("Unknown engine bundle target/schema")
    for record in manifest["files"]:
        relative = Path(record["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise SystemExit("Invalid manifest path")
        binary = root / relative
        if binary.is_symlink() or not binary.is_file():
            raise SystemExit(f"Missing regular binary: {relative}")
        actual = hashlib.sha256(binary.read_bytes()).hexdigest()
        if args.refresh_signed_hashes:
            record.update(sha256=actual, bytes=binary.stat().st_size)
        elif actual != record["sha256"]:
            raise SystemExit(f"Binary hash mismatch: {relative}")
        if command("lipo", "-archs", str(binary)) != "arm64":
            raise SystemExit(f"Unexpected architecture: {relative}")
        load_commands = command("otool", "-l", str(binary))
        minimum = re.search(r"\bminos (\S+)", load_commands)
        if not minimum or tuple(map(int, (minimum[1].split(".") + ["0", "0"])[:3])) > (14, 0, 0):
            raise SystemExit(f"Incompatible minimum OS: {relative}")
        rpaths = re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset", load_commands)
        if rpaths != ["@loader_path/../lib"]:
            raise SystemExit(f"Nonportable library search paths: {relative}")
        for line in command("otool", "-L", str(binary)).splitlines()[1:]:
            dependency = line.strip().split(" (", 1)[0]
            if dependency.startswith(("/usr/lib/", "/System/Library/")):
                continue
            if not dependency.startswith("@rpath/") or "/" in dependency.removeprefix("@rpath/"):
                raise SystemExit(f"External dependency in {relative}: {dependency}")
            target = root / "lib" / dependency.removeprefix("@rpath/")
            if not target.is_file() or not target.resolve().is_relative_to(root):
                raise SystemExit(f"Unresolved private library: {dependency}")
        command("codesign", "--verify", "--strict", str(binary))
    for link in (root / "lib").iterdir():
        if link.is_symlink() and not link.resolve().is_relative_to(root / "lib"):
            raise SystemExit(f"External library alias: {link.name}")
    for name in ["ffmpeg", "ffprobe"]:
        command(str(root / "bin" / name), "-version")
    command(str(root / "bin/svg-renderer"), "--version")
    protocols = command(str(root / "bin/ffmpeg"), "-hide_banner", "-protocols")
    names = {line.strip() for line in protocols.splitlines() if line.startswith("  ")}
    if names != {"file", "pipe"}:
        raise SystemExit(f"Unexpected file/network protocols: {names}")
    if args.refresh_signed_hashes:
        (root / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Media engines verified: {len(manifest['files'])} Apple Silicon binaries, macOS 14, local protocols only")


if __name__ == "__main__":
    main()
