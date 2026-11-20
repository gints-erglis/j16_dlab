#pragma description MP4 / MOV / 3GP: the box tree, track headers, codec setup and sample tables
#pragma endian big
#pragma array_limit 0xFFFFFFFFFFFF
#pragma pattern_limit 0x200000
#pragma loop_limit 0x100000
#pragma eval_depth 96

// ISO base media (MP4, 3GP, M4V) and QuickTime (MOV) are one format: a file is a list of
// boxes (QuickTime: atoms), each `size, type, payload`, and some boxes hold more boxes.
// What a recovery needs to see is all here: whether the index (moov) is whole, which
// codec and what its parameter sets are (avcC / hvcC), and whether the sample tables
// point into this file's mdat at all - an index taken from another recording does not.
//
// A sample table has one entry per sample, so a table shows its first SHOW() entries as
// rows and keeps the rest as one block of bytes. The mdat payload is never read, except
// its first few NAL units, which say whether the data starts where a decoder expects.

fn SHOW() { return 24; };
fn min(auto a, auto b) { if (a < b) return a; return b; };

// ── what the whole file says, read before the tree ────────────────────────────

u64 g_mdatStart = 0;    // the first mdat's payload
u64 g_mdatEnd = 0;
u8  g_codec = 0;        // 1 H.264, 2 H.265, 0 unknown
u8  g_nalLen = 4;       // NAL length field size, from avcC / hvcC
u64 g_firstVideo = 0;   // the video track's first chunk, from its stco / co64
bool g_moov = false;

fn read32(u64 at) { return builtin::std::mem::read_unsigned(at, 4, 1); };
fn read64(u64 at) { return builtin::std::mem::read_unsigned(at, 8, 1); };
fn is_type(u64 at, str t) {
    return $[at] == builtin::std::string::at(t, 0) && $[at + 1] == builtin::std::string::at(t, 1)
        && $[at + 2] == builtin::std::string::at(t, 2) && $[at + 3] == builtin::std::string::at(t, 3);
};

// A fourcc of letters, digits, spaces and the like; a QuickTime ilst item's "type" is a
// key index instead.
fn printable(u64 at) {
    for (u8 i = 0, i < 4, i = i + 1) if ($[at + i] < 0x20 || $[at + i] > 0x7E) return false;
    return true;
};

u64 g_tail = 0;          // where the top-level boxes stop: past it is not a box

fn prescan() {
    u64 at = 0;
    u64 n = 0;
    while (at + 8 <= sizeof($) && n < 4096) {
        if (!printable(at + 4)) break;
        u64 size = read32(at);
        u64 head = 8;
        if (size == 1) { size = read64(at + 8); head = 16; }
        else if (size == 0) size = sizeof($) - at;
        if (size < head) break;
        if (is_type(at + 4, "mdat") && g_mdatEnd == 0) { g_mdatStart = at + head; g_mdatEnd = at + size; }
        if (is_type(at + 4, "moov")) {
            g_moov = true;
            u64 end = at + size;
            if (end > sizeof($)) end = sizeof($);
            s128 cfg = builtin::std::mem::find_sequence_in_range(0, at, end, 0x68, 0x76, 0x63, 0x43);        // hvcC
            if (cfg != -1) g_codec = 2;
            else {
                cfg = builtin::std::mem::find_sequence_in_range(0, at, end, 0x61, 0x76, 0x63, 0x43);         // avcC
                if (cfg != -1) g_codec = 1;
            }
            // The chunk table that follows the codec setup is the video track's own.
            if (cfg != -1) {
                s128 co = builtin::std::mem::find_sequence_in_range(0, cfg, end, 0x73, 0x74, 0x63, 0x6F);     // stco
                s128 c64 = builtin::std::mem::find_sequence_in_range(0, cfg, end, 0x63, 0x6F, 0x36, 0x34);    // co64
                if (c64 != -1 && (co == -1 || c64 < co)) { if (read32(c64 + 8) > 0) g_firstVideo = read64(c64 + 12); }
                else if (co != -1) { if (read32(co + 8) > 0) g_firstVideo = read32(co + 12); }
            }
        }
        at = at + size;
        n = n + 1;
    }
    g_tail = at;
};
prescan();

