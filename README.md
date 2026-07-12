# J16 Data Lab

A Windows forensics and data-recovery workbench: image and scan drives, recover
files from damaged/deleted filesystems, inspect disk structures, read S.M.A.R.T.
health, and reassemble fragmented video — extensible through plugins.

## Download

Grab the latest package from this repository (or the **Releases** page):

- **`J16_DataLab-v0.1.1-win64.zip`** — the portable application (Windows x64).
- **`VideoAssembler-plugin-v1.0.0.zip`** — the optional Video Assembler plugin.

## Install & run

1. Launch **`J16_DataLab-v0.1.1-setup.exe`**. Reading physical drives requires running as
   **Administrator**.
2. *(Optional)* Video Assembler plugin: unzip
   `VideoAssembler-plugin-v1.0.0.zip` and copy the `mp4_parser` folder into the
   app's `plugins` folder (next to `J16_DataLab.exe`), then restart. Enable/disable it
   under **View ▸ Plugins**.

The **Structure Viewer** plugin is bundled with the app.

## Features

- Disk imaging (device → image/device) with an opportunistic sector map.
- Quick scan: filesystem detection + file carving; TSK-based filesystem recovery.
- Case workflow (`.j16case`) with findings, hex/structure inspection, submap.
- S.M.A.R.T. health (via smartctl) and disk info.
- Open a raw `.img` as a pseudo-disk; mount/unmount.
- **Video Assembler** plugin: carve, classify, validate and reassemble
  fragmented MP4/MOV and CCTV/DVR footage.

## Bug reports & feedback

Please open an **Issue** with the version (e.g. `v0.1.1`), your Windows version,
steps to reproduce, and what you expected vs. what happened.

## License

J16 Data Lab is licensed under the **Apache License 2.0** — see [`LICENSE`](LICENSE).
Bundled third-party components (Qt, The Sleuth Kit, smartmontools, and others)
keep their own licenses — see [`THIRD-PARTY-LICENSES.txt`](THIRD-PARTY-LICENSES.txt).
