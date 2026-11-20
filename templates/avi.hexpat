#pragma description AVI (RIFF): headers, streams and codecs, the movi chunks and the idx1 index
#pragma endian little
#pragma array_limit 0xFFFFFFFFFFFF
#pragma pattern_limit 0x200000
#pragma loop_limit 0x100000
#pragma eval_depth 96

// An AVI is a RIFF file: chunks of `fourcc, size, data` padded to an even length, and
// LISTs of chunks. hdrl says what the file holds (frame count, size, rate, one strl
// per stream with its codec); movi holds the frames as chunks named for their stream
// (00dc: stream 0 video, 01wb: stream 1 audio); idx1 at the end indexes them. A file
// over 1 GB continues in RIFF AVIX parts, indexed by OpenDML (indx / ix##).
//
// What a recovery asks: is the index there, and does it point at frames - an idx1
// counts its offsets from movi (usually) or from the file start, and an index that
// matches neither belongs to another file. movi shows its first SHOW() chunks; the rest
// is one row.

fn SHOW() { return 24; };
fn min(auto a, auto b) { if (a < b) return a; return b; };

u64 g_movi = 0;          // the first movi LIST's fourcc ("movi"), what idx1 offsets count from
u64 g_moviEnd = 0;

fn size_text(auto b) {
    if (b < 1024) return builtin::std::format("{} B", b);
    if (b < 1048576) return builtin::std::format("{:.1f} KB", b / 1024.0);
    if (b < 1073741824) return builtin::std::format("{:.1f} MB", b / 1048576.0);
    return builtin::std::format("{:.2f} GB", b / 1073741824.0);
};

fn read32(u64 at) { return builtin::std::mem::read_unsigned(at, 4, 0); };
fn fourcc_at(u64 at) {
    return builtin::std::format("{:c}{:c}{:c}{:c}", $[at], $[at + 1], $[at + 2], $[at + 3]);
};

// What a movi chunk's id says: two digits for the stream, two letters for the kind.
fn chunk_kind(str id) {
    str k = builtin::std::string::substr(id, 2, 2);
    match (k) {
        ("dc"): return "compressed video";
        ("db"): return "uncompressed video";
        ("wb"): return "audio";
        ("tx"): return "text";
        ("pc"): return "palette change";
        (_): return "";
    }
};

struct AviMainHeader {
    u32 microseconds_per_frame;
    u32 max_bytes_per_sec;
    u32 padding_granularity;
    u32 flags [[format("avih_flags")]];
    u32 total_frames;
    u32 initial_frames;
    u32 streams;
    u32 suggested_buffer_size;
    u32 width;
    u32 height;
    u32 reserved[4];
} [[format_read("avih_label")]];

fn avih_flags(auto f) {
    str s = builtin::std::format("0x{:X}", f);
    if (f & 0x10) s = s + " has index";
    if (f & 0x20) s = s + ", must use index";
    if (f & 0x100) s = s + ", interleaved";
    return s;
};
fn avih_label(ref auto h) {
    if (h.microseconds_per_frame == 0) return builtin::std::format("{} frames, {}x{}", h.total_frames, h.width, h.height);
    return builtin::std::format("{} frames, {}x{}, {:.3f} fps, {:.1f} s", h.total_frames, h.width, h.height,
                                1000000.0 / h.microseconds_per_frame, h.total_frames * h.microseconds_per_frame / 1000000.0);
};

struct StreamHeader {
    char type[4];            // vids, auds, txts, mids
    char handler[4];         // the codec fourcc (video)
    u32 flags;
    u16 priority;
    u16 language;
    u32 initial_frames;
    u32 scale;
    u32 rate;                // rate / scale = frames (samples) per second
    u32 start;
    u32 length;              // in rate/scale units
    u32 suggested_buffer_size;
    s32 quality;
    u32 sample_size;
    s16 frame_left;
    s16 frame_top;
    s16 frame_right;
    s16 frame_bottom;
} [[format_read("strh_label")]];

fn strh_label(ref auto h) {
    if (h.scale == 0) return builtin::std::format("{} {}", h.type, h.handler);
    return builtin::std::format("{} {}, {:.3f}/s, length {} ({:.1f} s)", h.type, h.handler, h.rate * 1.0 / h.scale,
                                h.length, h.length * 1.0 * h.scale / h.rate);
};

struct BitmapInfoHeader {
    u32 size;
    s32 width;
    s32 height;
    u16 planes;
    u16 bit_count;
    char compression[4];
    u32 image_size;
    s32 x_pels_per_meter;
    s32 y_pels_per_meter;
    u32 colors_used;
    u32 colors_important;
} [[format_read("bih_label")]];
fn bih_label(ref auto b) { return builtin::std::format("{} {}x{}, {} bit", b.compression, b.width, b.height, b.bit_count); };