// ── formatting ─────────────────────────────────────────────────────────────────

// Seconds since 1904-01-01, the clock of every QuickTime / ISO header.
fn mac_time(auto s) {
    if (s == 0) return "0 (not set)";
    s128 z = s / 86400 - 24107 + 719468;     // days since 1904, to the civil algorithm's epoch
    u64 t = s % 86400;
    s128 era = z / 146097;
    s128 doe = z - era * 146097;
    s128 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    s128 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    s128 mp = (5 * doy + 2) / 153;
    s128 d = doy - (153 * mp + 2) / 5 + 1;
    s128 m = mp < 10 ? mp + 3 : mp - 9;
    s128 y = yoe + era * 400 + (m <= 2 ? 1 : 0);
    return builtin::std::format("{:04}-{:02}-{:02} {:02}:{:02}:{:02}", y, m, d, t / 3600, t / 60 % 60, t % 60);
};

fn fixed16(auto v) { return builtin::std::format("{:.4f}", v / 65536.0); };
fn fixed8(auto v) { return builtin::std::format("{:.2f}", v / 256.0); };
fn hex32(auto v) { return builtin::std::format("0x{:08X}", v); };
fn hex8(auto v) { return builtin::std::format("0x{:02X}", v); };

fn lang(auto v) {
    if (v == 0 || v == 0x7FFF) return "und";
    return builtin::std::format("{:c}{:c}{:c}", ((v >> 10) & 31) + 0x60, ((v >> 5) & 31) + 0x60, (v & 31) + 0x60);
};

fn size_text(auto b) {
    if (b < 1024) return builtin::std::format("{} B", b);
    if (b < 1048576) return builtin::std::format("{:.1f} KB", b / 1024.0);
    if (b < 1073741824) return builtin::std::format("{:.1f} MB", b / 1048576.0);
    return builtin::std::format("{:.2f} GB", b / 1073741824.0);
};

fn h264_nal(auto t) {
    match (t) {
        (1): return "slice";
        (5): return "IDR slice (key frame)";
        (6): return "SEI";
        (7): return "SPS";
        (8): return "PPS";
        (9): return "access unit delimiter";
        (12): return "filler";
        (_): return "other";
    }
};

fn h265_nal(auto t) {
    if (t <= 9) return "slice";
    if (t >= 16 && t <= 21) return "IRAP slice (key frame)";
    match (t) {
        (32): return "VPS";
        (33): return "SPS";
        (34): return "PPS";
        (35): return "access unit delimiter";
        (39): return "SEI prefix";
        (40): return "SEI suffix";
        (_): return "other";
    }
};

fn avc_profile(auto p) {
    match (p) {
        (66): return "Baseline";
        (77): return "Main";
        (88): return "Extended";
        (100): return "High";
        (110): return "High 10";
        (122): return "High 4:2:2";
        (244): return "High 4:4:4";
        (_): return "other";
    }
};

// ── boxes ────────────────────────────────────────────────────────────────────

using Box;

fn box_label(ref auto b) {
    str t = builtin::std::format("{}, {}", b.type, size_text(b.boxSize));
    if (!printable(b.start + 4)) t = builtin::std::format("metadata item {}, {}", read32(b.start + 4), size_text(b.boxSize));
    if (b.boxEnd > sizeof($)) t = t + builtin::std::format(" - CUT: {} past the end of the file", size_text(b.boxEnd - sizeof($)));
    if (b.type == "mdat" && !g_moov) t = t + " - no moov in this file: the index is missing (a recording never closed, or a fragment)";
    return t;
};

