#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
"""Measure comparable built bundles and isolated synthetic conversion workloads.

These CLI workloads do not measure Finder drag latency or application idle CPU.
The bundled profile measures actual production conversion calls and app resources.
The prototype profile preserves the original packaging comparison.
"""
import argparse
import json
import os
import re
import statistics
import subprocess
import tempfile
import time
import zipfile
from pathlib import Path


def files(root):
    return sorted(p for p in root.rglob("*") if p.is_file() and not p.is_symlink())


def bundle_size(root, extra=None):
    uncompressed = sum(p.stat().st_size for p in files(root))
    with tempfile.TemporaryFile() as output:
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in files(root):
                archive.write(path, root.name + "/" + str(path.relative_to(root)))
            if extra:
                for path in files(extra):
                    archive.write(path, root.name + "/Contents/Resources/MediaEngines/"
                                  + str(path.relative_to(extra)))
                    uncompressed += path.stat().st_size
        compressed = output.tell()
    return {"bundle_file_bytes": uncompressed, "zip_bytes": compressed}


def measured(command, environment, repeats=5):
    samples = []
    for _ in range(repeats):
        start = time.perf_counter()
        result = subprocess.run(["/usr/bin/time", "-l", *map(str, command)],
                                capture_output=True, text=True, env=environment)
        elapsed = time.perf_counter() - start
        if result.returncode:
            raise RuntimeError(result.stderr[-4000:])
        rss = re.search(r"(\d+)\s+maximum resident set size", result.stderr)
        cpu = re.search(r"([\d.]+)\s+real\s+([\d.]+)\s+user\s+([\d.]+)\s+sys", result.stderr)
        samples.append({"wall_seconds": elapsed, "peak_rss_bytes": int(rss.group(1)) if rss else None,
                        "user_seconds": float(cpu.group(2)) if cpu else None,
                        "system_seconds": float(cpu.group(3)) if cpu else None})
        # The native fixture runner prints exactly the new output path.
        if "--media-convert-benchmark" in command:
            output = Path(result.stdout.strip())
            source = Path(command[command.index("--media-convert-benchmark") + 1])
            if output.parent == source.parent and output.name != source.name:
                output.unlink(missing_ok=True)
    return {"median_wall_seconds": statistics.median(s["wall_seconds"] for s in samples),
            "median_time_peak_rss_bytes": statistics.median(s["peak_rss_bytes"] for s in samples),
            "samples": samples}


