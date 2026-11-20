#pragma description MPEG-TS / M2TS (AVCHD, DVB, many DVRs): packets, PAT, PMT and PES headers
#pragma endian big
#pragma array_limit 0xFFFFFFFFFFFF
#pragma pattern_limit 0x200000
#pragma loop_limit 0x100000
#pragma eval_depth 64

// A transport stream is fixed-size packets: 188 bytes starting with the sync byte 0x47,
// or 192 in M2TS (AVCHD camcorders, Blu-ray) where a 4-byte timestamp comes first. Each
// packet carries a PID; PID 0 is the PAT, which names the PMT, which names each
// stream's PID and codec. A stream's data is PES packets cut into TS packets, and a PES
// header carries the time stamp (PTS) a player orders frames by.
//
// The first SHOW() packets are rows; the rest is one. A file whose size is not a whole
// number of packets was cut, or has bytes of something else appended.

fn SHOW() { return 64; };
fn min(auto a, auto b) { if (a < b) return a; return b; };

// 192-byte packets when the sync byte sits 4 bytes in, every 192 bytes.
bool g_m2ts = $[0] != 0x47 && $[4] == 0x47 && $[196] == 0x47;
u64 g_packet = g_m2ts ? 192 : 188;
u16 g_pmt = 0x1FFF;          // the PMT's PID, once the PAT names it

fn stream_type(auto t) {
    match (t) {
        (0x01): return "MPEG-1 video";
        (0x02): return "MPEG-2 video";
        (0x03): return "MPEG-1 audio";
        (0x04): return "MPEG-2 audio";
        (0x06): return "private data (often AC-3 or subtitles)";
        (0x0F): return "AAC audio (ADTS)";
        (0x11): return "AAC audio (LATM)";
        (0x15): return "metadata";
        (0x1B): return "H.264 video";
        (0x24): return "H.265 video";
        (0x80): return "LPCM audio (Blu-ray)";
        (0x81): return "AC-3 audio";
        (0x86): return "DTS / SCTE-35";
        (0x87): return "E-AC-3 audio";
        (0x90): return "PGS subtitles";
        (_): return builtin::std::format("0x{:02X}", t);
    }
};

fn pid_name(auto pid) {
    if (pid == 0) return "PAT";
    if (pid == 1) return "CAT";
    if (pid == 0x11) return "SDT";
    if (pid == 0x12) return "EIT";
    if (pid == 0x14) return "TDT";
    if (pid == 0x1FFF) return "null";
    if (pid == g_pmt) return "PMT";
    return "";
};

fn hex(auto v) { return builtin::std::format("0x{:X}", v); };
fn pid_text(auto w) {
    u16 pid = w & 0x1FFF;
    str t = builtin::std::format("PID 0x{:04X}", pid);
    if (pid_name(pid) != "") t = t + " (" + pid_name(pid) + ")";
    if (w & 0x4000) t = t + ", unit start";
    if (w & 0x8000) t = t + ", TRANSPORT ERROR";
    return t;
};
fn ctrl_text(auto c) {
    str af;
    match ((c >> 4) & 3) {
        (1): af = "payload";
        (2): af = "adaptation field";
        (3): af = "adaptation field + payload";
        (_): af = "reserved";
    }
    str t = builtin::std::format("{}, continuity {}", af, c & 15);
    if (c & 0xC0) t = t + ", SCRAMBLED";
    return t;
};

fn pcr_text(auto p) { return builtin::std::format("{:.3f} s", p / 90000.0); };
fn pcr_raw_text(auto r) { return builtin::std::format("{:.6f} s (base {}, extension {})", (r >> 15) / 90000.0 + (r & 0x1FF) / 27000000.0, r >> 15, r & 0x1FF); };
fn sc3(auto v) { return "00 00 01"; };

struct AdaptationField {
    u8 length;
    if (length > 0) {
        u8 flags [[format("af_flags")]];
        if ((flags & 0x10) && length >= 7) {
            u48 pcr_raw [[format("pcr_raw_text")]];
            u64 pcr = pcr_raw >> 15;               // 33-bit base, 90 kHz
        }
        u64 rest = addressof(length) + 1 + length;
        if ($ < rest) u8 stuffing[rest - $] [[sealed]];
    }
} [[format_read("af_label")]];
fn af_flags(auto f) {
    str t = builtin::std::format("0x{:02X}", f);
    if (f & 0x80) t = t + " discontinuity";
    if (f & 0x40) t = t + " random-access";
    if (f & 0x10) t = t + " PCR";
    return t;
};
fn af_label(ref auto a) {
    if (a.length > 0 && (a.flags & 0x10) && a.length >= 7) return builtin::std::format("PCR {}", pcr_text(a.pcr));
    return builtin::std::format("{} bytes", a.length);
};

struct PatEntry {
    u16 program_number;
    u16 pid_word [[format("pmt_pid")]];
    if (program_number != 0) g_pmt = pid_word & 0x1FFF;
};
fn pmt_pid(auto w) { return builtin::std::format("PMT at PID 0x{:04X}", w & 0x1FFF); };

