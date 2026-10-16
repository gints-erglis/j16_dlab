# Changelog

All notable changes to J16 Data Lab are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com), and the
project uses [Semantic Versioning](https://semver.org) (`vMAJOR.MINOR.PATCH`).

## [0.5.0] - 2026-10-12

### Upgrade note
- **Update the plugins together with the application.** The plugin interface changed and
  *Plugins > Install..* refuses a package built for the old one. Use
  `VideoAssembler-plugin-v2.1.0.zip` and `NANDReconstructor-plugin-v1.1.0.zip` with this
  version; 2.0.0 and 1.0.0 are for v0.4.0 and earlier.

### Added
- **Repair and extraction of damaged Apple (APFS) filesystems inside a case.** A new
  **Repair** tab lists the container and its volumes, rebuilds a file tree that will not
  walk, and writes the result out - on a disk, an image or an assembled array. It opens
  with a map of how each part of the filesystem is known: read in place, taken from a
  surviving copy, computed, assembled from fragments, or gone.
- **FileVault unlock** in the case's Encryption tab. The key is held for the session and
  used by repair, extraction and scanning alike.
- *Parse filesystem* falls through to the repair engine when the normal reader cannot open
  an Apple filesystem, and lists its volumes in the same tree as everything else.
- A Full scan can read an encrypted Apple volume through the unlocked key, as a second
  reading of the same source, so deleted files inside it can be carved.
- Transparently compressed Apple files (LZVN) are decoded on extraction instead of being
  written out as an undecoded `.decmpfs` payload.
- **RAID plugin, first public version (0.1.0):** binds image files and physical drives into
  one virtual disk. First shape: an Apple Fusion Drive.
- **Edit map** on the case's Map tab: *Change status..* re-labels sectors over a range, and
  *Import bad sectors..* reads a ddrescue mapfile or plain start/length lines.
- **Tick boxes in recovered file trees** with *Export checked..* / *Extract checked..*; the
  folder layout is kept at the destination.
- Folders can be exported from a filesystem parsed in a case. The export measures the
  selection first and shows a percentage; the status bar names the file being written.
- **Resolve extents..** on a scan re-measures where carved files end without reading the
  medium again to find them.
- The Tasks tab shows a speed for scans.

### Changed
- A Full scan of an assembled array reads where the array's content actually is, and steps
  over ranges the source declares unreadable instead of failing through them.
- Full scan always records APFS structures; the option is gone from the scan dialog.
- The structure viewer is a tab of its own beside Hex, opened with *Parse structure* from a
  disk, partition or file.
- The Encryption tab appears only when the case has an Apple filesystem or an unlocked key.
- Carved files from a Quick scan are not offered for export until their ends are measured.
- Tasks tab: denser rows, Speed ahead of Progress, columns resize normally, speed averaged
  over three seconds.
- A damaged file extracted on its own goes to the same `!Problem` folder as the rest and is
  named in `extraction.log`.
- Refreshed look: framed panels, visible divider handles, file-type icons. Both themes.

### Fixed
- A Full scan asked to look for no file types was looking for all of them.
- The application no longer crashes when it is closed, or when a plugin is disabled.
- A scan no longer writes each finding to the case separately, which stalled the window on
  scans that found a great deal.
- Copying one large file from the filesystem browser reports progress and can be cancelled
  part way.
- A reverse copy shows its speed.

### Known limits
- *Import bad sectors..* does not read PC-3000's own map format yet.
- LZFSE and LZBITMAP compression are not decoded; such a file is written as its `.decmpfs`
  payload and named in `extraction.log`.
- The RAID plugin assembles Apple Fusion Drives only.
## [0.4.0] - 2026-09-07

### Added
- **Reassembly of fragmented JPEG photographs.** *Reassemble fragmented JPEGs..* on the
  findings tree's JPEG row. JPEG carries neither a checksum nor an index, so a join is
  accepted only when the whole reassembled file decodes from the start, across the join,
  to its last MCU and ends at EOI.
- Photographs whose catalogued length was too short are corrected in place: the decoder
  knows how many MCUs the image owes and can run past a marker the extent walk refused.
- **Reassembled (n)** group under each carved type, listing the files an assembler put
  back together with their size, piece count and the method that proved each one.
- **Validate..** on a carved file or a recovered file, answered by whatever the format
  allows: a ZIP by its CRC32s, an MP4 by its box tree and sample table, a JPEG by decoding
  it. A carved file is read through its fragments, so a rejoined photograph is checked as
  the file it would be exported as.
- Export subfolders **by type, then state** (`JPG/Continued`, `JPG/Fragmented`,
  `JPG/Damaged`), now the default. Every file lands in exactly one.
- **Case > recent cases**: the last ten, newest first. A case on a drive that is not
  attached is greyed rather than dropped.

### Fixed
- Photographs are no longer reported as damaged for three ordinary things a JPEG may do:
  ending with a restart marker before EOI, ending with a stuffed padding byte
  (`FF 00 FF D9`), or carrying more than 64 KB of headers as EXIF with a thumbnail does.
  On one 57 GB card these three accounted for roughly four thousand files.
- The SOURCE and DESTINATION cards in Case Info draw their border again; their style had
  been written for a selector that could not match.

### Changed
- Reassembly reads the medium once rather than once per file, and skips photographs already
  proved whole - on a photo library, most of the medium.
- Where a filesystem is known, its allocation unit may make the search finer, never
  coarser: a carver recovers what a filesystem has forgotten, and on a reformatted card the
  data predates its current geometry.

### Known limits
- **Progressive JPEG is not judged** - about one photograph in twenty. It is reported as
  not judged, never as damaged. Arithmetic-coded and lossless JPEG likewise.
- Two fragments remain the limit, and a second fragment that was overwritten is gone.

## [0.3.0] - 2026-09-05

### Added
- Reassembly of bifragmented files: **Reassemble fragmented ZIP..** and **Reassemble
  fragmented MP4s..** on the findings tree's type rows. A ZIP join is proved by the
  archive's own CRC32; an MP4 join is checked against its sample table (which proves the
  layout, not the content).
