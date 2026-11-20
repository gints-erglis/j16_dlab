# Structure templates

The templates J16 Data Lab's **Structure Viewer** uses to show the structure of a disk
or a file as a tree beside its bytes. They are written for the recovery work the tool
is for: besides the fields, each one says what is wrong with a damaged file, where it
is wrong.

They are in the pattern language of [WerWolv/PatternLanguage](https://github.com/WerWolv/PatternLanguage),
the language of the ImHex hex editor, and run on its library inside J16. They call the
library's built-in functions directly and import nothing, so each file stands alone.
They have been tested in J16 Data Lab, not in ImHex.

## The templates

| File | Format | What it shows | What it marks |
|---|---|---|---|
| [`mp4.hexpat`](mp4.hexpat) | MP4, MOV, 3GP, M4V (ISO base media / QuickTime) | Every box with its size; movie and track headers (duration, creation time, resolution); the codec setup (`avcC` / `hvcC`) with its SPS and PPS; the sample tables, first rows; the first NAL units of the video | A box cut at the end of the file; a missing `moov` index; a chunk table that points outside this file's `mdat` (an index from another recording); data after the last box |
| [`avi.hexpat`](avi.hexpat) | AVI (RIFF), including OpenDML parts | Main header (frames, size, rate, duration); each stream with its codec (`BITMAPINFOHEADER`, `WAVEFORMATEX`); the first `movi` chunks; `idx1` | A chunk cut at the end; an `idx1` whose offsets do not land on the chunks they name |
| [`mpegts.hexpat`](mpegts.hexpat) | MPEG-TS (188-byte packets), M2TS (192, AVCHD and Blu-ray) | The first packets with PID, flags, adaptation field and PCR; PAT; PMT with each stream's type; PES headers with PTS / DTS | A lost sync byte; a transport error or scrambling flag; a partial last packet |
| [`mkv.hexpat`](mkv.hexpat) | Matroska, WebM (MKV, MKA, WEBM) | The EBML element tree with names and values; tracks and codecs; the first clusters with their blocks (track, time, key frame); Cues | A Segment of unknown size (a live or unfinished recording); no Cues (no seek index); a cluster cut at the end |
| [`annexb.hexpat`](annexb.hexpat) | Raw H.264 / H.265 streams (Annex B: start codes) | Each NAL unit in order with its type and size; H.264 SPS profile and level | A NAL unit with the forbidden bit set |
| [`jpeg.hexpat`](jpeg.hexpat) | JPEG (JFIF, Exif, MPF) | Every segment; Exif: camera, serial number, dates, GPS position, thumbnail; the frame (size, baseline / progressive, subsampling); each scan with its restart markers; MPF's other images | No EOI (a cut file); restart markers out of order or missing (data lost or from elsewhere); another JPEG starting inside a scan; what follows EOI (a motion-photo video, other data) |
| [`png.hexpat`](png.hexpat) | PNG, APNG | Every chunk with its CRC checked; size and colour type; text, time, physical size; a long run of IDAT chunks as one row | A wrong CRC (the damaged chunk); a chunk cut at the end; no IEND; data after the image |
| [`bmp.hexpat`](bmp.hexpat) | BMP (BITMAPINFOHEADER, V4, V5, OS/2) | File and bitmap headers; colour masks or palette; the pixel rows | A file size that does not match; a cut file: how many rows are left, and which part of the picture they are |
| [`mbr.hexpat`](mbr.hexpat) | Master Boot Record | The four partition entries: type, start and size in sectors | - |
| [`gpt.hexpat`](gpt.hexpat) | GPT header | The header at LBA 1: disk GUID, usable sectors, where the partition entries are and their checksum | - |

Long tables (sample tables, packets, clusters) show their first rows and keep the rest
as one row, and payload (`mdat`, `movi`, clusters) is never read, so a file of many
gigabytes opens at once. The image templates do read the picture data where it is the
check (a JPEG scan's end and restart markers, a PNG's CRCs), up to a limit they name.
A file cut anywhere still gives a tree: the structure the
file ends inside is shown as bytes and marked CUT, with everything before it parsed.

## Using them

In J16 Data Lab: right-click a disk, a partition or a file and choose **Parse
structure**. The template is picked by the file's signature; another one can be chosen
in the list and parsed again. Selecting a row selects its bytes, and clicking a byte
selects its row.

## Suggestions and fixes

Open an **Issue** with the format, what the template shows and what you expected, and,
if you can share one, a sample file (or its first few kilobytes).

## License

Apache License 2.0, like the rest of J16 Data Lab - see [`../LICENSE`](../LICENSE).
