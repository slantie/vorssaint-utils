# Tangerine public catalog coverage

Local implementation audit, September 29, 2026. Reference:
[Tangerine public catalog](https://tangerineformac.com/tools) and its public demo.
No installed Tangerine app was inspected. This is a working checklist, not a
claim of complete parity. Publication of the current implementation was approved
on September 29, 2026.

| Area | Implemented locally | Remaining work |
| --- | --- | --- |
| Finder workflow | Shift conversion wheel, Shift–Option PDF/image/archive/video/audio tools, floating editors, collision-safe outputs beside originals | Manual Finder verification of newly added tool families; screens/Spaces/accessibility checks |
| Image conversion | Native formats plus bundled WebP/AVIF/static SVG; image-to-PDF/DOCX; raster-embedded SVG output | Animated input coverage; unsupported interactive SVG is explicitly rejected |
| Photo editing | Exposure, brightness, contrast, saturation, sharpening, denoise, atmospheric-scattering dehaze, clarity, grain | Further visual validation |
| Image background | Solid/transparent/image background, full-resolution background decode, blur, corners, shadow | Further visual validation |
| Image crop/redaction | Area selection and numeric bounds, resize/aspect presets; movable solid/blur/pixelate areas burned into outputs | Additional interaction and keyboard checks |
| Collage | Grid, row/column/featured layout, dimensions, gaps, background, corners, input order | Further visual validation |
| Compression | Image quality/resize/target size; video dimension/target-size output | Remaining file types; video target-size error feedback |
| Metadata | PDF fields; image descriptive fields with all-property inspection/removal; video/audio file/track/chapter tags | Floating metadata UI verification; additional image field editing |
| Video | Trim, crop with audio, pitch-preserving speed, join mixed sizes on first canvas, single/all PNG frames, equal/custom splits, timed solid/blur/pixelate redaction | Frame/timecode controls and movable selection overlays added; further UI verification |
| Audio | Trim, two-pass loudness/true peak/range normalization with measured comparison, mono/stereo gains, timed bleep, waveform/still-image video | Silence detection, processed preview, waveform range/edge movement and individual channel preview added; further UI verification |
| PDF | Merge/reorder, page thumbnails/rotate/duplicate/remove, split default/custom ranges, compression, metadata, QR, equal-width export | Additional interaction/accessibility checks |
| Text/subtitles | UTF-8 TXT to PDF/all-page JPG/PNG/SRT/VTT; SRT/VTT/TXT conversions retain cue timings | Duration/offset/gap controls added; subtitle styling/position limitations documented below |
| Archives | ZIP/TAR/TAR.GZ/stored RAR conversion, extraction beside original, native system reader | Empty-container, CRC and depth-budget fixtures added; minimum-OS execution |
| Editing reliability | Image/PDF/video/audio undo/redo; per-file image/AV export progress, errors and retry | Generic conversion/extraction progress, partial success and retry added; further UI verification |
| Distribution | Source-built engines, notices/source archive/signing integration | Final size/CPU/memory report; minimum-OS execution and release signing gates |

## Verification completed for this increment

- 474 media checks pass, including actual exports through the staged bundled
  engines. These exercise image pixels, archive round trips, subtitle timings,
  PDF ranges/history, video/audio export duration/dimensions/audio presence,
  metadata edit/removal round trips, photo adjustments, SVG/Word exports, archive
  corruption and selection geometry.
- Computer Use verified the floating crop editor, undo and redo, and a 160 × 128
  PNG saved next to an unchanged 320 × 240 source. This does not verify the new
  Finder modifier gestures or every editor interaction.
- Computer Use verified the floating video trim editor, a saved 1.53-second
  result for a 0.5–2 second selection, and original/result playback controls.
  Latest UI additions compile but have not all been exercised through Computer Use.
- The relevant media/repository/localization selection passes 7,991 checks.
- No final performance claim is made for this unfinished increment.

The archive adapter adds a system-library module and pinned public BSD headers,
not another bundled executable/library or downloaded runtime dependency.
The runtime now has seven source-built projects and 19 runtime binaries, including
one additional statically linked SVG renderer. Meson/Ninja are build-only tools.

## Current limitations

Plain-text subtitle generation defaults to three seconds per nonempty line, with
editable duration, offset and gap; it cannot recover spoken timing from text.
Raster-to-SVG embeds PNG pixels and does not perform vector tracing. Static SVG
conversion rejects scripts, animation, external resources and unsafe dimensions.
SRT/VTT conversion preserves cue text
and timestamps, but not format-specific positioning/styling. Archive conversion
preserves file contents and names; it does not retain every filesystem metadata
field. Stored RAR output has no compression. Frame exports are limited to 5,000
frames, and outputs above that limit are rejected rather than silently truncated.

AV metadata removal retains chapter timing. MOV/M4A may need a blank chapter
title to retain a valid chapter-text track; source titles and personal tags are
removed. Codec/muxer technical tags can be generated by the output container.

## Upstream sync and final local checks

Merged upstream `main` at `5b7dea4486263a37949a7f77499de23f379906c8` into the
existing feature branch without conflicts. The post-sync full test executable
passes **105,981 checks**, including media 487, repository 246 and localization
7,406; preference cleanup also passes. The optimized app build has no compiler
warnings, and its bundled-engine verification and selftest pass. Earlier local
notch/switcher failures no longer reproduce after bringing in upstream changes.
This is not a local Swift 6.0.3, macOS 14 execution or notarization claim.

Recent interaction coverage includes two QR payloads detected in the installed
Developer app (one small and rotated); the user confirmed Finder drops add a PDF
to that overlay. Overlay saves now dismiss on complete success, preserving error
and retry controls after partial failures. PDF import provider fixtures exercise
retained page edits, provider order, atomic validation, undo and late cancellation.
The live interaction checks preceded the upstream sync; the synced optimized
build is covered by compilation, fixtures and selftest.
