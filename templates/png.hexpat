#pragma description PNG / APNG: the chunks and each one's CRC, the image header, text, time, and where the image ends
#pragma endian big
#pragma array_limit 0xFFFFFFFFFFFF
#pragma pattern_limit 0x200000
#pragma loop_limit 0x1000000
#pragma eval_depth 96

// A PNG is an 8-byte signature and a list of chunks, each `length, type, data, CRC`:
// IHDR (size, colour type), the ancillary ones (text, time, physical size, colour
// profile, Exif), the picture as IDAT chunks (one zlib stream cut into pieces), IEND.
//
// What a recovery asks: each chunk's CRC covers its type and data, so a wrong CRC says
// exactly which chunk is damaged; a chunk the file ends inside, or no IEND, is a cut
// file; a length or type that makes no sense is where the data stops being this image's.
// Text chunks and tIME say what made the image and when it was last changed.
//
// The CRC check reads the picture data, CHECK() bytes of it at most. A long run of IDAT
// chunks shows its first SHOW() as rows and the rest as one row, still checked.

fn SHOW() { return 24; };
fn CHECK() { return 0x4000000; };        // 64 MB of chunk data whose CRCs are checked
fn ROWS() { return 256; };               // chunk rows before the rest is one row
fn min(auto a, auto b) { if (a < b) return a; return b; };

fn size_text(auto b) {
    if (b < 1024) return builtin::std::format("{} B", b);
    if (b < 1048576) return builtin::std::format("{:.1f} KB", b / 1024.0);
    if (b < 1073741824) return builtin::std::format("{:.1f} MB", b / 1048576.0);
    return builtin::std::format("{:.2f} GB", b / 1073741824.0);
};

fn read32(u64 at) { return builtin::std::mem::read_unsigned(at, 4, 1); };

fn has(u64 at, str s) {
    u64 n = builtin::std::string::length(s);
    if (at + n > sizeof($)) return false;
    for (u64 i = 0, i < n, i = i + 1) if ($[at + i] != builtin::std::string::at(s, i)) return false;
    return true;
};

// A C string of at most n bytes at `at`.
fn cstr(u64 at, u64 n) {
    u64 k = 0;
    while (k < n && at + k < sizeof($) && $[at + k] != 0) k = k + 1;
    if (k == 0) return "";
    return builtin::std::mem::read_string(at, k);
};
// Where the NUL at or after `at` is, or `end`.
fn nul(u64 at, u64 end) {
    while (at < end && $[at] != 0) at = at + 1;
    return at;
};

fn letters(u64 at) {
    for (u8 i = 0, i < 4, i = i + 1) {
        u8 c = $[at + i];
        if (!((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A))) return false;
    }
    return true;
};

// ── the CRCs ─────────────────────────────────────────────────────────────────

u64 g_checked = 0;       // chunk bytes whose CRC has been checked
u64 g_bad = 0;           // chunks with a wrong CRC
u64 g_firstBad = 0;      // the first one, + 1
u64 g_unchecked = 0;     // chunks past CHECK()

// 0 the CRC is right, 1 wrong, 2 not checked. Counts it.
fn crc_check(u64 start, u64 length) {
    if (g_checked + length > CHECK()) { g_unchecked = g_unchecked + 1; return 2; }
    g_checked = g_checked + length + 4;
    u32 want = read32(start + 8 + length);
    u32 got = builtin::std::hash::crc32(builtin::std::mem::read_string(start + 4, length + 4),
                                        0xFFFFFFFF, 0x04C11DB7, 0xFFFFFFFF, true, true);
    if (got == want) return 0;
    g_bad = g_bad + 1;
    if (g_firstBad == 0) g_firstBad = start + 1;
    return 1;
};

// ── the image ────────────────────────────────────────────────────────────────

u32  g_w = 0;
u32  g_h = 0;
str  g_kind = "";
bool g_done = false;
bool g_iend = false;
str  g_why = "";
u64  g_chunks = 0;
u64  g_idat = 0;         // IDAT chunks so far
u64  g_idatBytes = 0;
str  g_software = "";
str  g_time = "";
u64  g_frames = 0;       // APNG

fn color_type(auto t) {
    match (t) {
        (0): return "greyscale";
        (2): return "RGB";
        (3): return "indexed";
        (4): return "greyscale + alpha";
        (6): return "RGBA";
        (_): return builtin::std::format("colour type {} (INVALID)", t);
    }
};

// A run of chunks walked as one row: its end, how many, the first bad CRC in it.
u64 g_runEnd = 0;
u64 g_runCount = 0;
u64 g_runBad = 0;
u64 g_runUnchecked = 0;

