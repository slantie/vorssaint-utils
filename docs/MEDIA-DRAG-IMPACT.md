# Shift-drag conversion: size, dependencies and performance

Measured on September 28, 2026 for issue #2254 and PR #2258.

The original measurements cover the native Shift-drag feature and a **packaging
prototype**. The compatible bundled-runtime update below measures the actual
engine integration. The full Tangerine tool catalog
and Shift–Option editors are still being implemented. The prototype is not a
release build and does not establish the final size of that full feature.

## Build after upstream sync, September 29

After merging upstream `main` at `5b7dea44`, the optimized bundle contains
**116.67 MB** of app files and a comparable **41.01 MB** ZIP. The private engine
runtime remains **34.92 MB**. Exact counts are in
[post-sync size evidence](benchmarks/media-synced-size-2026-09-29.json).
A matching build of current upstream without the feature was not measured.
Therefore the historical feature delta below must not be applied to this synced
bundle: it includes intervening upstream application changes. No new idle CPU,
launch, Finder latency or complete-catalog performance claim is made.

## Local catalog expansion before upstream sync, September 29

This local optimized build measures **113.62 MB** of app files and a comparable
**40.24 MB** ZIP. Against the historical baseline (**75.28 MB / 24.09 MB**), this
adds **38.34 MB (50.93%)** to app files and **16.14 MB (67.01%)** to the ZIP.
The baseline was reused from the previous report, not rebuilt this time.

The bundle has seven source-built projects and 19 runtime binaries. ThorVG adds
one statically linked SVG renderer; pinned Meson/Ninja are build-only tools.
The private runtime is **34.92 MB**, including notices and signed manifest.
Archive support uses macOS libarchive with pinned BSD headers and no extra
bundled archive runtime. Package.swift adds a system-library target rather than
a downloaded Swift package dependency.

[Raw size evidence](benchmarks/media-catalog-size-2026-09-29.json) contains exact
byte counts and the signed engine manifest. Expanded conversion workloads,
GUI idle CPU/memory, UI launch and Finder latency have not been remeasured;
the historical runtime timings below are not a finished-catalog performance claim.
See the [coverage checklist](TANGERINE-CATALOG-CHECKLIST.md) for implemented scope,
UI verification and remaining limitations. Publication was approved on
September 29, 2026.

## Native PDF tools increment

The local review fixes and reference-style floating panels now measure
**110.47 MB** of app files and a comparable **39.42 MB** ZIP. This is
**0.74 MB / 0.17 MB** above the earlier compatible-engine build, or
**35.18 MB / 15.33 MB** above the original baseline. No additional third-party
dependency was introduced; PDF QR scanning reuses the existing Vision decoder.
These measurements precede the later catalog and upstream sync updates.

The optimized app with PDF conversion and the split/merge/organize/compress/
metadata workspace measures **110.15 MB**, with a comparable **39.36 MB** ZIP.
Relative to the earlier compatible-engine build below, this adds **0.42 MB**
of app files and **0.11 MB** of ZIP bytes. PDFKit adds no third-party dependency;
the six bundled source projects and private engines are unchanged. Relative to
the original baseline, the app increment is 34.87 MB (46.32%) and the ZIP
increment is 15.27 MB. These are still intermediate-catalog measurements.

See [raw PDF size evidence](benchmarks/media-pdf-impact-2026-09-28.json) and
[PDF validation results](benchmarks/media-pdf-validation-2026-09-28.txt).
The latest 272-check media suite, 246-check repository suite and debug/optimized
selftests pass. Computer Use verified the floating organizer and saved output
after removing, rotating and reordering pages before appending another PDF.
The current Finder modifier-drag flow still needs manual verification.
No new PDF runtime or idle performance claim is made from build or size checks.

## Compatible bundled-runtime update before PDF tools

The source-built runtime now replaces the incompatible Homebrew prototype.
This is an **intermediate implementation**, with audio/video conversion and
WebP/AVIF integrated; PDF routes were added in the increment above. Archive,
subtitle and the remaining Shift–Option editors
remain. The measurements below do not establish the finished catalog’s size.

| Optimized variant | App files | Comparable ZIP |
| --- | ---: | ---: |
| Baseline without feature (`9be00fbc`) | 75.28 MB | 24.09 MB |
| Compatible bundled engines before PDF tools | 109.73 MB | 39.25 MB |

The current increment is **34.45 MB / 45.76%** in app files and **15.16 MB**
in the comparable ZIP. Its private runtime, including notices and manifest,
is **34.22 MB**. This is 19.63 MB smaller than the earlier 53.85 MB payload,
while the prototype also included ImageMagick support absent from this runtime.
Different format coverage prevents treating that difference as an equivalent
replacement-size comparison.