fn is_container(str t) {
    return t == "moov" || t == "trak" || t == "mdia" || t == "minf" || t == "stbl" || t == "dinf"
        || t == "edts" || t == "udta" || t == "moof" || t == "traf" || t == "mvex" || t == "mfra"
        || t == "tref" || t == "sinf" || t == "schi" || t == "gmhd" || t == "ilst" || t == "tapt"
        || t == "clip" || t == "matt" || t == "rmra" || t == "imap";
};

struct FullHeader {
    u8 version;
    u24 flags [[format("hex32")]];
};

struct Ftyp {
    char major_brand[4];
    u32 minor_version [[format("hex32")]];
    char compatible_brands[parent.boxEnd - $];
};

struct Mvhd {
    FullHeader header;
    if (header.version == 1) {
        u64 creation_time [[format("mac_time")]];
        u64 modification_time [[format("mac_time")]];
        u32 timescale;
        u64 duration;
    } else {
        u32 creation_time [[format("mac_time")]];
        u32 modification_time [[format("mac_time")]];
        u32 timescale;
        u32 duration;
    }
    u32 rate [[format("fixed16")]];
    u16 volume [[format("fixed8")]];
    padding[10];
    s32 matrix[9];
    padding[24];
    u32 next_track_id;
} [[format_read("mvhd_label")]];

fn mvhd_label(ref auto m) {
    if (m.timescale == 0) return "timescale 0: the duration cannot be read";
    return builtin::std::format("{:.2f} s, timescale {}", m.duration * 1.0 / m.timescale, m.timescale);
};

struct Tkhd {
    FullHeader header;
    if (header.version == 1) {
        u64 creation_time [[format("mac_time")]];
        u64 modification_time [[format("mac_time")]];
        u32 track_id;
        padding[4];
        u64 duration;
    } else {
        u32 creation_time [[format("mac_time")]];
        u32 modification_time [[format("mac_time")]];
        u32 track_id;
        padding[4];
        u32 duration;
    }
    padding[8];
    s16 layer;
    s16 alternate_group;
    u16 volume [[format("fixed8")]];
    padding[2];
    s32 matrix[9];
    u32 width [[format("fixed16")]];
    u32 height [[format("fixed16")]];
} [[format_read("tkhd_label")]];

fn tkhd_label(ref auto t) {
    if (t.width == 0) return builtin::std::format("track {}", t.track_id);
    return builtin::std::format("track {}, {}x{}", t.track_id, t.width >> 16, t.height >> 16);
};

struct Mdhd {
    FullHeader header;
    if (header.version == 1) {
        u64 creation_time [[format("mac_time")]];
        u64 modification_time [[format("mac_time")]];
        u32 timescale;
        u64 duration;
    } else {
        u32 creation_time [[format("mac_time")]];
        u32 modification_time [[format("mac_time")]];
        u32 timescale;
        u32 duration;
    }
    u16 language [[format("lang")]];
    u16 quality;
} [[format_read("mvhd_label")]];

struct Hdlr {
    FullHeader header;
    char component_type[4];        // QuickTime: mhlr / dhlr; ISO: 0
    char handler_type[4];          // vide, soun, meta, tmcd, hint, text
    padding[12];
    char name[parent.boxEnd - $];
} [[format_read("hdlr_label")]];

fn hdlr_label(ref auto h) {
    match (h.handler_type) {
        ("vide"): return "video";
        ("soun"): return "sound";
        ("meta"): return "timed metadata";
        ("tmcd"): return "timecode";
        ("text"): return "text";
        ("sbtl"): return "subtitles";
        (_): return h.handler_type;
    }
};

struct ElstEntry64 { u64 segment_duration; s64 media_time; u32 media_rate [[format("fixed16")]]; };
struct ElstEntry32 { u32 segment_duration; s32 media_time; u32 media_rate [[format("fixed16")]]; };
struct SttsEntry { u32 sample_count; u32 sample_delta; };
struct CttsEntry { u32 sample_count; s32 sample_offset; };
struct StscEntry { u32 first_chunk; u32 samples_per_chunk; u32 sample_description_index; };

