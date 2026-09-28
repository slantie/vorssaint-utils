#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
"""Build pinned, relocatable Apple Silicon media engines for macOS 14.

Build prerequisites: Xcode Command Line Tools, cmake, pkgconf. No installed
Homebrew codec library is used. The installed app needs none of these tools.
Outputs: runtime/, corresponding-sources.tar.gz, and build logs/manifest.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile

SOURCES = [
    ("lame", "4.0", "https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz",
     "3df5124d5ad3a98312ffd7ba6a9b36230e4f8a3e66d3ce0f425e336c32d216eb"),
    ("opus", "1.6.1", "https://ftp.osuosl.org/pub/xiph/releases/opus/opus-1.6.1.tar.gz",
     "6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"),
    ("libvpx", "1.17.0", "https://github.com/webmproject/libvpx/archive/refs/tags/v1.17.0.tar.gz",
     "1020f184046187baa2985dbde38e0691f49c44088bca7a1842b0236c6081dc0a"),
    ("webp", "1.6.0", "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz",
     "e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564"),
    ("aom", "3.15.1", "https://aomedia.googlesource.com/aom.git",
     "44d0a57786f432d933ff64b653347c66f4d0fa1d"),
    ("ffmpeg", "9.0.2", "https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz",
     "8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"),
]


AOM_ARCHIVE_SHA256 = "dc0e5c1e2fabc7756fda36443936f0ca99e96e5d9ba413f992f660fd035e7c2d"

def capture(*args):
    return subprocess.check_output(args, text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, default=Path(".build/media-engines"))
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 2))
    parser.add_argument("--stage-only", action="store_true", help="Restage a previously completed local build")
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("This recipe targets Apple Silicon macOS.")
    for tool in ["cmake", "pkg-config", "clang", "make", "git"]:
        if not shutil.which(tool):
            raise SystemExit(f"Missing build prerequisite: {tool}")
    work = args.work.resolve()
    for folder in ["downloads", "sources", "objects", "logs", "prefix"]:
        (work / folder).mkdir(parents=True, exist_ok=True)
    prefix = work / "prefix"
    sdk = capture("xcrun", "--sdk", "macosx", "--show-sdk-path")
    flags = f"-O2 -fPIC -mmacosx-version-min=14.0 -isysroot {sdk}"
    env = dict(os.environ, MACOSX_DEPLOYMENT_TARGET="14.0", CC="clang", CXX="clang++",
               CFLAGS=flags + " -std=gnu17", CXXFLAGS=flags, LDFLAGS="-mmacosx-version-min=14.0",
               PKG_CONFIG_LIBDIR=str(prefix / "lib/pkgconfig"), PKG_CONFIG_PATH="",
               CMAKE_PREFIX_PATH=str(prefix), SOURCE_DATE_EPOCH="0")
    records = []
    commands = []

    def run(argv, cwd, log):
        commands.append({"argv": list(map(str, argv)), "cwd": str(cwd)})
        with log.open("a") as out:
            process = subprocess.run(list(map(str, argv)), cwd=cwd, env=env,
                                     stdout=out, stderr=subprocess.STDOUT)
        if process.returncode:
            raise RuntimeError(f"Build failed: {argv[0]}; inspect {log}")

    for name, version, url, expected in SOURCES:
        label = f"{name}-{version}"
        log = work / "logs" / f"{label}.log"
        source = work / "sources" / label
        archive = work / "downloads" / (label + (".tar.xz" if name == "ffmpeg" else ".tar.gz"))
        print(f"Building {label}", flush=True)
        if name == "aom":
            if not archive.exists():
                repository = work / "downloads/aom-git"
                if not repository.exists():
                    run(["git", "clone", "--depth=1", "--branch=v" + version, url, repository], work, log)
                if capture("git", "-C", str(repository), "rev-parse", "HEAD") != expected:
                    raise RuntimeError("AOM source revision differs from the pinned commit")
                run(["git", "-C", repository, "archive", "--format=tar.gz", "--prefix=" + label + "/",
                     "--output=" + str(archive), expected], work, log)
            if digest(archive) != AOM_ARCHIVE_SHA256:
                raise RuntimeError("AOM source archive checksum mismatch")
        else:
            if not archive.exists():
                temporary = archive.with_suffix(archive.suffix + ".partial")
                run(["curl", "--fail", "--location", "--retry", "3", "--output", temporary, url], work, log)
                if digest(temporary) != expected:
                    raise RuntimeError(f"Source checksum mismatch: {label}")
                temporary.rename(archive)
            if digest(archive) != expected:
                raise RuntimeError(f"Cached source checksum mismatch: {label}")
        if not source.exists():
            source.mkdir()
            run(["tar", "-xf", archive, "-C", source, "--strip-components=1"], work, log)
        objects = work / "objects" / label
        objects.mkdir(exist_ok=True)
        cmake = ["cmake", "-S", source, "-B", objects, "-DCMAKE_BUILD_TYPE=Release",
                 "-DCMAKE_INSTALL_PREFIX=" + str(prefix), "-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0",
                 "-DCMAKE_OSX_ARCHITECTURES=arm64", "-DCMAKE_OSX_SYSROOT=" + sdk,
                 "-DBUILD_SHARED_LIBS=ON"]
        if name == "lame":
            configure = [source / "configure", "--prefix=" + str(prefix), "--enable-shared",
                         "--disable-static", "--disable-frontend", "--disable-decoder"]
        elif name == "opus":
            configure = [source / "configure", "--prefix=" + str(prefix), "--enable-shared",
                         "--disable-static", "--disable-doc", "--disable-extra-programs"]
        elif name == "libvpx":
            configure = [source / "configure", "--prefix=" + str(prefix), "--target=arm64-darwin23-gcc",
                         "--enable-shared", "--disable-static", "--enable-pic", "--enable-vp9-highbitdepth",
                         "--disable-examples", "--disable-tools", "--disable-unit-tests", "--disable-docs"]
        elif name == "webp":
            configure = cmake + ["-DWEBP_BUILD_ANIM_UTILS=OFF", "-DWEBP_BUILD_CWEBP=OFF",
                                 "-DWEBP_BUILD_DWEBP=OFF", "-DWEBP_BUILD_GIF2WEBP=OFF",
                                 "-DWEBP_BUILD_IMG2WEBP=OFF", "-DWEBP_BUILD_VWEBP=OFF",
                                 "-DWEBP_BUILD_WEBPINFO=OFF", "-DWEBP_BUILD_WEBPMUX=OFF",
                                 "-DWEBP_BUILD_EXTRAS=OFF"]
        elif name == "aom":
            configure = cmake + ["-DENABLE_DOCS=OFF", "-DENABLE_EXAMPLES=OFF", "-DENABLE_TESTS=OFF",
                                 "-DENABLE_TESTDATA=OFF", "-DENABLE_TOOLS=OFF", "-DCONFIG_TUNE_VMAF=0"]
        else:
            configure = [source / "configure", "--prefix=" + str(prefix), "--arch=arm64", "--target-os=darwin",
                         "--cc=clang", "--cxx=clang++", "--disable-autodetect", "--disable-static",
                         "--enable-shared", "--enable-pic", "--disable-debug", "--disable-doc",
                         "--disable-ffplay", "--disable-network", "--disable-indevs", "--disable-outdevs",
                         "--disable-protocols", "--enable-protocol=file,pipe", "--enable-videotoolbox",
                         "--enable-audiotoolbox", "--enable-libmp3lame", "--enable-libopus", "--enable-libvpx",
                         "--enable-libwebp", "--enable-libaom", "--enable-zlib", "--extra-cflags=" + flags + " -I" + str(prefix / "include"),
                         "--extra-ldflags=-mmacosx-version-min=14.0 -L" + str(prefix / "lib")]
        # The marker includes the recipe and toolchain: changing either forces
        # reconfiguration. Sources are unmodified; all objects stay separate.
        key = hashlib.sha256(json.dumps([configure, env["CFLAGS"], env["CXXFLAGS"], env["LDFLAGS"],
                                         capture("clang", "--version"), expected], default=str).encode()).hexdigest()
        marker = objects / "completed-recipe.txt"
        if args.stage_only and not marker.exists():
            raise RuntimeError(f"No completed build for {label}")
        if not args.stage_only and (not marker.exists() or marker.read_text() != key):
            run(configure, objects, log)
            if name in ["webp", "aom"]:
                run(["cmake", "--build", objects, "--parallel", str(args.jobs)], objects, log)
                run(["cmake", "--install", objects], objects, log)
            else:
                run(["make", "-j" + str(args.jobs)], objects, log)
                run(["make", "install"], objects, log)
            marker.write_text(key)
        records.append({"name": name, "version": version, "source_url": url,
                        "source_identity": expected, "archive": archive.name, "sha256": digest(archive),
                        "configure": list(map(str, configure))})

    runtime = work / "runtime"
    if runtime.exists():
        shutil.rmtree(runtime)  # Only this recipe's generated staging output.
    for folder in ["bin", "lib", "notices"]:
        (runtime / folder).mkdir(parents=True)
    for name in ["ffmpeg", "ffprobe"]:
        shutil.copy2(prefix / "bin" / name, runtime / "bin" / name)
    for library in (prefix / "lib").glob("*.dylib"):
        if not library.is_symlink():
            shutil.copy2(library, runtime / "lib" / library.name)
    # Preserve only relative library aliases, never build-machine paths.
    for library in (prefix / "lib").glob("*.dylib"):
        if library.is_symlink():
            (runtime / "lib" / library.name).symlink_to(library.resolve().name)
    binaries = list((runtime / "bin").iterdir()) + [p for p in (runtime / "lib").iterdir() if not p.is_symlink()]
    for binary in binaries:
        dependencies = capture("otool", "-L", str(binary)).splitlines()[1:]
        changes = []
        for dependency in dependencies:
            path = dependency.strip().split(" (", 1)[0]
            if path.startswith(str(prefix)) or ("/" not in path and (prefix / "lib" / path).is_file()):
                changes += ["-change", path, "@rpath/" + Path(path).name]
            elif not path.startswith(("/usr/lib/", "/System/Library/", "@rpath/")):
                raise RuntimeError(f"Unexpected external dependency {path} in {binary}")
        if binary.parent.name == "lib":
            changes += ["-id", "@rpath/" + binary.name]
        load_commands = capture("otool", "-l", str(binary))
        for path in re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset", load_commands):
            changes += ["-delete_rpath", path]
        changes += ["-add_rpath", "@loader_path/../lib"]
        run(["install_name_tool", *changes, binary], work, work / "logs/staging.log")
        run(["codesign", "--force", "--sign", "-", binary], work, work / "logs/staging.log")
        load_commands = capture("otool", "-l", str(binary))
        minimum = re.search(r"\bminos (\S+)", load_commands)
        if not minimum or tuple(map(int, (minimum[1].split(".") + ["0", "0"])[:3])) > (14, 0, 0):
            raise RuntimeError(f"Incompatible minimum OS in {binary}")
    for name, version, _, _ in SOURCES:
        source = work / "sources" / f"{name}-{version}"
        for path in source.rglob("*"):
            if path.is_file() and any(word in path.name.upper() for word in ["LICENSE", "COPYING", "NOTICE", "PATENTS", "AUTHORS"]):
                target = runtime / "notices" / name / path.relative_to(source)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
    manifest = {"schema": 1, "target": "arm64-apple-macos14", "packages": records,
                "files": [{"path": str(p.relative_to(runtime)), "bytes": p.stat().st_size, "sha256": digest(p)} for p in binaries],
                "toolchain": capture("clang", "--version"), "sdk": sdk,
                "sources_artifact": "corresponding-sources.tar.gz"}
    (runtime / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (runtime / "notices/README.txt").write_text(
        "Media conversion uses FFmpeg (LGPL-2.1-or-later), LAME (LGPL-2.0-or-later), "
        "Opus, libvpx, libwebp and AOM. Full notices are included in this folder.\n"
        "The matching corresponding-sources.tar.gz is distributed alongside the app.\n"
        "Engines run as separate local executables. No source changes were applied.\n")
    with tarfile.open(work / "corresponding-sources.tar.gz", "w:gz") as out:
        for record in records:
            out.add(work / "downloads" / record["archive"], arcname="archives/" + record["archive"])
        out.add(Path(__file__), arcname="build-media-engines.py")
        out.add(runtime / "manifest.json", arcname="manifest.json")
        out.add(Path(__file__).with_name("verify-media-engines.py"), arcname="verify-media-engines.py")
        import io
        instructions = (
            "Corresponding media engine sources for Vorssaint\n\n"
            "Prerequisites: Apple Silicon Mac, Xcode Command Line Tools, CMake, pkgconf.\n"
            "Sources are unmodified. All archives are pinned and SHA-256 verified.\n"
            "To rebuild using these archives without fetching upstream sources:\n"
            "  mkdir -p engine-build/downloads\n"
            "  cp archives/* engine-build/downloads/\n"
            "  python3 build-media-engines.py --work engine-build\n"
            "  python3 verify-media-engines.py engine-build/runtime\n"
            "The manifest records the original toolchain and configuration.\n"
            "Different Apple toolchains may produce different binary bytes.\n"
        ).encode()
        info = tarfile.TarInfo("README.txt")
        info.size = len(instructions)
        out.addfile(info, io.BytesIO(instructions))
    (work / "build-commands.json").write_text(json.dumps(commands, indent=2) + "\n")
    for name in ["ffmpeg", "ffprobe"]:
        run([runtime / "bin" / name, "-version"], work, work / "logs/staging.log")
    print(f"Runtime ready: {runtime}", flush=True)


if __name__ == "__main__":
    main()