There are **six source-built third-party projects**: FFmpeg, LAME, Opus, libvpx,
libwebp and AOM; two executables and 16 real dynamic libraries. Package.swift
still has no added dependencies. All 18 actual Mach-O binaries declare macOS
14 and Apple Silicon. Private dependencies, signatures, source checksums and
file-only protocols passed verification. The app bundles license notices and
the release workflow stages the matching source archive. These checks do not
replace execution on a macOS 14 Mac or real Developer ID notarization.

Five warm production-path runs on the same M5 / 16 GB / macOS 27.2 machine:

| Synthetic conversion | Native fallback | Bundled production path |
| --- | ---: | ---: |
| 24 MP gradient PNG → JPEG | 0.156 s | 0.158 s (same native image path) |
| 10 s 1080p30 ProRes MOV with stereo audio → MP4 | 3.076 s | 1.258 s |
| 10 s stereo 48 kHz WAV → M4A | 0.073 s | 0.112 s |
| 24 MP gradient PNG → WebP | unavailable | 1.148 s |

Video and audio encoder settings differ between paths; this is **not a
quality-matched speed comparison**. These fixtures also differ from the original
prototype fixtures, so cross-report timing comparisons are uncontrolled.
`/usr/bin/time` RSS accounting peaked around 410 MB for JPEG, 188 MB for bundled
video and 314 MB for WebP. A separate video process-tree probe sampled about
199 MB summed RSS, including 186 MB in the encoder child. Shared pages are
counted more than once and short peaks may be missed; none of these values
represents extra memory in the running GUI app.

Warm selftest medians were 0.203 s baseline and 0.226 s bundled; the latter also
launches both private engines for its health check. This is not UI launch time.
New idle CPU, UI startup and Finder latency measurements remain pending; the
Mac was locked during this increment’s Computer Use validation.

[Raw compatible-runtime evidence](benchmarks/media-bundled-impact-2026-09-28.json)
records exact file sizes, versions, signed binary hashes and every timing sample.
The optimized Swift app uses the same MacOSX26 SDK as the baseline; engine C/C++
sources were compiled with Xcode 27’s SDK and an explicit macOS 14 target.
Source recipe, build flags, signing and redistribution are described in
[engine packaging](MEDIA-ENGINES.md). Reproduce this update with:

```sh
python3 Tools/measure-media-feature.py --profile bundled \
  --baseline-app /path/to/baseline/Vorssaint.app \
  --feature-app build/stage/Vorssaint.app \
  --engines build/stage/Vorssaint.app/Contents/Resources/MediaEngines \
  --native-tests build/metrics-tests \
  --output /tmp/vorssaint-bundled-impact.json
```

## Original native/prototype measurements

### Comparable optimized app sizes

Both app variants were built with `./build.sh`, `-O`, the same MacOSX26 SDK,
toolchain and resources. Baseline: `9be00fbc`. Native feature: `6350dbcc`.
MB below means 1,000,000 bytes. App size is the sum of regular file sizes;
filesystem allocation can differ. ZIP figures use the same deflate level 6,
not the project's DMG format.

| Variant | App files | Comparable ZIP | Increase in app files |
| --- | ---: | ---: | ---: |
| Without the feature | 75.28 MB | 24.09 MB | — |
| Current native Shift-drag feature | 75.45 MB | 24.14 MB | 0.16 MB / 0.22% |
| Native feature plus engine packaging prototype | 129.30 MB | 46.20 MB | 54.02 MB / 71.75% |

The engine payload itself is **53.85 MB**. Its compressed increment is
**22.06 MB**, compared with the native feature. The remaining tool UI,
document/archive routes, metadata support, complete source distribution and
future codec choices can change these totals.

## Dependency increase

The native feature introduces **zero third-party packages**. It uses frameworks
already used by Vorssaint and macOS's `avconvert` and `afconvert`. `Package.swift`
has no added dependency.

The prototype stages two engine projects, **FFmpeg and ImageMagick**, from
Homebrew. It contains three executables (`ffmpeg`, `ffprobe`, `magick`),
35 dynamic libraries and 10 selected image coder modules. In total, its files
come from **24 Homebrew packages**:

`aom`, `dav1d`, `ffmpeg`, `freetype`, `imagemagick`, `jpeg-turbo`, `lame`,
`libde265`, `libheif`, `libpng`, `libtiff`, `libtool`, `libvmaf`, `libvpx`,
`little-cms2`, `mpg123`, `openssl@3`, `opus`, `svt-av1`, `webp`, `x264`,
`x265`, `xz`, `zstd`.

These dependencies introduce codec updates, library compatibility, signing and
redistribution maintenance. The script records exact versions, binary hashes,
Homebrew formulas, receipts and available license notices in a manifest.