struct Elst {
    FullHeader header;
    u32 entry_count;
    if (header.version == 1) ElstEntry64 entries[min(entry_count, SHOW())];
    else ElstEntry32 entries[min(entry_count, SHOW())];
};

// One parameter set inside avcC: a length and a NAL unit.
struct ParamSet {
    u16 length;
    u8 nal_header [[format("avc_header")]];
    u8 data[length - 1] [[sealed]];
};
fn avc_header(auto h) { return builtin::std::format("type {} ({})", h & 0x1F, h264_nal(h & 0x1F)); };

struct AvcC {
    u8 configuration_version;
    u8 profile [[format("avc_profile")]];
    u8 profile_compatibility [[format("hex8")]];
    u8 level [[format("avc_level")]];
    u8 nal_length_size [[format("len_size")]];
    g_nalLen = (nal_length_size & 3) + 1;
    u8 sps_count_byte [[format("sps_count")]];
    ParamSet sps[sps_count_byte & 0x1F];
    u8 pps_count;
    ParamSet pps[pps_count];
    if ($ < parent.boxEnd) u8 extension[parent.boxEnd - $] [[sealed]];
} [[format_read("avcc_label")]];

fn sps_count(auto b) { return builtin::std::format("{} (0x{:02X})", b & 0x1F, b); };
fn avc_level(auto l) { return builtin::std::format("{}.{}", l / 10, l % 10); };
fn len_size(auto b) { return builtin::std::format("{} bytes per NAL length", (b & 3) + 1); };
fn avcc_label(ref auto a) {
    return builtin::std::format("H.264 {} level {}.{}, {} SPS, {} PPS", avc_profile(a.profile), a.level / 10, a.level % 10,
                                a.sps_count_byte & 0x1F, a.pps_count);
};

struct HevcNal {
    u16 length;
    u8 data[length] [[sealed]];
};

struct HevcArray {
    u8 type_byte [[format("hevc_array_type")]];
    u16 nal_count;
    HevcNal nals[nal_count];
};
fn hevc_array_type(auto b) { return builtin::std::format("type {} ({})", b & 0x3F, h265_nal(b & 0x3F)); };

struct HvcC {
    u8 configuration_version;
    u8 profile_byte;
    u32 profile_compatibility [[format("hex32")]];
    u48 constraint_flags;
    u8 level;
    u16 min_spatial_segmentation;
    u8 parallelism_type;
    u8 chroma_format;
    u8 luma_bit_depth;
    u8 chroma_bit_depth;
    u16 avg_frame_rate;
    u8 length_byte [[format("len_size")]];
    g_nalLen = (length_byte & 3) + 1;
    u8 array_count;
    HevcArray arrays[array_count];
} [[format_read("hvcc_label")]];

fn hvcc_label(ref auto h) {
    return builtin::std::format("H.265 profile {} level {:.1f}, {} parameter set arrays", h.profile_byte & 0x1F, h.level / 30.0, h.array_count);
};

fn is_visual(str f) {
    return f == "avc1" || f == "avc3" || f == "hvc1" || f == "hev1" || f == "mp4v" || f == "jpeg" || f == "mjpa"
        || f == "mjpb" || f == "apcn" || f == "apch" || f == "apcs" || f == "apco" || f == "ap4h" || f == "dvh1"
        || f == "dvhe" || f == "av01" || f == "vp09" || f == "s263" || f == "h263" || f == "CFHD";
};
fn is_audio(str f) {
    return f == "mp4a" || f == "sowt" || f == "twos" || f == "lpcm" || f == "in24" || f == "in32" || f == "fl32"
        || f == "ulaw" || f == "alaw" || f == "ac-3" || f == "ec-3" || f == "Opus" || f == "samr" || f == "raw ";
};