// The chunks from `at` that are whole and of type IDAT (only_idat), or any type, up to
// IEND. Stops before a chunk the file ends inside or that is not a chunk.
fn walk(u64 at, bool only_idat) {
    g_runCount = 0; g_runBad = 0; g_runUnchecked = 0;
    while (at + 12 <= sizeof($) && letters(at + 4) && read32(at) <= 0x7FFFFFFF) {
        u64 len = read32(at);
        if (at + 12 + len > sizeof($)) break;
        bool idat = has(at + 4, "IDAT");
        if (only_idat && !idat) break;
        u8 c = crc_check(at, len);
        if (c == 1 && g_runBad == 0) g_runBad = at + 1;
        if (c == 2) g_runUnchecked = g_runUnchecked + 1;
        if (idat) { g_idat = g_idat + 1; g_idatBytes = g_idatBytes + len; }
        g_runCount = g_runCount + 1;
        g_chunks = g_chunks + 1;
        at = at + 12 + len;
        if (has(at - len - 8, "IEND")) { g_done = true; g_iend = true; break; }
    }
    g_runEnd = at;
};

struct Chunk {
    u64 start = $;
    u32 length;
    char type[4];
    u64 end = start + 12 + length;
    str name = type;
    str note = "";
    u8  crc = 2;
    u64 bad = 0;
    if (end > sizeof($)) {
        // a chunk the file ends inside: its fields are not all here, so it stays bytes
        g_done = true; g_why = "CUT: no IEND";
        note = builtin::std::format("CUT: {} past the end of the file", size_text(end - sizeof($)));
        u8 data[sizeof($) - $] [[sealed]];
    } else if ((type == "IDAT" && g_idat >= SHOW()) || g_chunks >= ROWS()) {
        // the rest of a run of IDAT chunks (or of a very long file), one row
        walk(start, type == "IDAT" && g_chunks < ROWS());
        name = builtin::std::format("{} chunks", g_runCount);
        if (type == "IDAT" && g_chunks < ROWS()) name = builtin::std::format("IDAT x{}", g_runCount);
        note = builtin::std::format("{} more chunks, {}", g_runCount, size_text(g_runEnd - start));
        bad = g_runBad;
        if (g_runBad != 0) { crc = 1; note = builtin::std::format("CRC MISMATCH in the chunk at 0x{:X}: DAMAGED; {}", g_runBad - 1, note); }
        else if (g_runUnchecked != 0) note = note + builtin::std::format(", {} not checked", g_runUnchecked);
        else crc = 0;
        u8 more_chunks[g_runEnd - $] [[sealed]];
    } else {
        g_chunks = g_chunks + 1;
        if (type == "IHDR" && length >= 13) {
            u32 width;
            u32 height;
            u8  bit_depth;
            u8  colour_type [[format("color_type")]];
            u8  compression;
            u8  filter;
            u8  interlace;
            g_w = width; g_h = height;
            g_kind = builtin::std::format("{}-bit {}", bit_depth, color_type(colour_type));
            if (interlace == 1) g_kind = g_kind + ", interlaced";
            note = builtin::std::format("{}x{}, {}", width, height, g_kind);
        } else if (type == "tIME" && length == 7) {
            u16 year;
            u8  month;
            u8  day;
            u8  hour;
            u8  minute;
            u8  second;
            g_time = builtin::std::format("{:04}-{:02}-{:02} {:02}:{:02}:{:02}", year, month, day, hour, minute, second);
            note = g_time + " UTC, when the image was last changed";
        } else if (type == "tEXt" && length > 0) {
            u64 k = nul($, end - 4);
            str key = cstr($, min(k - $, 79));
            str text = "";
            if (k < end - 4) text = cstr(k + 1, min(end - 4 - k - 1, 120));
            note = key + ": " + text;
            if (key == "Software") g_software = text;
        } else if (type == "iTXt" && length > 0) {
            u64 k = nul($, end - 4);
            str key = cstr($, min(k - $, 79));
            note = key;
            if (k + 3 <= end - 4) {
                if ($[k + 1] != 0) note = key + " (compressed text)";
                else {
                    u64 lang = nul(k + 3, end - 4);
                    u64 trans = nul(lang + 1, end - 4);
                    if (trans < end - 4) {
                        if (key == "XML:com.adobe.xmp") note = builtin::std::format("XMP, {}", size_text(end - 4 - trans - 1));
                        else note = key + ": " + cstr(trans + 1, min(end - 4 - trans - 1, 120));
                    }
                }
            }
        } else if (type == "zTXt" && length > 0) {
            note = cstr($, min(length, 79)) + " (compressed text)";
        } else if (type == "pHYs" && length == 9) {
            u32 x_per_unit;
            u32 y_per_unit;
            u8  unit;
            if (unit == 1) note = builtin::std::format("{:.0f}x{:.0f} dpi", x_per_unit * 0.0254, y_per_unit * 0.0254);
            else note = builtin::std::format("aspect {}:{}", x_per_unit, y_per_unit);
        } else if (type == "PLTE") {
            note = builtin::std::format("{} colours", length / 3);
        } else if (type == "iCCP" && length > 0) {
            note = "ICC profile " + cstr($, min(length, 79));
        } else if (type == "eXIf") {
            note = builtin::std::format("Exif, {}", size_text(length));
        } else if (type == "acTL" && length == 8) {
            u32 frames;
            u32 plays;
            g_frames = frames;
            note = builtin::std::format("animated (APNG): {} frames", frames);
        } else if (type == "IDAT") {
            note = size_text(length);
        } else if (type == "IEND") {
            g_done = true; g_iend = true;
            note = "end of image";
        }
        if (type == "IDAT") { g_idat = g_idat + 1; g_idatBytes = g_idatBytes + length; }
        if ($ < end - 4) u8 data[end - 4 - $] [[sealed]];
        u32 crc32;
        crc = crc_check(start, length);
        if (crc == 1) {
            bad = start + 1;
            if (note != "") note = "; " + note;
            note = builtin::std::format("CRC MISMATCH: stored {:08X}: the chunk is DAMAGED", crc32) + note;
        }
    }
    builtin::std::core::set_display_name(this, name);
} [[format_read("chunk_label")]];
fn chunk_label(ref auto c) { return c.note; };