The prototype was never wired into the app or release workflow. The compatible
source-built runtime described above is now integrated.

## Runtime measurements

Machine: Apple M5, 16 GB RAM, macOS 27.2. All conversion fixtures were synthetic
local files. Five sequential timing runs per workload; figures are medians.
Fixture creation was excluded. The native cases call the actual production
conversion engine from the test executable.

### Idle app

Twenty-second CPU intervals were sampled with settings closed. CPU percentage is
the fraction of one CPU core, based on the process's accumulated CPU time. The
off/on/off trials use the same running optimized feature app and preferences.

| Session | CPU | Median resident memory |
| --- | ---: | ---: |
| Baseline app | 0.60% | 304.92 MB |
| Feature app, Shift-drag off | 0.89% | 358.11 MB |
| Same feature app, Shift-drag on | 1.19% | 287.44 MB |
| Same feature app, Shift-drag off again | 1.29% | 262.44 MB |

The initial on/off difference was +0.30 percentage points, but turning the
feature off did not reverse it. Resident memory also decreased across these
sessions. This live-Mac experiment **cannot attribute a precise CPU or memory
increase to the feature**. It does not justify claiming zero overhead or a
percentage slowdown. Background activity, UI warm-up and memory pressure were
not controlled. Drag latency, energy use and older Macs were not measured.

### Active conversion costs

| Workload | Native engine | Prototype engine |
| --- | ---: | ---: |
| 24 MP PNG → JPEG | 0.239 s | 0.276 s, ImageMagick |
| 10 s, 1080p30 ProRes MOV → MP4 | 3.053 s | 1.251 s, FFmpeg |
| 10 s, 48 kHz WAV → M4A | 0.047 s | 0.075 s, FFmpeg |

These are costs for specific fixtures, **not a quality-matched speed ranking**.
For example, native video uses `PresetHighestQuality`, while the FFmpeg case
uses VideoToolbox H.264 at 8 Mbit/s. They do not produce identical files.

The image cases reached approximately **404.82 MB** maximum process RSS with
the native engine and **365.23 MB** with ImageMagick. The FFmpeg video case
reached **216.92 MB**. These are conversion-process measurements, not additional
memory measured inside the running GUI app.

A separate process-tree probe sampled native video at 44.86 MB summed RSS
(including 28.66 MB in its encoder child). Summed RSS double counts shared
pages; short peaks can be missed. macOS can delegate media work to XPC services
outside that tree. Consequently it is not a complete physical-memory estimate.
The audio jobs were too short for reliable sampled process-tree peaks.

The selftest took 0.200 s in the baseline and 0.195 s with the native feature;
maximum process RSS was 41.57 MB and 41.70 MB. This is a health-check comparison,
**not a full UI startup benchmark**.

## Packaging findings and remaining gates

The FFmpeg 9.0.2 and ImageMagick 7.1.2-32 installed on this Mac, and some of their
libraries, have a **macOS 27 minimum deployment version**. Vorssaint supports
macOS 14. Those binaries cannot be shipped as this feature's final engines.
The staging tool now rejects newer minimum deployment versions by default;
measurement prototypes require an explicit flag.

These were the prototype’s outstanding gates. The compatible source build and
matching source redistribution described above now replace those binaries;
macOS 14 execution and official signing/notarization remain unverified here. FFmpeg's [license guidance](https://ffmpeg.org/legal.html) requires
corresponding sources for its distributed code; ImageMagick's
[license](https://imagemagick.org/license/) requires attribution and license
notices. The prototype's manifest and copied notices do not replace that work.

The working native build remains available while the full catalog is completed.
The final PR should repeat these measurements after the actual bundled engines,
all editors and release packaging are in place.

## Reproduction and evidence

Raw measurements, dependency versions, hashes and minimum OS versions:
[benchmark JSON](benchmarks/media-drag-impact-2026-09-28.json).

From two separate source snapshots, build both optimized app bundles, then run:

```sh
./build.sh --test-suite=media
python3 Tools/prepare-media-engines.py /tmp/vorssaint-engines \
  --allow-newer-macos
python3 Tools/measure-media-feature.py \
  --baseline-app /path/to/baseline/build/stage/Vorssaint.app \
  --feature-app /path/to/feature/build/stage/Vorssaint.app \
  --engines /tmp/vorssaint-engines \
  --native-tests build/metrics-tests \
  --output /tmp/vorssaint-impact.json
```

The staging command uses build prerequisites `brew install ffmpeg imagemagick`.
Its `--allow-newer-macos` option is for measurement only. Idle observations were
performed separately using Computer Use to toggle the setting and `ps` to sample
the app. The measurement script does not drive Finder or change preferences.