struct SampleEntry {
    u64 start = $;
    u32 size;
    char format[4];
    u64 end = start + size;
    padding[6];
    u16 data_reference_index;
    if (is_visual(format)) {
        u16 version;
        u16 revision;
        char vendor[4];
        u32 temporal_quality;
        u32 spatial_quality;
        u16 width;
        u16 height;
        u32 horizontal_resolution [[format("fixed16")]];
        u32 vertical_resolution [[format("fixed16")]];
        u32 data_size;
        u16 frame_count;
        u8 compressor_name_length;
        char compressor_name[31];
        u16 depth;
        s16 color_table_id;
        Box extensions[while($ + 8 <= end)] [[inline]];
    } else if (is_audio(format)) {
        u16 version;
        u16 revision;
        char vendor[4];
        u16 channels;
        u16 sample_size;
        s16 compression_id;
        u16 packet_size;
        u32 sample_rate [[format("fixed16")]];
        if (version == 1) { u32 samples_per_packet; u32 bytes_per_packet; u32 bytes_per_frame; u32 bytes_per_sample; }
        if (version == 2) { u32 struct_size; u64 sample_rate64; u32 channels32; u32 always_7F000000; u32 bits_per_channel; u32 format_flags; u32 bytes_per_packet; u32 frames_per_packet; }
        Box extensions[while($ + 8 <= end)] [[inline]];
    }
    if ($ < end) u8 rest[end - $] [[sealed]];
    builtin::std::core::set_display_name(this, format);
} [[format_read("entry_label")]];

fn entry_label(ref auto e) {
    if (is_visual(e.format)) return builtin::std::format("video {}x{}", e.width, e.height);
    if (is_audio(e.format)) return builtin::std::format("audio, {} channel(s), {} Hz", e.channels, e.sample_rate >> 16);
    return builtin::std::format("{} bytes", e.size);
};

struct Stsd {
    FullHeader header;
    u32 entry_count;
    SampleEntry entries[entry_count] [[inline]];
};

// A table: count, its first SHOW() rows, and the rest as bytes.
struct Stts {
    FullHeader header;
    u32 entry_count;
    SttsEntry entries[min(entry_count, SHOW())];
    if ($ < parent.boxEnd) u8 more[parent.boxEnd - $] [[sealed]];
} [[format_read("count_label")]];

struct Ctts {
    FullHeader header;
    u32 entry_count;
    CttsEntry entries[min(entry_count, SHOW())];
    if ($ < parent.boxEnd) u8 more[parent.boxEnd - $] [[sealed]];
} [[format_read("count_label")]];

struct Stss {
    FullHeader header;
    u32 entry_count;
    u32 sample_numbers[min(entry_count, SHOW())];
    if ($ < parent.boxEnd) u8 more[parent.boxEnd - $] [[sealed]];
} [[format_read("stss_label")]];

fn count_label(ref auto t) { return builtin::std::format("{} entries", t.entry_count); };
fn stss_label(ref auto t) { return builtin::std::format("{} key frames", t.entry_count); };

struct Stsc {
    FullHeader header;
    u32 entry_count;
    StscEntry entries[min(entry_count, SHOW())];
    if ($ < parent.boxEnd) u8 more[parent.boxEnd - $] [[sealed]];
} [[format_read("count_label")]];

struct Stsz {
    FullHeader header;
    u32 sample_size;
    u32 sample_count;
    if (sample_size == 0) {
        u32 sizes[min(sample_count, SHOW())];
        if ($ < parent.boxEnd) u8 more[parent.boxEnd - $] [[sealed]];
    }
} [[format_read("stsz_label")]];

fn stsz_label(ref auto t) {
    if (t.sample_size != 0) return builtin::std::format("{} samples of {} bytes", t.sample_count, t.sample_size);
    return builtin::std::format("{} samples", t.sample_count);
};