- Verification of carved archives and video against their own indexes, which also reports
  a file whose structure is intact but whose data was overwritten.
- Export subfolders **by confidence** (`1-assembled` ... `6-unrated`), numbered so the
  trustworthy set sorts first. `manifest.csv` gained a `fragments` column.
- Full scan reports filesystem records when the Filesystems branch is selected.
- Update notice: a link in the status bar only when a newer release exists, an answer on
  demand in **Help > About**, and a toggle in **View > Preferences > Updates**. It sends
  nothing about the machine or its cases.

### Changed
- **Plugins no longer add commands to the case.** Everything the Video Assembler does is
  now in one view under **Tools**, over a drive or image chosen in the drive list. A case
  looks the same whether a plugin is installed or not.
- The video recovery engines moved into the plugin itself, so without the plugin the
  capability is absent rather than hidden.
- Tasks panel: Progress is a fixed-width column; Status takes the remaining space.

### Fixed
- The Filesystems checkbox in the scan dialog can be clicked in both scan modes; it was
  disabled in Full mode and showed a tick that could not be cleared.
- Stop now works for both reassembly tasks.

### Upgrade note
- Update the Video Assembler plugin to **2.0.0**. An older copy still loads but registers
  a command the application no longer shows, so it appears to do nothing.


## [0.2.0] - 2026-09-02

### Added
- Full scan

### Changed
- Plugins UI

### Fixed
- SMART: Exit status is a bit mask, not an enum. Values combining "device open failed" with useful data were being discarded - which mostly affected dying drives behind USB bridges, exactly the ones that matter. The reader now judges the payload, not the status word, and treats smartctl's own DISK FAILING bit as a failure signal.
- SMART: Capabilities come from the device. Polling times and self-test support are read from the SMART data buffer the app already holds, so the Self-Tests tab works on USB bridges that smartctl cannot open at all.


## [0.1.1] - 2026-07-12

User-interface polish for the main window.

### Added
- Collapsible left navigation panel: a chevron button (next to Refresh) collapses
  it to a slim strip; click the strip's chevron to restore it.

### Changed
- The detail tabs (Drive, Hex, Preferences, Case) now share a single flat row.
  Opening Preferences or a Case no longer creates a nested second row of tabs.

### Fixed
- The main splitter no longer lets the left panel be dragged over the detail
  region and hide it — both sides keep a sensible minimum width, and the divider
  shows hover feedback.

## [0.1.0] - 2026-07-11

First public release (Windows x64, portable).

### Added
- Disk imaging (device → image/device) with a live sector status map.
- Quick scan: filesystem detection, file-type carving, and TSK-based
  filesystem recovery (browse and recover files/folders).
- Case workflow (`.j16case`): findings tree, hex + structure inspection,
  submap (targeted range imaging to a destination).
- S.M.A.R.T. health reading (via bundled smartctl) and disk info.
- Open a raw `.img` as a pseudo-disk; mount / unmount.
- Preferences (theme + configurable font sizes), persisted.
- **Structure Viewer** plugin (bundled): disk-structure templates (MBR/GPT).
- **Video Assembler** plugin (separate download): carve, classify, validate and
  reassemble fragmented MP4/MOV and CCTV/DVR footage, including orphan
  moov/mdat header↔body matching and reassembly.
