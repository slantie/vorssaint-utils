# PR #2258 review fixes

Local review audit, September 29, 2026. The three inline comments by `vorssaint`
were reread from GitHub; there are no additional issue-thread comments.
The current fixes were approved for publication on September 29. The table below
maps each review point to its implementation and regression evidence.

| Review point | Fix | Regression evidence |
| --- | --- | --- |
| Cancellation still reveals partial output or shows success after encoding | Completion checks batch ownership, cancellation and feature availability before presentation. Completed copies remain on disk. | `MediaFeatureTests.testFileDragCompletion` exercises an actual partial conversion and late cancellation; `FileJobWorkspaceTests` holds the main queue until encoding finishes, then cancels/disables before the callback. |
| Importing another PDF loses page edits | The workspace validates additions, preserves existing page identities/order/rotations/duplicates/removals and appends only new pages. | `PDFWorkspaceModelTests` saves and reopens the edited document after an import, checking contents and rotation; invalid/duplicate imports preserve the plan. |
| Metadata from the removed first PDF is saved into the remaining PDF | Metadata follows the current single source. Unsaved edits stay with the same source; failed reloads clear stale fields and block saving. | Workspace fixtures remove the first PDF, switch to metadata, save/reopen the remaining copy and verify its title/author/subject/keywords. |

The relevant local test selection passes 7,991 checks: media 474, repository 246,
and localization 7,271. Debug and optimized compilation pass without warnings; both selftests pass. Detailed catalog
coverage and interaction limits are recorded in `TANGERINE-CATALOG-CHECKLIST.md`;
these checks do not establish complete UI parity or minimum-OS execution.

## CI compile failure

Run [36452438239](https://github.com/vorssaint/vorssaint-utils/actions/runs/36452438239)
at published commit `eb9ca171` failed in both build jobs before selftest,
packaging or unit tests ran. Both compilers reported that
`FileDragDropSession(inputs:formats:)` was private: the synthesized memberwise
initializer inherited the access of the private stored state. Local Xcode 27
accepted the earlier construction, so local builds did not expose this failure.

An explicit internal `init(inputs:formats:)` now initializes the session without
exposing its prepared/consumed state. Existing drop regression fixtures exercise
construction, mouse-up ordering, cancellation, one-time consumption and writing a
valid PDF beside its source. The post-fix media suite passes 474 checks; the
optimized app build and its selftest also pass locally. CI must rerun after
publication; Swift 6.0.3 is not installed on this Mac, so this is not a claim of a
local run with that compiler.

## Close overlays after saving

PDF editors close only after a successful save. Generic conversion/extraction
jobs request dismissal only when every input row is saved, including after a
successful retry. Image and audio/video editors close when the save callback has
outputs and no remaining failures. Metadata editors close after writing their
copy. Failures keep editing/retry controls visible; cancelled or unavailable
jobs suppress success presentation. QR results and metadata inspection remain
readable until dismissed because they do not save a file.

The media suite passes 479 checks, including real TXT-to-PDF output, partial
failure followed by retry, and cancellation/feature-disablement guards for the
new successful-completion callback. The Developer build and selftest pass;
the updated app is installed and running. This validates completion decisions
and compilation; the latest window-close gestures across every tool family
have not all been manually exercised.

## PDF drops and QR presentation

The user confirmed the earlier empty scan was a PDF without a QR code. The QR
panel now shows its source filenames, scanning/error/empty/result states,
Scan again and Close controls, and a local-scanning footer instead of save-copy
text. QR file scanning propagates Vision failures instead of reporting them as
an empty scan and restricts this action to QR/micro-QR symbologies. Screen
barcode reading retains its existing matrix-code behavior.

Finder file-URL drops append PDFs through the existing workspace plan. Whole
batches validate before import, provider order is preserved, current page edits
remain intact, undo restores the previous plan, and delayed imports are ignored
after closing. Drops on page/document cards route to file import while their
internal text drags continue to reorder. Single-document metadata rejects
additional PDFs. Adding files to the QR overlay rescans the current input set.

The local media and localization selection passes 7,758 checks (media 487,
localization 7,271), including actual NSItemProvider loads, invalid mixed drops,
undo, cancelled imports and disabled/single-document guards. The Developer
build and selftest pass without compiler warnings. Computer Use verified two
payloads in the installed app from the three-page dummy PDF, including a small
rotated QR. The user then confirmed that a real Finder drop added another PDF
to the QR overlay while retaining both results. Organize-page/card drops have
provider regression coverage but were not separately exercised manually in
this follow-up.

## Verification after upstream sync

Merged upstream `main` at `b2ddae4f` without conflicts. The optimized build has no
compiler warnings, engine verification and selftest pass, and the full suite
passes 108,255 checks plus preference cleanup. Media 487, repository 246 and
localization 7,406 are included. Historical notch/switcher failures are resolved
by the upstream changes. Raw results are in
`benchmarks/media-sync-validation-2026-09-29.txt`.
Swift 6.0.3 and DMG packaging are covered by GitHub CI after publication, not by
this local run. The installed Developer app's UI checks preceded upstream sync.