struct Pat {
    u8 pointer_field;
    padding[pointer_field];
    u8 table_id;
    u16 section_length_word [[format("sec_len")]];
    u16 transport_stream_id;
    u8 version [[format("version_text")]];
    u8 section_number;
    u8 last_section_number;
    PatEntry programs[((section_length_word & 0x3FF) - 9) / 4];
    u32 crc32 [[format("hex")]];
};
fn sec_len(auto w) { return builtin::std::format("{} bytes", w & 0x3FF); };
fn version_text(auto v) { return builtin::std::format("version {}{}", (v >> 1) & 0x1F, (v & 1) ? ", current" : ", next"); };

struct PmtStream {
    u8 stream_type [[format("stream_type")]];
    u16 pid_word [[format("es_pid")]];
    u16 info_length_word [[format("sec_len")]];
    u8 descriptors[info_length_word & 0x3FF] [[sealed]];
} [[format_read("pmt_stream_label")]];
fn es_pid(auto w) { return builtin::std::format("PID 0x{:04X}", w & 0x1FFF); };
fn pmt_stream_label(ref auto s) { return builtin::std::format("{} at PID 0x{:04X}", stream_type(s.stream_type), s.pid_word & 0x1FFF); };

struct Pmt {
    u8 pointer_field;
    padding[pointer_field];
    u8 table_id;
    u16 section_length_word [[format("sec_len")]];
    u64 end = $ + (section_length_word & 0x3FF) - 4;
    u16 program_number;
    u8 version [[format("version_text")]];
    u8 section_number;
    u8 last_section_number;
    u16 pcr_pid_word [[format("es_pid")]];
    u16 program_info_length_word [[format("sec_len")]];
    u8 program_descriptors[program_info_length_word & 0x3FF] [[sealed]];
    PmtStream streams[while($ + 5 <= end)];
    u32 crc32 [[format("hex")]];
};

fn pts_value(u64 at) {
    return (($[at] >> 1) & 7) << 30 | $[at + 1] << 22 | ($[at + 2] >> 1) << 15 | $[at + 3] << 7 | ($[at + 4] >> 1);
};

struct PesHeader {
    u24 start_code [[format("sc3")]];
    u8 stream_id [[format("pes_stream")]];
    u16 pes_length;
    if (stream_id != 0xBE && stream_id != 0xBF) {
        u8 flags1 [[format("hex")]];
        u8 flags2 [[format("hex")]];
        u8 header_length;
        u64 opt = $;
        if ((flags2 & 0x80) && header_length >= 5) u64 pts = pts_value($);
        if ((flags2 & 0xC0) == 0xC0 && header_length >= 10) u64 dts = pts_value($ + 5);
        u8 optional[header_length] [[sealed]];
    }
} [[format_read("pes_label")]];
fn pes_stream(auto id) {
    if (id >= 0xE0 && id <= 0xEF) return builtin::std::format("0x{:02X} video", id);
    if (id >= 0xC0 && id <= 0xDF) return builtin::std::format("0x{:02X} audio", id);
    if (id == 0xBD) return "0xBD private stream 1";
    return builtin::std::format("0x{:02X}", id);
};
fn pes_label(ref auto p) {
    if (p.stream_id == 0xBE || p.stream_id == 0xBF) return pes_stream(p.stream_id);
    if ((p.flags2 & 0x80) && p.header_length >= 5) return builtin::std::format("{}, PTS {:.3f} s", pes_stream(p.stream_id), p.pts / 90000.0);
    return pes_stream(p.stream_id);
};

struct Packet {
    u64 begin = $;
    if (g_m2ts) u32 arrival_timestamp [[format("hex")]];
    u8 sync_byte [[format("hex")]];
    u16 pid_word [[format("pid_text")]];
    u8 control [[format("ctrl_text")]];
    u16 pid = pid_word & 0x1FFF;
    u64 end = begin + g_packet;
    if ((control & 0x20) && $ < end) AdaptationField adaptation;
    if ((control & 0x10) && $ < end) {
        if (pid == 0 && (pid_word & 0x4000)) Pat pat;
        else if (pid == g_pmt && (pid_word & 0x4000)) Pmt pmt;
        else if ((pid_word & 0x4000) && $[$] == 0 && $[$ + 1] == 0 && $[$ + 2] == 1) PesHeader pes;
        if ($ < end) u8 payload[end - $] [[sealed]];
    }
    if ($ < end) u8 rest[end - $] [[sealed]];
    if (pid_name(pid) != "") builtin::std::core::set_display_name(this, pid_name(pid));
    else builtin::std::core::set_display_name(this, builtin::std::format("PID 0x{:04X}", pid));
} [[format_read("packet_label")]];

fn packet_label(ref auto p) {
    str t = pid_text(p.pid_word);
    if (p.sync_byte != 0x47) t = "LOST SYNC (no 0x47): " + t;
    return t;
};

struct Stream {
    u64 count = sizeof($) / g_packet;
    Packet packets[min(count, SHOW())] [[inline]];
    if ($ < sizeof($)) u8 rest[sizeof($) - $] [[sealed]];
} [[format_read("stream_label")]];

fn stream_label(ref auto s) {
    str t = builtin::std::format("{} packets of {} bytes", s.count, g_packet);
    if (sizeof($) % g_packet) t = t + builtin::std::format(" + {} bytes: the file is cut, or has something else at the end", sizeof($) % g_packet);
    return t;
};

Stream stream @ 0x00;
