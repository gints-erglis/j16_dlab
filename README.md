# J16 Data Lab

A Windows forensics and data-recovery workbench: image and scan drives, recover
files from damaged/deleted filesystems, inspect disk and file structures, read
S.M.A.R.T. health, and reassemble fragmented video - extensible through plugins.

## Download

Take the newest version from the **Releases** page (the same files are in
[`releases/`](releases/)):

- **`J16_DataLab-v<version>-setup.exe`** - the Windows installer (x64).
- **`J16_DataLab-v<version>-win64.zip`** - the portable build: unzip anywhere and run.

What changed in each version, and what to read before upgrading, is in
[`CHANGELOG.md`](CHANGELOG.md).

## Install & run

1. Run the installer, or unzip the portable build.
2. Launch **J16 Data Lab**. Reading physical drives requires **Administrator** rights,
   so it asks for them on start. The Timeline Viewer does not.

The application checks for a newer release on its own (**Help > About**, or turn it off
in **View > Preferences > Updates**). It sends nothing about the computer or its cases.

## Features

- Disk imaging (device > image/device) with an opportunistic sector map.
- Quick scan: filesystem detection + file carving; TSK-based filesystem recovery.
- Full scan: resolves where each file ends, then reassembles bifragmented ZIP, MP4 and
  JPEG files - each join proved by what the format allows (a ZIP's CRC32, an MP4's sample
  table, a JPEG decoded to its end). Export carries a manifest with MD5s.
- Case workflow (`.j16case`) with findings, hex/structure inspection, submap.
- **Structure Viewer**: *Parse structure* on a disk, a partition or a file shows its
  structure as a tree beside the bytes - partition tables, video containers (MP4/MOV,
  AVI, MPEG-TS/M2TS, MKV/WebM, raw H.264/H.265) and images (JPEG, PNG, BMP), with what a
  recovery needs to know: where a file is cut or damaged, an index that does not fit,
  what follows the end. The templates are built into the application; a copy of each is
  published in [`templates/`](templates/) to read or use in ImHex.
- **J16 Timeline Viewer** (`TimelineViewer.exe`): what happened to every file of a FAT32
  card, ordered by causes rather than clocks, each event marked fact or inference;
  recordings that stopped early or are unlike the rest; HTML/CSV report. Built from a
  card's image file or a case's FAT32 finding, or opened from a NAND reconstruction's
  timeline file.
- Apple (APFS) recovery inside a case: FileVault unlock, repair of a filesystem that will
  not mount, and extraction with an account of what did not come out whole.
- S.M.A.R.T. health (via smartctl) and disk info, also for disks in USB enclosures.
- Open a raw `.img` as a pseudo-disk; mount/unmount.

## Plugins

Installed from **View > Plugins > Install...**. Each is licensed per computer: without a
licence file its view shows the computer's code, which gives the licence file on the
licence's downloads page. The check runs on the computer; nothing is sent.

- **Video Assembler** (Tools menu): for video the file carver cannot name - unindexed or
  truncated containers, raw H.264 streams, CCTV/DVR frame streams and orphan moov/mdat
  halves, and recordings cut before the camera wrote any header. Rebuilds a missing
  index, wraps an elementary stream, reconstructs a frame stream, repairs against a
  reference file from the same device (sound included), or joins a header with the media
  it was written for.
- **JPEG Repair** (Tools menu): decodes a damaged photograph block by block, shows which
  part of the picture the file still holds, and puts back what follows the damage.
  Baseline and progressive JPEG.
- **NAND Reconstructor** (Tools menu): rebuilds a logical image from raw NAND chip dumps;
  finds the recipe for a card from its dumps and assembles every video from one version
  of its data.
- **RAID** (Tools menu): binds image files and physical drives into one virtual disk.
  First shape: an Apple Fusion Drive.

A plugin is built for one plugin interface; the changelog says when a release changes it
and which plugin versions go with it.

## Bug reports & feedback

Please open an **Issue** with the version (**Help > About**), your Windows version,
steps to reproduce, and what you expected vs. what happened.

## License

J16 Data Lab is licensed under the **Apache License 2.0** - see [`LICENSE`](LICENSE).
Bundled third-party components (Qt, The Sleuth Kit, smartmontools, and others)
keep their own licenses - see [`THIRD-PARTY-LICENSES.txt`](THIRD-PARTY-LICENSES.txt).
