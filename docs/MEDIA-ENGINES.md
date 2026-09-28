# Bundled media engines

Vorssaint builds its private media runtime from pinned upstream sources with
`Tools/build-media-engines.py`. This replaces the Homebrew measurement prototype
whose binaries required macOS 27. The installed app does not invoke Homebrew,
search the user's PATH, download engines, or load codecs from a system installation.

## Build and verify

```sh
brew install cmake pkgconf
python3 Tools/build-media-engines.py
python3 Tools/verify-media-engines.py .build/media-engines/runtime
./build.sh --dev
./build.sh --test-suite=media
```

The default app build includes the runtime. For unrelated development,
`./build.sh --without-media-engines` retains the limited native conversion path.
Objects, downloaded archives and the resulting runtime stay in `.build/media-engines`.
Source archives are verified by SHA-256; AOM is pinned to its upstream Git commit
and archived without modifications. The recipe records configure arguments,
toolchain, SDK, package versions and binary hashes. Changing configure arguments
or the toolchain invalidates the corresponding build cache. Byte-for-byte
reproducibility across different Apple toolchains is not claimed.

The six projects are FFmpeg 9.0.2, LAME 4.0, Opus 1.6.1, libvpx 1.17.0,
libwebp 1.6.0 and AOM 3.15.1. The runtime has two executables and 16 real dynamic
libraries, with relative aliases. It uses system frameworks and zlib.
No ImageMagick, Homebrew codecs, OpenSSL, x264, x265 or network protocols are
part of this runtime. SVG/document/archive support is separate work.

All sources compile with an Apple Silicon target and macOS 14 deployment flags.
Verification checks the actual Mach-O minimum OS, architecture, signatures,
binary hashes, relative library search paths, private dependency resolution,
successful engine launches, and an encoder protocol list limited to `file` and `pipe`.
Declaring a macOS 14 target does not substitute for testing on a macOS 14 machine.

## Distribution

`build.sh` signs each private library and executable before sealing the app.
The manifest hashes are refreshed after distribution signing, since signing
changes Mach-O file bytes. The protected release workflow bundles the engines,
notarizes the app, and stages the matching
`vorssaint-media-sources-VERSION.tar.gz` beside the DMG. Both artifacts are
included in release hash verification. These changes do not publish a release.

The source artifact contains every exact upstream archive, the build recipe and
its manifest. License, notice, author and patent texts from the sources are
included in the app's `MediaEngines/notices` folder. About settings credits the
projects and opens the notices and corresponding sources. Developer builds open
their local source artifact; release builds link to the matching release asset.

FFmpeg and LAME are separate executables/libraries under their LGPL licenses;
the optional GPL and nonfree FFmpeg components are not enabled. Other project
notices are preserved. See the upstream
[FFmpeg license guidance](https://ffmpeg.org/legal.html) and the exact bundled
license texts. Maintainers must publish the matching source artifact with every
binary release and keep source links on download pages current.

## Conversion coverage and validation

With this runtime, the Shift-drag wheel supports video outputs MP4, MOV, MKV,
WebM, AVI, WMV, GIF and extracted MP3, and audio outputs MP3, M4A, WAV, FLAC,
OGG, Opus, AIFF and WMA. OGG output uses Opus in an Ogg container. Native image
outputs remain available; WebP and AVIF use the bundled encoder. Image orientation
is normalized through ImageIO before encoding. AVIF transparency is stored as
its separate lossless alpha image instead of being discarded.

Production-path fixtures encode and probe every listed audio/video output,
decode the audio containers back to PCM and the video containers back to MP4,
check retained audio, preserve source bytes and reject symbolic links. Image
fixtures check dimensions and retained WebP/AVIF alpha. Cancellation, collisions,
PNG-to-PDF and drag-release ordering retain their native regression checks.

PDFs now use native PDFKit, without another bundled dependency. Shift-drag
offers DOCX, JPG, PNG and TXT. Multi-page image exports create a new folder
containing every page at 300 DPI. Word export retains selectable text in reading
order, with page images when text is absent; it does not reconstruct the original
layout or perform OCR. Scanned PDFs consequently need OCR before TXT export.

Shift–Option dragging PDFs opens split, merge, page organization, compression
or standard document metadata tools. The same tools are accessible from the
Media view's PDF tools menu. Merge starts with Finder's selection order;
organization supports drag reordering, earlier/later controls, rotation,
duplication and removal. Split saves one PDF per page in a new folder.
Compression optimizes embedded images and may not reduce the size of every
document. Metadata edits title, author, subject and keywords; it does not claim
to remove every embedded metadata object. Password-locked or restricted inputs
are rejected. Originals and existing outputs are preserved.

The full requested catalog is **not complete**: subtitle/archive conversion
and the remaining image/video/audio tool editors remain. The earlier impact report
still describes the original native feature and its measurement prototype;
the finished feature needs new comparable size and performance measurements.
