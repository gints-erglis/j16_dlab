# Changelog

All notable changes to J16 Data Lab are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com), and the
project uses [Semantic Versioning](https://semver.org) (`vMAJOR.MINOR.PATCH`).

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
