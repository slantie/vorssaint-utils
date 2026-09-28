# Shift-drag conversion: size, dependencies and performance

Measured on September 28, 2026 for issue #2254 and PR #2258.

This report covers the working native Shift-drag feature and a **packaging
prototype** for the broader conversion engines. The full Tangerine tool catalog
and Shift–Option editors are still being implemented. The prototype is not a
release build and does not establish the final size of that full feature.

## Comparable optimized app sizes

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

The app's installed users would not need Homebrew. The prototype script is a
build tool; it is **not wired into the app or release workflow yet**.

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

Compatible binaries need to be built or obtained before release. Engine source
archives and complete redistribution material also need to accompany release
artifacts. FFmpeg's [license guidance](https://ffmpeg.org/legal.html) requires
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