// Chunk offsets are where the samples are. Pointing outside this file's mdat means the
// index belongs to another recording, or the file was cut.
fn chunk_check(auto first, auto last) {
    if (g_mdatEnd == 0) return "no mdat in this file to point into";
    if (first < g_mdatStart || first >= g_mdatEnd) return builtin::std::format("first chunk 0x{:X} is OUTSIDE mdat (0x{:X}-0x{:X}): the index does not fit this file", first, g_mdatStart, g_mdatEnd);
    if (last >= sizeof($)) return builtin::std::format("last chunk 0x{:X} is past the end of the file: the file is cut", last);
    if (last >= g_mdatEnd) return builtin::std::format("last chunk 0x{:X} is past mdat's end (0x{:X})", last, g_mdatEnd);
    return "first and last chunk inside mdat";
};

struct Stco {
    FullHeader header;
    u32 entry_count;
    u64 first = entry_count ? read32($) : 0;
    u64 last = entry_count ? read32($ + (entry_count - 1) * 4) : 0;
    u32 chunk_offsets[min(entry_count, SHOW())];
    if ($ < parent.boxEnd) u8 more[parent.boxEnd - $] [[sealed]];
} [[format_read("stco_label")]];

fn stco_label(ref auto t) {
    if (t.entry_count == 0) return "0 chunks";
    return builtin::std::format("{} chunks; {}", t.entry_count, chunk_check(t.first, t.last));
};

struct Co64 {
    FullHeader header;
    u32 entry_count;
    u64 first = entry_count ? read64($) : 0;
    u64 last = entry_count ? read64($ + (entry_count - 1) * 8) : 0;
    u64 chunk_offsets[min(entry_count, SHOW())];
    if ($ < parent.boxEnd) u8 more[parent.boxEnd - $] [[sealed]];
} [[format_read("co64_label")]];

fn co64_label(ref auto t) {
    if (t.entry_count == 0) return "0 chunks";
    return builtin::std::format("{} chunks; {}", t.entry_count, chunk_check(t.first, t.last));
};

// The first NAL units of mdat, as length-prefixed units (the way MP4 stores H.264/H.265).
// A sane run of them says the payload starts with video; garbage lengths say it does not
// (audio first, another file's bytes, or a stream with start codes instead of lengths).
struct NalUnit {
    if (g_nalLen == 4) u32 length;
    else if (g_nalLen == 2) u16 length;
    else if (g_nalLen == 1) u8 length;
    else u24 length;
    u8 header [[format("nal_type")]];
    u8 data[length - 1] [[sealed]];
} [[format_read("nal_label")]];

fn nal_type(auto h) {
    if (g_codec == 2) return builtin::std::format("H.265 type {} ({})", (h >> 1) & 0x3F, h265_nal((h >> 1) & 0x3F));
    return builtin::std::format("H.264 type {} ({})", h & 0x1F, h264_nal(h & 0x1F));
};
fn nal_label(ref auto n) { return builtin::std::format("{}, {} bytes", nal_type(n.header), n.length); };

fn nal_ok(u64 at, u64 end) {
    if (at + g_nalLen + 1 > end) return false;
    u64 len = builtin::std::mem::read_unsigned(at, g_nalLen, 1);
    if (len < 2 || at + g_nalLen + len > end) return false;
    return ($[at + g_nalLen] & 0x80) == 0;       // forbidden_zero_bit
};

fn annexb_at(u64 at) { return $[at] == 0 && $[at + 1] == 0 && ($[at + 2] == 1 || ($[at + 2] == 0 && $[at + 3] == 1)); };

// The first video sample, where the index says it is (or, with no index, where mdat
// starts): its NAL units should be parameter sets, SEI and a key frame.
struct FirstVideo {
    // no mdat and no index to say where the video is: nothing here is a NAL unit
    u64 limit = g_mdatEnd ? min(g_mdatEnd, sizeof($)) : (g_firstVideo != 0 ? sizeof($) : 0);
    NalUnit units[while(nal_ok($, limit) && builtin::std::core::array_index() < 8)] [[inline]];
} [[format_read("first_label")]];

