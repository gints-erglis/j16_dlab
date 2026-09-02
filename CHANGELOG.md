# Changelog

All notable changes to J16 Data Lab are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com), and the
project uses [Semantic Versioning](https://semver.org) (`vMAJOR.MINOR.PATCH`).

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
