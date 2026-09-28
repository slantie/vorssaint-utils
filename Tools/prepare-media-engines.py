#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
"""Stage relocatable media engines from Homebrew, with an auditable manifest.

Build prerequisite: brew install ffmpeg imagemagick
This stages build dependencies; the installed app never invokes Homebrew.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def dependencies(path):
    return [line.strip().split(" (", 1)[0]
            for line in command("/usr/bin/otool", "-L", str(path)).splitlines()[1:]]


def resolve_dependency(source, dependency):
    if dependency.startswith("/"):
        return Path(dependency).resolve(strict=True)
    if dependency.startswith("@loader_path/"):
        return (source.parent / dependency.removeprefix("@loader_path/")).resolve(strict=True)
    if dependency.startswith("@rpath/"):
        name = dependency.removeprefix("@rpath/")
        candidates = [source.parent / name]
        load_commands = command("/usr/bin/otool", "-l", str(source))
        rpaths = re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset', load_commands)
        candidates.extend(Path(p.replace("@loader_path", str(source.parent))) / name for p in rpaths)
        for candidate in candidates:
            if candidate.is_file():
                return candidate.resolve(strict=True)
    raise RuntimeError(f"Unresolved library {dependency} in {source}")


def minimum_macos(path):
    commands = command("/usr/bin/otool", "-l", str(path))
    match = re.search(r'\bminos (\S+)', commands) or re.search(r'\bversion (\S+)', commands)
    if not match:
        raise RuntimeError(f"Missing minimum deployment version in {path}")
    return match.group(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--maximum-minimum-macos", default="14.0",
                        help="Reject incompatible binaries; use --allow-newer-macos only for measurement")
    parser.add_argument("--allow-newer-macos", action="store_true",
                        help="Permit a measurement prototype that cannot be shipped on macOS 14")
    args = parser.parse_args()
    target = args.destination.resolve()
    if target.exists():
        raise SystemExit(f"Destination already exists: {target}; use a fresh staging directory")
    target.mkdir(parents=True)
    binaries = target / "bin"
    libraries = target / "lib"
    modules = target / "coders"
    config = target / "config"
    notices = target / "notices"
    for directory in [binaries, libraries, modules, config, notices]:
        directory.mkdir()
    copied = {}
    packages = {}
    queue = []

    def stage(source, folder):
        source = source.resolve(strict=True)
        if source in copied:
            return copied[source]
        destination = folder / source.name
        if destination.exists():
            raise RuntimeError(f"Conflicting engine filenames: {destination.name}")
        shutil.copy2(source, destination)
        destination.chmod(0o755)
        copied[source] = destination
        queue.append(source)
        parts = source.parts
        if "Cellar" not in parts:
            raise RuntimeError(f"Expected an auditable Homebrew keg: {source}")
        index = parts.index("Cellar")
        package, version = parts[index + 1:index + 3]
        packages[package] = (version, Path(*parts[:index + 3]))
        return destination

    for name in ["ffmpeg", "ffprobe", "magick"]:
        path = shutil.which(name)
        if not path:
            raise SystemExit(f"Missing {name}. Install build prerequisites: brew install ffmpeg imagemagick")
        stage(Path(path), binaries)
    magick_keg = packages["imagemagick"][1]
    image_coders = {"png", "jpeg", "webp", "heic", "tiff", "bmp", "gif", "svg", "miff", "xc"}
    for source in sorted((magick_keg / "lib").glob("ImageMagick*/modules-*/coders/*.so")):
        if source.stem in image_coders:
            stage(source, modules)
            descriptor = source.with_suffix(".la")
            if descriptor.exists():
                text = descriptor.read_text()
                text = re.sub(r"^dependency_libs=.*$", "dependency_libs=''", text, flags=re.M)
                text = re.sub(r"^libdir=.*$", "libdir=''", text, flags=re.M)
                (modules / descriptor.name).write_text(text)

    while queue:
        source = queue.pop(0)
        for dependency in dependencies(source):
            if dependency.startswith(("/usr/lib/", "/System/Library/")):
                continue
            resolved = resolve_dependency(source, dependency)
            if resolved != source:
                stage(resolved, libraries)

    for source, destination in copied.items():
        changes = []
        for dependency in dependencies(source):
            if dependency.startswith(("/usr/lib/", "/System/Library/")):
                continue
            resolved = resolve_dependency(source, dependency)
            if resolved == source:
                continue
            relative = "@rpath/" + copied[resolved].name
            changes.extend(["-change", dependency, relative])
        if destination.parent == libraries:
            changes.extend(["-id", "@rpath/" + destination.name])
        load_commands = command("/usr/bin/otool", "-l", str(destination))
        rpaths = re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset', load_commands)
        for rpath in rpaths:
            if rpath != "@loader_path/../lib":
                changes.extend(["-delete_rpath", rpath])
        if "@loader_path/../lib" not in rpaths:
            changes.extend(["-add_rpath", "@loader_path/../lib"])
        changed = subprocess.run(["/usr/bin/install_name_tool", *changes, str(destination)],
                                 capture_output=True, text=True)
        if changed.returncode:
            raise RuntimeError(changed.stderr)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(destination)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # No external delegate commands or remote resources are allowed by this
    # private engine configuration. PDF rendering is handled by native PDFKit.
    (config / "policy.xml").write_text('''<?xml version="1.0"?>
<policymap>
  <policy domain="delegate" rights="none" pattern="*"/>
  <policy domain="coder" rights="none" pattern="{HTTP,HTTPS,URL,FTP,EPHEMERAL,MSL,MVG,PS,PS2,PS3,EPS,PDF,XPS}"/>
  <policy domain="path" rights="none" pattern="@*"/>
  <policy domain="resource" name="memory" value="512MiB"/>
  <policy domain="resource" name="map" value="1GiB"/>
  <policy domain="resource" name="disk" value="1GiB"/>
  <policy domain="resource" name="time" value="300"/>
</policymap>
''')
    package_records = []
    for name, (version, keg) in sorted(packages.items()):
        package_notice = notices / name
        package_notice.mkdir()
        formula = keg / ".brew" / (name + ".rb")
        formula_text = formula.read_text() if formula.exists() else ""
        if formula.exists():
            shutil.copy2(formula, package_notice / "build-formula.rb")
        source_urls = re.findall(r'^\s*url\s+["\']([^"\']+)', formula_text, re.M)
        license_line = next((line.strip() for line in formula_text.splitlines()
                             if line.strip().startswith("license ")), "See upstream source")
        found = 0
        for path in keg.rglob("*"):
            if path.is_file() and any(word in path.name.upper()
                                      for word in ["COPYING", "LICENSE", "NOTICE", "COPYRIGHT"]):
                relative = path.relative_to(keg)
                out = package_notice / relative
                out.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, out)
                found += 1
        receipt = keg / "INSTALL_RECEIPT.json"
        if receipt.exists():
            shutil.copy2(receipt, package_notice / receipt.name)
        package_records.append({"name": name, "version": version, "license": license_line,
                                "source_urls": source_urls, "license_files": found})
    file_records = [{"path": str(destination.relative_to(target)),
                     "bytes": destination.stat().st_size,
                     "minimum_macos": minimum_macos(destination),
                     "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}
                    for destination in copied.values()]
    manifest = {"engines": ["ffmpeg", "ffprobe", "magick"],
                "packages": package_records, "files": file_records,
                "redistribution_status": "Source archives and complete license notices must accompany releases"}
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    def version(value):
        return tuple(map(int, (value.split('.') + ['0', '0'])[:3]))
    incompatible = [record['path'] for record in file_records
                    if version(record['minimum_macos']) > version(args.maximum_minimum_macos)]
    if incompatible and not args.allow_newer_macos:
        raise SystemExit(f"Engine bundle cannot ship on macOS {args.maximum_minimum_macos}: "
                         f"{len(incompatible)} binaries require a newer OS. "
                         "Build compatible engines from source or stage compatible bottles.")
    (notices / "README.txt").write_text(
        "Media conversion uses FFmpeg and ImageMagick, plus the libraries listed in manifest.json.\n"
        "Exact installed Homebrew build formulas, receipts, and available notices are included here.\n"
        "Release distributions must include the corresponding source archives and all license notices.\n")
    environment = dict(__import__("os").environ,
                       MAGICK_CODER_MODULE_PATH=str(modules), MAGICK_CONFIGURE_PATH=str(config))
    for name in ["ffmpeg", "ffprobe", "magick"]:
        subprocess.run([str(binaries / name), "-version"], env=environment, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([str(binaries / "magick"), "xc:white", str(target / "probe.png")],
                   env=environment, check=True)
    (target / "probe.png").unlink()
    print(json.dumps({"destination": str(target), "packages": len(packages),
                      "macho_files": len(copied), "bytes": sum(p.stat().st_size
                                                               for p in target.rglob("*") if p.is_file())}))


if __name__ == "__main__":
    main()