// Another chunk follows: one whose length and type make sense.
fn chunk_next(u64 at) {
    if (g_done) return false;
    if (at + 8 > sizeof($)) { g_why = "CUT: no IEND"; return false; }
    if (!letters(at + 4) || read32(at) > 0x7FFFFFFF) {
        g_why = builtin::std::format("not a chunk at 0x{:X}: damaged, or another file from there", at);
        return false;
    }
    return true;
};

u64 g_after = 0;

struct Png {
    u8 signature[8] [[format("sig_text")]];
    Chunk chunks[while(chunk_next($) && builtin::std::core::array_index() < ROWS() + 1)] [[inline]];
    g_after = $;
    u32 w = g_w;
    u32 h = g_h;
    str kind = g_kind;
    bool iend = g_iend;
    str why = g_why;
    u64 count = g_chunks;
    u64 bad = g_bad;
    u64 first_bad = g_firstBad;
    u64 unchecked = g_unchecked;
    u64 idat = g_idat;
    u64 idat_bytes = g_idatBytes;
    str software = g_software;
    str time = g_time;
    builtin::std::core::set_display_name(this, "PNG");
} [[format_read("png_label")]];
fn sig_text(auto s) { return "89 PNG CR LF SUB LF"; };

// What is wrong first (the row is cut short when long), then what the image is.
fn png_label(ref auto p) {
    str t = "";
    if (!p.iend) t = p.why == "" ? "no IEND" : p.why;
    if (p.bad != 0) t = t + (t == "" ? "" : "; ")
                      + builtin::std::format("{} CRC MISMATCH(ES), the first at 0x{:X}", p.bad, p.first_bad - 1);
    if (t != "") t = t + "; ";
    if (p.w != 0) t = t + builtin::std::format("{}x{} {}", p.w, p.h, p.kind);
    else t = t + "no IHDR";
    t = t + builtin::std::format("; {} chunks, {} IDAT ({})", p.count, p.idat, size_text(p.idat_bytes));
    if (p.software != "") t = t + "; " + p.software;
    if (p.time != "") t = t + "; " + p.time;
    if (p.iend && p.bad == 0) {
        if (p.unchecked != 0) t = t + builtin::std::format("; ends at IEND, {} CRCs not checked", p.unchecked);
        else t = t + "; ends at IEND, all CRCs right";
    }
    return t;
};

Png png[sizeof($) >= 8 ? 1 : 0] @ 0x00 [[inline]];

// What follows IEND: often the end of a carved run, sometimes data hidden after the image.
struct Tail {
    u64 begin = $;
    u8 data[sizeof($) - $] [[sealed]];
    builtin::std::core::set_display_name(this, "after the image");
} [[format_read("tail_label")]];
fn tail_label(ref auto t) {
    str s = builtin::std::format("{} after the image", size_text(sizeof($) - t.begin));
    u64 zeros = 0;
    while (zeros < 16 && t.begin + zeros < sizeof($) && $[t.begin + zeros] == 0) zeros = zeros + 1;
    if (zeros == 16 || t.begin + zeros == sizeof($)) return s + ": zeros";
    return s + ": not part of the image (another file, data hidden after it, or the end of a carved run)";
};
fn tail_at() { if (g_after < sizeof($)) return g_after; return 0; };
Tail after_the_image[g_after < sizeof($) ? 1 : 0] @ tail_at() [[inline]];
