# J16 Data Lab

A Windows forensics and data-recovery workbench: image and scan drives, recover
files from damaged/deleted filesystems, inspect disk structures, read S.M.A.R.T.
health, and reassemble fragmented video - extensible through plugins.

## Download

Grab the latest package from this repository (or the **Releases** page):

- **`J16_DataLab-v0.3.0-setup.exe`** - the installable application (Windows x64).

## Install & run

1. Launch **`J16_DataLab-v0.3.0-setup.exe`**. Reading physical drives requires running as
   **Administrator**.

## Features

- Disk imaging (device > image/device) with an opportunistic sector map.
- Quick scan: filesystem detection + file carving; TSK-based filesystem recovery.
- Full scan: resolves where each file ends, then reassembles bifragmented ZIP and MP4
  files - a ZIP join is proved by the archive's own CRC32, an MP4 join is checked
  against its sample table. Export carries a manifest with MD5s.
- Case workflow (`.j16case`) with findings, hex/structure inspection, submap.
- S.M.A.R.T. health (via smartctl) and disk info.
- Open a raw `.img` as a pseudo-disk; mount/unmount.
- **Video Assembler** plugin (Tools menu): for video the file carver cannot name -
  unindexed or truncated containers, raw H.264 streams, CCTV/DVR frame streams and
  orphan moov/mdat halves. Rebuilds a missing index, wraps an elementary stream,
  reconstructs a frame stream, or repairs against a reference file from the same device.
- **NAND Reconstructor** plugin (Tools menu): rebuilds a logical image from raw NAND
  chip dumps.

## Bug reports & feedback

Please open an **Issue** with the version (e.g. `v0.3.0`), your Windows version,
steps to reproduce, and what you expected vs. what happened.

## License

J16 Data Lab is licensed under the **Apache License 2.0** - see [`LICENSE`](LICENSE).
Bundled third-party components (Qt, The Sleuth Kit, smartmontools, and others)
keep their own licenses - see [`THIRD-PARTY-LICENSES.txt`](THIRD-PARTY-LICENSES.txt).