def process_tree_probe(command, environment):
    """Separate diagnostic run, so polling does not perturb timing samples.

    A sum of resident sizes double counts shared pages and is not a physical
    memory footprint. It does, however, reveal a native encoder child that
    /usr/bin/time around the test harness alone cannot account for.
    """
    with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
        process = subprocess.Popen(command, stdout=output, stderr=errors, env=environment)
        peak = 0
        peak_children = 0
        count = 0
        while process.poll() is None:
            table = subprocess.check_output(["ps", "-axo", "pid=,ppid=,rss="], text=True)
            rows = [list(map(int, line.split())) for line in table.splitlines() if line.strip()]
            tree = {process.pid}
            previous = None
            while previous != len(tree):
                previous = len(tree)
                tree.update(pid for pid, parent, _ in rows if parent in tree)
            rss = sum(kib * 1024 for pid, _, kib in rows if pid in tree)
            children = sum(kib * 1024 for pid, _, kib in rows if pid in tree and pid != process.pid)
            peak = max(peak, rss)
            peak_children = max(peak_children, children)
            count += 1
            time.sleep(0.05)
        if process.returncode:
            errors.seek(0)
            raise RuntimeError(errors.read().decode()[-4000:])
        return {"sampled_peak_sum_rss_bytes": peak, "sampled_children_peak_sum_rss_bytes": peak_children,
                "samples": count, "interval_seconds": 0.05,
                "note": "Separate run; shared pages double counted; short peaks may be missed."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-app", required=True, type=Path)
    parser.add_argument("--feature-app", required=True, type=Path)
    parser.add_argument("--engines", required=True, type=Path)
    parser.add_argument("--native-tests", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--profile", choices=["prototype", "bundled"], default="prototype")
    args = parser.parse_args()
    environment = dict(os.environ, LC_ALL="C")
    if args.profile == "prototype":
        environment.update(MAGICK_CODER_MODULE_PATH=str(args.engines.resolve() / "coders"),
                           MAGICK_CONFIGURE_PATH=str(args.engines.resolve() / "config"))
    elif not (args.feature_app / "Contents/Resources/MediaEngines/manifest.json").is_file():
        raise SystemExit("Bundled profile requires an app containing its engines")
    engines = args.engines.resolve()
    native = args.native_tests.resolve()
    report = {
        "environment": {"macos": subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(),
                        "chip": subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip(),
                        "ram_bytes": int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True))},
        "profile": args.profile,
        "sizes": ({"baseline": bundle_size(args.baseline_app),
                   "native_feature": bundle_size(args.feature_app),
                   "engine_packaging_prototype": bundle_size(args.feature_app, engines)}
                  if args.profile == "prototype" else
                  {"baseline": bundle_size(args.baseline_app),
                   "bundled_feature": bundle_size(args.feature_app),
                   "private_runtime": bundle_size(engines)}),
        "engine_manifest": json.loads((engines / "manifest.json").read_text()),
        "workloads": {},
        "limitations": ["Synthetic files on one Mac, five sequential warm runs per workload.",
                        "CPU seconds and maximum RSS are /usr/bin/time process accounting, not app idle overhead.",
                        "The test harness uses the actual conversion engine but is not a full app UI session.",
                        "Video encoder settings differ; timings are illustrative costs, not a quality-matched speed ranking.",
                        ("Prototype engines have not passed macOS 14 compatibility or release redistribution gates."
                         if args.profile == "prototype" else
                         "The compatible runtime is integrated, but the full requested tool catalog is not finished.")]}
    for label, app in [("baseline_selftest", args.baseline_app), ("feature_selftest", args.feature_app)]:
        report["workloads"][label] = measured([str(app.resolve() / "Contents/MacOS/Vorssaint"), "--selftest"],
                                               environment)
    with tempfile.TemporaryDirectory(prefix="vorssaint-conversion-benchmark-") as temporary:
        work = Path(temporary)
        png = work / "Synthetic24MP.png"
        video = work / "Synthetic1080p10s.mov"
        audio = work / "SyntheticAudio10s.wav"
        ffmpeg = engines / "bin/ffmpeg"
        magick = engines / "bin/magick"
        def generate(arguments):
            subprocess.run([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", *arguments],
                           check=True, env=environment)
        if args.profile == "prototype":
            generate(["-f", "lavfi", "-i", "testsrc2=size=6000x4000:rate=1", "-frames:v", "1", str(png)])
            generate(["-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=30", "-t", "10",
                      "-c:v", "prores_ks", "-profile:v", "0", str(video)])
            generate(["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "10", str(audio)])
            workloads = {
                "native_24mp_png_to_jpeg": [str(native), "--media-convert-benchmark", str(png), "jpg"],
                "magick_24mp_png_to_jpeg": [str(magick), str(png), "-quality", "85", str(work / "magick.jpg")],
                "native_1080p_video_to_mp4": [str(native), "--media-convert-benchmark", str(video), "mp4"],
                "ffmpeg_1080p_video_to_mp4": [str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
                                               "-i", str(video), "-c:v", "h264_videotoolbox", "-b:v", "8M",
                                               str(work / "ffmpeg.mp4")],
                "native_10s_wav_to_m4a": [str(native), "--media-convert-benchmark", str(audio), "m4a"],
                "ffmpeg_10s_wav_to_m4a": [str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
                                          "-i", str(audio), "-c:a", "aac", "-b:a", "128k", str(work / "ffmpeg.m4a")],
            }
        else:
            # No lavfi input device is shipped. Deterministic local fixtures use
            # only Python's standard library and the bundle's real file inputs.
            import math
            import struct
            import wave
            import zlib
            def chunk(kind, data):
                return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
            width, height = 6000, 4000
            compressor = zlib.compressobj()
            encoded = bytearray()
            for y in range(height):
                row = bytes(component for x in range(width)
                            for component in (x * 255 // width, y * 255 // height, (x + y) % 256))
                encoded.extend(compressor.compress(b"\0" + row))
            encoded.extend(compressor.flush())
            png.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                            + chunk(b"IDAT", encoded) + chunk(b"IEND", b""))
            with wave.open(str(audio), "wb") as out:
                out.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
                out.writeframes(b"".join(struct.pack("<hh", *(2 * [int(8192 * math.sin(2 * math.pi * 440 * i / 48000))]))
                                         for i in range(480000)))
            generate(["-loop", "1", "-framerate", "30", "-i", str(png), "-i", str(audio),
                      "-t", "10", "-vf", "scale=1920:1080", "-threads", "4",
                      "-c:v", "prores_ks", "-profile:v", "0", "-c:a", "pcm_s16le", str(video)])
            report["fixture_description"] = "24 MP RGB gradient; 10 s 1080p30 static ProRes MOV with stereo audio; 10 s stereo 48 kHz PCM sine wave."
            report["limitations"].append("Fixtures differ from the original prototype's testsrc2 video; cross-report timing comparisons are not controlled.")
            workloads = {}
            for label, source, fmt in [("24mp_png_to_jpeg", png, "jpg"),
                                       ("1080p_video_to_mp4", video, "mp4"),
                                       ("10s_wav_to_m4a", audio, "m4a")]:
                workloads["native_" + label] = [str(native), "--media-convert-benchmark", str(source), fmt]
                workloads["bundled_" + label] = [str(native), "--media-convert-benchmark", str(source), fmt,
                                                   "--engines", str(engines)]
            workloads["bundled_24mp_png_to_webp"] = [str(native), "--media-convert-benchmark", str(png), "webp",
                                                       "--engines", str(engines)]
        for label, arguments in workloads.items():
            report["workloads"][label] = measured(arguments, environment)
            report["workloads"][label]["process_tree_probe"] = process_tree_probe(arguments, environment)
            print(label, flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report["sizes"], indent=2))


if __name__ == "__main__":
    main()
