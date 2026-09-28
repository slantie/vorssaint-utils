# Native archive adapter

This module links the libarchive ABI supplied by macOS (`libarchive.2`). It does
not ship or download a libarchive binary and does not invoke external helpers.
The macOS SDK supplies the linker stub but omits the public C headers, so this
module includes the unmodified headers from upstream libarchive v3.7.2:

- [archive.h](https://github.com/libarchive/libarchive/blob/v3.7.2/libarchive/archive.h), SHA-256 `f454bbb6b3c707d617f428ca1927afac8f2c082d846bbf4d21d37467c31ba914`
- [archive_entry.h](https://github.com/libarchive/libarchive/blob/v3.7.2/libarchive/archive_entry.h), SHA-256 `e0358da9fa8da5a97be41d0105a3ec2d7c39fa5aaaa3e7ab5b85d344ce31c15b`

The original BSD notices remain in the headers. `build.sh` also installs
`Resources/ArchiveHeaders-LICENSE.txt` with the app. Only established reader,
writer and entry functions are used. Running fixtures on a macOS 14 Mac remains
required before claiming execution compatibility with the minimum OS.

The stored RAR5 writer is Vorssaint source based on the public format description
at https://www.rarlab.com/technote.htm. It contains no UnRAR code or RAR compression
engine. RAR output uses method 0 and is intentionally uncompressed.