fn first_label(ref auto f) {
    u64 n = builtin::std::core::member_count(f.units);
    if (n == 0 && g_mdatEnd == 0 && g_firstVideo == 0) return "no mdat in this file: no video data to read";
    if (n == 0) return "no length-prefixed NAL units here (no index to find the video, or not H.264/H.265)";
    return builtin::std::format("the first {} NAL units of the video", n);
};

struct Box {
    u64 start = $;
    u32 size;
    char type[4];
    if (size == 1) u64 large_size;
    u64 boxSize = size == 1 ? large_size : (size == 0 ? sizeof($) - start : size);
    u64 boxEnd = start + boxSize;
    if (type == "uuid") u8 user_type[16];

    if (boxSize < 8) {
        // a size no box can have: the tree stops here (a cut or overwritten file)
    } else if (is_container(type)) {
        Box children[while($ + 8 <= min(boxEnd, sizeof($)))] [[inline]];
    } else if (type == "meta") {
        if (read32($) == 0) FullHeader header;             // ISO: a full box; QuickTime: not
        Box children[while($ + 8 <= min(boxEnd, sizeof($)))] [[inline]];
    } else if (boxEnd > sizeof($)) {
        // a box the file ends inside: its fields are not all here, so it stays bytes
    } else if (type == "ftyp") Ftyp ftyp [[inline]];
    else if (type == "mvhd") Mvhd mvhd;
    else if (type == "tkhd") Tkhd tkhd;
    else if (type == "mdhd") Mdhd mdhd;
    else if (type == "hdlr") Hdlr hdlr;
    else if (type == "elst") Elst elst [[inline]];
    else if (type == "stsd") Stsd stsd [[inline]];
    else if (type == "avcC") AvcC avcC;
    else if (type == "hvcC") HvcC hvcC;
    else if (type == "stts") Stts stts;
    else if (type == "ctts") Ctts ctts;
    else if (type == "stss") Stss stss;
    else if (type == "stsc") Stsc stsc;
    else if (type == "stsz") Stsz stsz;
    else if (type == "stco") Stco stco;
    else if (type == "co64") Co64 co64;
    else if (type == "dref") { FullHeader header; u32 entry_count; Box entries[while($ + 8 <= min(boxEnd, sizeof($)))] [[inline]]; }

    u64 stop = min(boxEnd, sizeof($));
    if (boxSize >= 8 && $ < stop) u8 data[stop - $] [[sealed]];
    if (printable(start + 4)) builtin::std::core::set_display_name(this, type);
    else builtin::std::core::set_display_name(this, builtin::std::format("item 0x{:X}", read32(start + 4)));
} [[format_read("box_label")]];

Box boxes[while($ + 8 <= sizeof($) && printable($ + 4))] @ 0x00 [[inline]];

// What follows the last box when it is not one: another file's data (a carve that ran
// on), or the rest of an area the camera reserved. Nothing past the boxes is the file's.
struct Tail {
    u8 data[sizeof($) - $] [[sealed]];
    builtin::std::core::set_display_name(this, "after the last box");
} [[format_read("tail_label")]];
fn tail_label(ref auto t) { return builtin::std::format("{} after the last box: not part of this file's structure", size_text(sizeof($) - g_tail)); };
fn tail_at() { if (g_tail < sizeof($)) return g_tail; return 0; };   // a placement must be in bounds, even of nothing
Tail after_last_box[g_tail < sizeof($) ? 1 : 0] @ tail_at() [[inline]];

// Placed unconditionally (a placement inside an `if` makes no pattern); with nothing to
// show it is an empty row.
fn first_video_at() {
    if (g_firstVideo != 0 && g_firstVideo < sizeof($)) return g_firstVideo;
    return g_mdatStart;
};
FirstVideo first_video_units @ first_video_at();