fn wave_format(auto t) {
    match (t) {
        (0x0001): return "PCM";
        (0x0002): return "MS ADPCM";
        (0x0003): return "IEEE float";
        (0x0006): return "A-law";
        (0x0007): return "u-law";
        (0x0011): return "IMA ADPCM";
        (0x0050): return "MPEG audio";
        (0x0055): return "MP3";
        (0x00FF): return "AAC";
        (0x2000): return "AC-3";
        (0xFFFE): return "extensible";
        (_): return builtin::std::format("0x{:04X}", t);
    }
};

struct WaveFormat {
    u16 format_tag [[format("wave_format")]];
    u16 channels;
    u32 samples_per_sec;
    u32 avg_bytes_per_sec;
    u16 block_align;
    u16 bits_per_sample;
} [[format_read("wave_label")]];
fn wave_label(ref auto w) { return builtin::std::format("{}, {} channel(s), {} Hz, {} bit", wave_format(w.format_tag), w.channels, w.samples_per_sec, w.bits_per_sample); };

struct IndexEntry {
    char chunk_id[4];
    u32 flags [[format("idx_flags")]];
    u32 offset;
    u32 size;
};
fn idx_flags(auto f) { return (f & 0x10) ? "key frame" : builtin::std::format("0x{:X}", f); };

// idx1 offsets count from the movi fourcc (the usual case) or from the file start. The
// first entry says which: its chunk id must be at the place the offset names.
fn idx1_check(u64 first, u64 at_rel_id) {
    if (g_movi == 0) return "no movi to point into";
    if (g_movi + first + 4 <= sizeof($) && read32(g_movi + first) == at_rel_id) return "offsets count from movi, and the first one is that chunk";
    if (first + 4 <= sizeof($) && read32(first) == at_rel_id) return "offsets count from the file start, and the first one is that chunk";
    return "the first entry's chunk is NOT where its offset says: the index does not fit this file";
};

struct Idx1 {
    u64 count = parent.size / 16;
    u64 first = count ? read32($ + 8) : 0;
    u64 first_id = count ? read32($) : 0;
    IndexEntry entries[min(count, SHOW())];
    if ($ < parent.end) u8 more[parent.end - $] [[sealed]];
} [[format_read("idx1_label")]];
fn idx1_label(ref auto i) {
    if (i.count == 0) return "0 entries";
    return builtin::std::format("{} entries; {}", i.count, idx1_check(i.first, i.first_id));
};

using Chunk;

fn chunk_label(ref auto c) {
    str t = builtin::std::format("{}, {}", c.name4, size_text(c.size));
    str k = chunk_kind(c.id);
    if (k != "") t = builtin::std::format("{} ({}), {}", c.id, k, size_text(c.size));
    if (c.end > sizeof($)) t = t + builtin::std::format(" - CUT: {} past the end of the file", size_text(c.end - sizeof($)));
    return t;
};

struct Chunk {
    u64 start = $;
    char id[4];
    u32 size;
    u64 end = start + 8 + size;
    str name4 = id;
    if ((id == "RIFF" || id == "LIST") && $ + 4 <= sizeof($)) {
        char list_type[4];
        name4 = builtin::std::format("{} {}", id, list_type);
        if (list_type == "movi") {
            if (g_movi == 0) { g_movi = start + 8; g_moviEnd = end; }
            Chunk chunks[while($ + 8 <= min(end, sizeof($)) && builtin::std::core::array_index() < SHOW())] [[inline]];
            if ($ < min(end, sizeof($))) u8 more_chunks[min(end, sizeof($)) - $] [[sealed]];
        } else {
            Chunk chunks[while($ + 8 <= min(end, sizeof($)))] [[inline]];
        }
    } else if (end > sizeof($)) {
        // a chunk the file ends inside: its fields are not all here, so it stays bytes
    } else if (id == "avih") AviMainHeader avih;
    else if (id == "strh") StreamHeader strh;
    else if (id == "strf") {
        if (read32(start + 8) == 40 && size >= 40) BitmapInfoHeader video_format;
        else if (size >= 16) WaveFormat audio_format;
    } else if (id == "idx1") Idx1 idx1;
    else if (id == "strn" || id == "ISFT" || id == "INAM" || id == "ICRD" || id == "IART" || id == "ICMT") {
        char text[min(size, sizeof($) - $)];
    }

    u64 stop = min(end, sizeof($));
    if ($ < stop) u8 data[stop - $] [[sealed]];
    // RIFF pads every chunk to an even length.
    if ((size & 1) && $ < sizeof($)) padding[1];
    builtin::std::core::set_display_name(this, name4);
} [[format_read("chunk_label")]];

Chunk riff[while($ + 8 <= sizeof($))] @ 0x00 [[inline]];
