#pragma description H.264 / H.265 elementary stream (Annex B): NAL units after start codes
#pragma endian big
#pragma array_limit 0xFFFFFFFFFFFF
#pragma pattern_limit 0x200000
#pragma loop_limit 0x100000
#pragma eval_depth 64

// A raw video stream: each NAL unit follows a start code (00 00 01, or 00 00 00 01),
// with no container around them. DVRs and dashcams write streams like this, carving
// finds them, and a recovery that rebuilds an MP4 starts from one. What a stream needs
// to decode is its parameter sets first (H.264: SPS, PPS; H.265: VPS, SPS, PPS), then a
// key frame - the rows say whether they are there and in that order.
//
// The first SHOW() units are rows; the rest of the stream is one. A unit's length is
// the distance to the next start code, searched up to SEARCH() bytes ahead.

fn SHOW() { return 64; };
fn SEARCH() { return 0x2000000; };    // 32 MB: no frame is larger
fn min(auto a, auto b) { if (a < b) return a; return b; };

// H.265 if the first unit's header reads as an H.265 parameter set or AUD (its type
// sits in bits 1-6 and the second header byte is 01); H.264 otherwise.
fn first_header_at() {
    if ($[0] == 0 && $[1] == 0 && $[2] == 1) return 3;
    return 4;
};
u64 g_h0 = first_header_at();
bool g_hevc = ($[g_h0] & 0x81) == 0 && (($[g_h0] >> 1) & 0x3F) >= 32 && (($[g_h0] >> 1) & 0x3F) <= 35 && $[g_h0 + 1] == 1;

fn h264_nal(auto t) {
    match (t) {
        (1): return "slice";
        (2): return "slice part A";
        (5): return "IDR slice (key frame)";
        (6): return "SEI";
        (7): return "SPS";
        (8): return "PPS";
        (9): return "access unit delimiter";
        (10): return "end of sequence";
        (11): return "end of stream";
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
        (36): return "end of sequence";
        (37): return "end of bitstream";
        (38): return "filler";
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

fn size_text(auto b) {
    if (b < 1024) return builtin::std::format("{} B", b);
    if (b < 1048576) return builtin::std::format("{:.1f} KB", b / 1024.0);
    return builtin::std::format("{:.1f} MB", b / 1048576.0);
};

// The next start code at or after `from`, or the end of the data.
fn next_start(u64 pos) {
    u64 to = min(pos + SEARCH(), sizeof($));
    if (pos + 3 > to) return sizeof($);
    s128 at = builtin::std::mem::find_sequence_in_range(0, pos, to, 0x00, 0x00, 0x01);
    if (at == -1) return to;
    if (at > pos && $[at - 1] == 0) return at - 1;      // a 4-byte start code
    return at;
};

fn nal_type_text(auto h) {
    if (g_hevc) return builtin::std::format("H.265 type {} ({})", (h >> 1) & 0x3F, h265_nal((h >> 1) & 0x3F));
    return builtin::std::format("H.264 type {} ({})", h & 0x1F, h264_nal(h & 0x1F));
};

struct Sps264 {
    u8 profile_idc [[format("avc_profile")]];
    u8 constraint_flags [[format("hex8")]];
    u8 level_idc [[format("avc_level")]];
};
fn hex8(auto v) { return builtin::std::format("0x{:02X}", v); };
fn avc_level(auto l) { return builtin::std::format("{}.{}", l / 10, l % 10); };

fn sc4(auto v) { return "00 00 00 01"; };
fn sc3(auto v) { return "00 00 01"; };

struct NalUnit {
    u64 begin = $;
    if ($[$] == 0 && $[$ + 1] == 0 && $[$ + 2] == 0) u32 start_code [[format("sc4")]];
    else u24 start_code [[format("sc3")]];
    u8 header [[format("nal_type_text")]];
    if (g_hevc) u8 header2;
    u64 end = next_start($);
    if (!g_hevc && (header & 0x1F) == 7 && end - $ >= 3) Sps264 sps;
    if ($ < end) u8 data[end - $] [[sealed]];
    if (g_hevc) builtin::std::core::set_display_name(this, h265_nal((header >> 1) & 0x3F));
    else builtin::std::core::set_display_name(this, h264_nal(header & 0x1F));
} [[format_read("unit_label")]];

fn unit_label(ref auto n) {
    str t = builtin::std::format("{}, {}", nal_type_text(n.header), size_text(n.end - n.begin));
    if (n.header & 0x80) t = t + " - forbidden bit set: not a NAL unit (corrupt, or not a stream)";
    return t;
};

// A unit's start code and header: a stream cut inside them has no unit there.
fn unit_head(u64 at) {
    u64 sc = 3;
    if ($[at] == 0 && $[at + 1] == 0 && $[at + 2] == 0) sc = 4;
    if (g_hevc) return sc + 2;
    return sc + 1;
};

struct Stream {
    NalUnit units[while($ + 4 <= sizeof($) && $ + unit_head($) <= sizeof($) && builtin::std::core::array_index() < SHOW())] [[inline]];
    if ($ < sizeof($)) u8 rest[sizeof($) - $] [[sealed]];
} [[format_read("stream_label")]];

fn stream_label(ref auto s) {
    return builtin::std::format("{} stream; the first {} NAL units", g_hevc ? "H.265" : "H.264", builtin::std::core::member_count(s.units));
};

// Leading bytes before the first start code (a carved stream rarely starts on one).
fn first_start() { return next_start(0); };
Stream stream @ first_start();
