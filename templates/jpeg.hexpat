#pragma description JPEG / JFIF / Exif: the segments, the camera, dates and GPS from Exif, the frame, the scans and where each image ends
#pragma endian big
#pragma array_limit 0xFFFFFFFFFFFF
#pragma pattern_limit 0x200000
#pragma loop_limit 0x1000000
#pragma eval_depth 96

// A JPEG is a list of segments, each a marker (FF xx) and most with a length: SOI, the
// APPn blocks (JFIF, Exif, XMP, ICC, MPF), the tables (DQT, DHT), the frame (SOFn: size,
// components, baseline or progressive), and one scan (SOS) or several, each followed by
// its entropy-coded data, which has no length: it runs to the next marker. EOI ends it.
//
// What a recovery asks: does the image end where it should (EOI), or is it cut, or does
// another file start inside it; are the restart markers (RST0..7, in a cycle, when the
// frame has a DRI) in order - a gap or a jump is where data is missing or comes from
// somewhere else; what made it and when (Exif: camera, serial, dates, GPS, a thumbnail
// that may survive a damaged image); and what follows the image (an MPF second image,
// a phone's motion-photo video, or another file).
//
// Finding the end of a scan means reading the scan: a JPEG's check reads its picture
// data, as an Annex B stream's does. It is followed for LIMIT() bytes at most.

fn SHOW() { return 24; };
fn LIMIT() { return 0x8000000; };           // 128 MB of one scan
fn min(auto a, auto b) { if (a < b) return a; return b; };

fn size_text(auto b) {
    if (b < 1024) return builtin::std::format("{} B", b);
    if (b < 1048576) return builtin::std::format("{:.1f} KB", b / 1024.0);
    if (b < 1073741824) return builtin::std::format("{:.1f} MB", b / 1048576.0);
    return builtin::std::format("{:.2f} GB", b / 1073741824.0);
};

fn read16(u64 at) { return builtin::std::mem::read_unsigned(at, 2, 1); };
fn rde(u64 at, u64 n, u8 e) { return builtin::std::mem::read_unsigned(at, n, e); };

// `s` is at `at` (as bytes; no NUL needed after it).
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

fn marker_text(auto m) { return builtin::std::format("{:02X} {:02X}", m >> 8, m & 0xFF); };

fn marker_name(auto m) {
    if (m >= 0xE0 && m <= 0xEF) return builtin::std::format("APP{}", m - 0xE0);
    if (m >= 0xD0 && m <= 0xD7) return builtin::std::format("RST{}", m - 0xD0);
    if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) return builtin::std::format("SOF{}", m - 0xC0);
    match (m) {
        (0xC4): return "DHT";
        (0xCC): return "DAC";
        (0xD8): return "SOI";
        (0xD9): return "EOI";
        (0xDA): return "SOS";
        (0xDB): return "DQT";
        (0xDC): return "DNL";
        (0xDD): return "DRI";
        (0xFE): return "COM";
        (_): return builtin::std::format("FF{:02X}", m);
    }
};

fn sof_kind(auto m) {
    match (m) {
        (0xC0): return "baseline";
        (0xC1): return "extended sequential";
        (0xC2): return "progressive";
        (0xC3): return "lossless";
        (0xC9): return "arithmetic sequential";
        (0xCA): return "arithmetic progressive";
        (0xCB): return "arithmetic lossless";
        (_): return "hierarchical";
    }
};

// What may follow a scan's data: the tables and scans of a progressive image, EOI. Any
// other marker there is not this image's.
fn after_scan_ok(auto m) {
    return m == 0xC4 || m == 0xDA || m == 0xDB || m == 0xDD || m == 0xD9 || m == 0xDC || m == 0xCC || m == 0xFE
        || (m >= 0xE0 && m <= 0xEF);
};

// ── one image's state, set as its segments are read ──────────────────────────

u32  g_w = 0;
u32  g_h = 0;
u8   g_comps = 0;
u8   g_hmax = 1;
u8   g_vmax = 1;
str  g_kind = "";        // baseline, progressive, ...
u32  g_ri = 0;           // restart interval (DRI), in MCUs
u32  g_scans = 0;
bool g_done = false;     // the image's segments are over
bool g_eoi = false;
bool g_afterScan = false;
str  g_why = "";         // why the image stops, when not at EOI
str  g_damage = "";      // the first damage a scan shows
str  g_camera = "";      // from Exif, for the image's row
str  g_taken = "";
bool g_gps = false;
u64  g_after = 0;        // where the last image ended
u32  g_images = 0;

// ── the end of a scan ────────────────────────────────────────────────────────

u64 g_scanEnd = 0;
u64 g_rst = 0;           // restart markers in the scan
u64 g_rstJump = 0;       // the first one out of the cycle, + 1 (0: none)
u8  g_rstGot = 0;
u8  g_rstWant = 0;

// `FF b` in [at, to), or `to`. (A search may look past `to`: what it finds there is not in range.)
fn find2(u64 at, u64 to, u8 b) {
    if (at + 2 > to) return to;
    s128 p = builtin::std::mem::find_sequence_in_range(0, at, to, 0xFF, b);
    if (p == -1 || p + 2 > to) return to;
    return p;
};

// Where a scan's data ends: at the next marker that is not a restart marker. Inside the
// data an FF is always FF 00 (stuffed) or a restart marker, so the markers that can come
// next are searched for, the likeliest first, each in what is left. SOI there is
// another image written over this one.
fn scan_end(u64 begin, u64 lim) {
    u64 e = find2(begin, lim, 0xDA);
    e = find2(begin, e, 0xC4);
    e = find2(begin, e, 0xDB);
    e = find2(begin, e, 0xDD);
    e = find2(begin, e, 0xD8);
    e = find2(begin, e, 0xD9);
    g_scanEnd = e;
};

// The restart markers in [pos, end), which run RST0..RST7 and round again. The next one
// due is searched for; the one before it in the cycle showing up first means the cycle
// broke there (data lost, or from elsewhere), and the count then resumes from the marker
// actually found.
fn rst_walk(u64 pos, u64 end) {
    g_rst = 0; g_rstJump = 0;
    u8 k = 0;
    while (pos < end) {
        u64 q = find2(pos, end, 0xD0 + k);
        u64 prev = find2(pos, q, 0xD0 + ((k + 7) & 7));
        if (prev < q) {
            u64 first = prev;
            u8 code = (k + 7) & 7;
            for (u8 c = 0, c < 8, c = c + 1) {
                u64 x = find2(pos, first, 0xD0 + c);
                if (x < first) { first = x; code = c; }
            }
            if (g_rstJump == 0) { g_rstJump = first + 1; g_rstGot = code; g_rstWant = k; }
            g_rst = g_rst + 1;
            pos = first + 2;
            k = (code + 1) & 7;
            continue;
        }
        if (q >= end) break;
        g_rst = g_rst + 1;
        pos = q + 2;
        k = (k + 1) & 7;
    }
};

// Restart markers a scan of the whole frame has: one between each interval.
fn rst_expected(u64 ns) {
    if (g_ri == 0 || g_kind == "progressive" || ns != g_comps || g_w == 0) return 0;
    u64 mcus = ((g_w + 8 * g_hmax - 1) / (8 * g_hmax)) * ((g_h + 8 * g_vmax - 1) / (8 * g_vmax));
    return (mcus + g_ri - 1) / g_ri - 1;
};

struct ScanData {
    u64 begin = $;
    u64 lim = min(sizeof($), begin + LIMIT());
    scan_end(begin, lim);
    u64 stop = g_scanEnd;
    g_rst = 0; g_rstJump = 0;
    if (g_ri != 0) rst_walk(begin, stop);
    u64 rst = g_rst;
    u64 jump = g_rstJump;
    u8  got = g_rstGot;
    u8  want = g_rstWant;
    u64 expect = rst_expected(parent.ns);
    u8  marker = stop + 1 < sizeof($) ? $[stop + 1] : 0;
    str end = "";
    str why = "";
    if (stop >= sizeof($)) { end = "CUT: no EOI, the file ends inside the scan"; why = "CUT: no EOI"; }
    else if (stop >= lim) { end = builtin::std::format("no end in the first {} of the scan: not followed further", size_text(LIMIT())); why = end; }
    else if (marker == 0xD8) {
        end = builtin::std::format("another JPEG starts inside the scan at 0x{:X}: this image is cut there", stop);
        why = builtin::std::format("CUT at 0x{:X} by another JPEG", stop);
    }
    if (end != "") { g_done = true; g_why = why; }
    if (g_damage == "" && jump != 0) g_damage = builtin::std::format("restart markers OUT OF ORDER at 0x{:X}", jump - 1);
    else if (g_damage == "" && expect != 0 && rst < expect) g_damage = builtin::std::format("SHORT: {} of {} restart markers", rst, expect);
    g_afterScan = true;
    if (stop > begin) u8 data[stop - begin] [[sealed]];
} [[format_read("scan_label")]];

// What is wrong with a scan, most telling first; "" when nothing.
fn scan_damage(u64 jump, u8 got, u8 want, u64 rst, u64 expect) {
    str t = "";
    if (jump != 0)
        t = builtin::std::format("OUT OF ORDER at 0x{:X}: RST{} where RST{} was due (data missing or from elsewhere)", jump - 1, got, want);
    str n = "";
    if (expect != 0 && rst < expect) n = builtin::std::format("SHORT: {} of {} restart markers", rst, expect);
    else if (expect != 0 && rst > expect) n = builtin::std::format("{} restart markers, {} more than the frame has", rst, rst - expect);
    if (t != "" && n != "") return t + "; " + n;
    return t + n;
};

fn scan_label(ref auto s) {
    str t = scan_damage(s.jump, s.got, s.want, s.rst, s.expect);
    if (s.end != "") { if (t != "") t = t + "; "; t = t + s.end; }
    if (t != "") return t;
    t = builtin::std::format("{} of entropy-coded data", size_text(s.stop - s.begin));
    if (s.rst > 0) t = t + builtin::std::format(", {} restart markers", s.rst);
    return t;
};

// ── Exif and MPF: a TIFF block, in its own byte order ─────────────────────────

u8  g_e = 1;             // 1 big (MM), 2 little (II)
u64 g_tiff = 0;          // offsets count from here
u64 g_tiffEnd = 0;       // and must stay before here
u8  g_ifdKind = 0;       // 0 image tags, 3 GPS, 4 MPF

fn type_size(auto t) {
    if (t == 3 || t == 8) return 2;
    if (t == 4 || t == 9 || t == 11) return 4;
    if (t == 5 || t == 10 || t == 12) return 8;
    return 1;
};

// The entry for `tag` in the IFD at `ifd`, 0 when absent.
fn ifd_entry(u64 ifd, u64 tag) {
    if (ifd + 2 > g_tiffEnd) return 0;
    u64 n = rde(ifd, 2, g_e);
    for (u64 i = 0, i < n && i < 512 && ifd + 14 + 12 * i <= g_tiffEnd, i = i + 1) {
        u64 a = ifd + 2 + 12 * i;
        if (rde(a, 2, g_e) == tag) return a;
    }
    return 0;
};
// Its value, read as the number it is (a SHORT sits in the first two bytes).
fn ifd_value(u64 ifd, u64 tag) {
    u64 a = ifd_entry(ifd, tag);
    if (a == 0) return 0;
    if (rde(a + 2, 2, g_e) == 3) return rde(a + 8, 2, g_e);
    return rde(a + 8, 4, g_e);
};
// Its text, "" when absent or outside the block.
fn ifd_text(u64 ifd, u64 tag) {
    u64 a = ifd_entry(ifd, tag);
    if (a == 0) return "";
    u64 n = rde(a + 4, 4, g_e);
    u64 at = a + 8;
    if (n > 4) at = g_tiff + rde(a + 8, 4, g_e);
    if (at + min(n, 64) > g_tiffEnd) return "";
    return cstr(at, min(n, 64));
};
fn ifd_next(u64 ifd) {
    u64 n = rde(ifd, 2, g_e);
    u64 at = ifd + 2 + 12 * n;
    if (at + 4 > g_tiffEnd) return 0;
    return rde(at, 4, g_e);
};
// An IFD at this offset can be read: 0 is "none".
fn ifd_ok(u64 off) { return off >= 8 && g_tiff + off + 2 <= g_tiffEnd; };

fn tag_name(auto tag, auto kind) {
    if (kind == 3) {
        match (tag) {
            (0x0000): return "GPSVersionID";
            (0x0001): return "GPSLatitudeRef";
            (0x0002): return "GPSLatitude";
            (0x0003): return "GPSLongitudeRef";
            (0x0004): return "GPSLongitude";
            (0x0005): return "GPSAltitudeRef";
            (0x0006): return "GPSAltitude";
            (0x0007): return "GPSTimeStamp";
            (0x0012): return "GPSMapDatum";
            (0x001D): return "GPSDateStamp";
            (_): return builtin::std::format("GPS tag 0x{:04X}", tag);
        }
    }
    if (kind == 4) {
        match (tag) {
            (0xB000): return "MPFVersion";
            (0xB001): return "NumberOfImages";
            (0xB002): return "MPEntry";
            (0xB003): return "ImageUIDList";
            (_): return builtin::std::format("MPF tag 0x{:04X}", tag);
        }
    }
    match (tag) {
        (0x0100): return "ImageWidth";
        (0x0101): return "ImageLength";
        (0x0103): return "Compression";
        (0x010E): return "ImageDescription";
        (0x010F): return "Make";
        (0x0110): return "Model";
        (0x0112): return "Orientation";
        (0x011A): return "XResolution";
        (0x011B): return "YResolution";
        (0x0128): return "ResolutionUnit";
        (0x0131): return "Software";
        (0x0132): return "DateTime";
        (0x013B): return "Artist";
        (0x0201): return "JPEGInterchangeFormat";
        (0x0202): return "JPEGInterchangeFormatLength";
        (0x0213): return "YCbCrPositioning";
        (0x8298): return "Copyright";
        (0x8769): return "ExifIFD";
        (0x8825): return "GPSIFD";
        (0x829A): return "ExposureTime";
        (0x829D): return "FNumber";
        (0x8827): return "ISO";
        (0x9000): return "ExifVersion";
        (0x9003): return "DateTimeOriginal";
        (0x9004): return "DateTimeDigitized";
        (0x9010): return "OffsetTime";
        (0x9011): return "OffsetTimeOriginal";
        (0x9012): return "OffsetTimeDigitized";
        (0x920A): return "FocalLength";
        (0x927C): return "MakerNote";
        (0x9286): return "UserComment";
        (0x9290): return "SubSecTime";
        (0x9291): return "SubSecTimeOriginal";
        (0x9292): return "SubSecTimeDigitized";
        (0xA002): return "PixelXDimension";
        (0xA003): return "PixelYDimension";
        (0xA005): return "InteropIFD";
        (0xA420): return "ImageUniqueID";
        (0xA430): return "CameraOwnerName";
        (0xA431): return "BodySerialNumber";
        (0xA433): return "LensMake";
        (0xA434): return "LensModel";
        (0xA435): return "LensSerialNumber";
        (_): return builtin::std::format("tag 0x{:04X}", tag);
    }
};

fn rational(u64 at, u8 e) {
    u64 d = rde(at + 4, 4, e);
    if (d == 0) return 0.0;
    return rde(at, 4, e) * 1.0 / d;
};

struct IfdEntry {
    u64 at = $;
    u8  e = g_e;
    u64 base = g_tiff;
    u64 lim = g_tiffEnd;
    u8  kind = g_ifdKind;
    u16 tag;
    u16 type;
    u32 count;
    u32 value;
    builtin::std::core::set_display_name(this, tag_name(tag, kind));
} [[sealed, format_read("entry_label")]];

fn entry_label(ref auto x) {
    u64 n = type_size(x.type) * x.count;
    u64 where = x.at + 8;
    if (n > 4) where = x.base + x.value;
    if (x.kind == 0 && (x.tag == 0x8769 || x.tag == 0x8825 || x.tag == 0xA005))
        return builtin::std::format("an IFD at +0x{:X}", x.value);
    if (n > 4 && where + n > x.lim)
        return builtin::std::format("{} bytes at +0x{:X}: OUTSIDE the block", n, x.value);
    if (x.kind == 4 && x.tag == 0xB002) return builtin::std::format("{} images, listed below", x.count / 16);
    if (x.type == 2) return cstr(where, min(x.count, 120));
    if (x.kind == 3 && (x.tag == 2 || x.tag == 4) && x.type == 5 && x.count == 3)
        return builtin::std::format("{:.0f}° {:.0f}' {:.2f}\"", rational(where, x.e), rational(where + 8, x.e), rational(where + 16, x.e));
    if (x.count == 1) {
        if (x.type == 3) return builtin::std::format("{}", rde(where, 2, x.e));
        if (x.type == 4) return builtin::std::format("{}", rde(where, 4, x.e));
        if (x.type == 5) return builtin::std::format("{:.4g}", rational(where, x.e));
    }
    if (x.type == 7 && n <= 4) return cstr(where, n);
    return builtin::std::format("{} values of type {}, {} bytes", x.count, x.type, n);
};

struct Ifd {
    u64 at = $;
    u16 count;
    u64 room = 0;
    if (g_tiffEnd > $ + 4) room = (g_tiffEnd - $) / 12;
    IfdEntry entries[min(min(count, room), 128)] [[inline]];
    u64 shown = min(min(count, room), 128);
    if ($ + 4 <= g_tiffEnd) u32 next_ifd;
} [[format_read("ifd_label")]];
fn ifd_label(ref auto i) {
    if (i.shown < i.count) return builtin::std::format("{} entries, {} shown: the rest is past the end of the block", i.count, i.shown);
    return builtin::std::format("{} entries", i.count);
};

u64 g_thumb = 0;

struct Thumbnail {
    u64 begin = $;
    u8 data[g_thumb] [[sealed]];
} [[format_read("thumb_label")]];
fn thumb_label(ref auto t) {
    if ($[t.begin] == 0xFF && $[t.begin + 1] == 0xD8)
        return builtin::std::format("a JPEG of {}: a picture of the image that may outlive it", size_text(sizeof(t.data)));
    return builtin::std::format("{}, NOT a JPEG: the Exif block points at something else", size_text(sizeof(t.data)));
};

u32 g_mp = 0;

struct MpEntry {
    u64 base = g_tiff;
    g_mp = g_mp + 1;
    builtin::std::core::set_display_name(this, builtin::std::format("image {}", g_mp));
    u32 attributes;
    u32 size;
    u32 offset;
    u16 dependent1;
    u16 dependent2;
} [[format_read("mp_label")]];
fn mp_label(ref auto m) {
    if (m.offset == 0) return builtin::std::format("{}: this image", size_text(m.size));
    u64 at = m.base + m.offset;
    if (at + 2 > sizeof($)) return builtin::std::format("{} at 0x{:X}: past the end of the file, CUT", size_text(m.size), at);
    str t = builtin::std::format("{} at 0x{:X}", size_text(m.size), at);
    if ($[at] == 0xFF && $[at + 1] == 0xD8) {
        if (at + m.size > sizeof($)) return t + ", a JPEG, CUT by the end of the file";
        return t + ", a JPEG";
    }
    return t + ": NOT a JPEG there, the image this names is not where it says";
};

// The TIFF header and its IFDs, at offsets from its start. Exif and MPF blocks each
// have one, in their own byte order.
struct Tiff {
    g_tiff = $;
    char byte_order[2];
    if (byte_order == "II") g_e = 2; else g_e = 1;
    builtin::std::core::set_endian(g_e);
    u16 magic;
    u32 ifd0_offset;
    u64 o0 = ifd0_offset;
    if (ifd_ok(o0)) {
        g_ifdKind = parent.kind;
        Ifd ifd0 @ g_tiff + o0;
        if (parent.kind == 0) {
            u64 make = g_tiff + o0;
            str maker = ifd_text(make, 0x010F);
            str model = ifd_text(make, 0x0110);
            if (model != "" && maker != "") g_camera = maker + " " + model;
            else g_camera = maker + model;
            g_taken = ifd_text(make, 0x0132);
            u64 oe = ifd_value(g_tiff + o0, 0x8769);
            if (ifd_ok(oe)) {
                Ifd exif_ifd @ g_tiff + oe;
                str t = ifd_text(g_tiff + oe, 0x9003);
                if (t != "") g_taken = t;
                str serial = ifd_text(g_tiff + oe, 0xA431);
                if (serial != "") g_camera = g_camera + ", serial " + serial;
            }
            u64 og = ifd_value(g_tiff + o0, 0x8825);
            if (ifd_ok(og)) {
                g_ifdKind = 3;
                Ifd gps_ifd @ g_tiff + og;
                g_ifdKind = 0;
                g_gps = ifd_entry(g_tiff + og, 2) != 0;
            }
            u64 o1 = ifd_next(g_tiff + o0);
            if (ifd_ok(o1)) {
                Ifd ifd1 @ g_tiff + o1;
                u64 to = ifd_value(g_tiff + o1, 0x0201);
                g_thumb = ifd_value(g_tiff + o1, 0x0202);
                if (to >= 8 && g_thumb > 0 && g_tiff + to + g_thumb <= g_tiffEnd) Thumbnail thumbnail @ g_tiff + to;
            }
        } else {
            // MPF: an entry of 16 bytes per image; offsets from this header, the first
            // image (this one) at 0.
            u64 me = ifd_entry(g_tiff + o0, 0xB002);
            if (me != 0) {
                u64 mo = rde(me + 8, 4, g_e);
                u64 mn = rde(me + 4, 4, g_e) / 16;
                if (mo >= 8 && g_tiff + mo + 16 * mn <= g_tiffEnd) { g_mp = 0; MpEntry images[min(mn, SHOW())] @ g_tiff + mo; }
            }
        }
    }
    builtin::std::core::set_endian(1);
};

// ── the segments ─────────────────────────────────────────────────────────────

struct Component {
    u8 id;
    u8 sampling [[format("sampling_text")]];
    u8 table;
} [[format_read("component_label")]];
fn component_label(ref auto c) { return builtin::std::format("id {}, {}x{}, quantisation table {}", c.id, c.sampling >> 4, c.sampling & 15, c.table); };
fn sampling_text(auto v) { return builtin::std::format("{}x{}", v >> 4, v & 15); };

struct ScanComponent {
    u8 id;
    u8 tables [[format("tables_text")]];
} [[format_read("scan_component_label")]];
fn scan_component_label(ref auto c) { return builtin::std::format("id {}, Huffman DC {}, AC {}", c.id, c.tables >> 4, c.tables & 15); };
fn tables_text(auto v) { return builtin::std::format("DC {}, AC {}", v >> 4, v & 15); };

// The largest sampling factors of a frame's components: an MCU's size in blocks.
fn max_sampling(u64 at, u64 count, u64 end) {
    g_hmax = 1; g_vmax = 1;
    for (u64 i = 0, i < count && at + 3 * i + 3 <= end, i = i + 1) {
        u8 s = $[at + 3 * i + 1];
        if ((s >> 4) > g_hmax) g_hmax = s >> 4;
        if ((s & 15) > g_vmax) g_vmax = s & 15;
    }
};

fn subsampling(u64 at) {          // from the first component against the others
    u8 y = $[at + 1];
    if (y == 0x22) return "4:2:0";
    if (y == 0x21) return "4:2:2";
    if (y == 0x12) return "4:4:0";
    if (y == 0x11) return "4:4:4";
    if (y == 0x41) return "4:1:1";
    return builtin::std::format("{}x{}", y >> 4, y & 15);
};

fn dqt_text(u64 at, u64 end) {
    str t = "";
    u64 n = 0;
    while (at < end && n < 8) {
        u8 pq = $[at] >> 4;
        t = t + builtin::std::format("{}{} ({}-bit)", n == 0 ? "table " : ", ", $[at] & 15, pq == 0 ? 8 : 16);
        at = at + 1 + 64 * (pq + 1);
        n = n + 1;
    }
    return t;
};

fn dht_text(u64 at, u64 end) {
    str t = "";
    u64 n = 0;
    while (at + 17 <= end && n < 8) {
        u64 codes = 0;
        for (u8 i = 1, i <= 16, i = i + 1) codes = codes + $[at + i];
        t = t + builtin::std::format("{}{} {}", n == 0 ? "" : ", ", ($[at] >> 4) == 0 ? "DC" : "AC", $[at] & 15);
        at = at + 17 + codes;
        n = n + 1;
    }
    return t;
};

fn app_id(u64 at, u64 end) {      // an APPn block's identifier, when it reads as one
    u64 k = 0;
    while (at + k < end && k < 32 && $[at + k] >= 0x20 && $[at + k] < 0x7F) k = k + 1;
    if (k < 3) return "";
    return builtin::std::mem::read_string(at, k);
};

struct Segment {
    u64 start = $;
    u16 marker [[format("marker_text")]];
    u8  code = marker & 0xFF;
    str name = marker_name(code);
    str note = "";
    if (code == 0xD9) { g_done = true; g_eoi = true; note = "end of image"; }
    else if (code == 0xD8) note = "start of image";
    else if (code == 0x01 || (code >= 0xD0 && code <= 0xD7)) {}
    else if ($ + 2 > sizeof($)) {
        g_done = true; g_why = "CUT inside a segment, no EOI";
        note = "CUT: the file ends here";
    } else {
        u16 length;
        u64 end = start + 2 + length;
        if (length < 2) {
            g_done = true; g_why = builtin::std::format("DAMAGED segment at 0x{:X} (length {})", start, length);
            note = "length < 2: DAMAGED, not a segment";
        } else if (end > sizeof($)) {
            // a segment the file ends inside: its fields are not all here, so it stays bytes
            g_done = true; g_why = "CUT inside a segment, no EOI";
            note = builtin::std::format("CUT: {} past the end of the file", size_text(end - sizeof($)));
        } else if (code == 0xDA) {
            u8 ns;
            ScanComponent components[min(ns, ($ < end ? (end - $) / 2 : 0))];
            if ($ + 3 <= end) { u8 spectral_start; u8 spectral_end; u8 approximation; }
            if ($ < end) u8 rest[end - $] [[sealed]];
            g_scans = g_scans + 1;
            note = builtin::std::format("scan {}: {} component(s)", g_scans, ns);
            ScanData scan_data;
            end = $;
        } else if (g_afterScan && !after_scan_ok(code)) {
            // not reached: the scan already stopped the image
        } else if (code >= 0xC0 && code <= 0xCF && code != 0xC4 && code != 0xC8 && code != 0xCC && length >= 8) {
            u8 precision;
            u16 height;
            u16 width;
            u8 count;
            Component components[min(count, (end - $) / 3)];
            g_w = width; g_h = height; g_comps = count; g_kind = sof_kind(code);
            max_sampling(start + 10, count, end);
            note = builtin::std::format("{}, {}x{}, {} component(s), {} bit", g_kind, width, height, count, precision);
            if (count == 3 && start + 13 <= end) note = note + ", " + subsampling(start + 10);
        } else if (code == 0xDD && length == 4) {
            u16 restart_interval;
            g_ri = restart_interval;
            note = builtin::std::format("restart every {} MCUs", restart_interval);
        } else if (code == 0xDB) note = dqt_text($, end);
        else if (code == 0xC4) note = dht_text($, end);
        else if (code == 0xFE) note = cstr($, min(end - $, 120));
        else if (code == 0xE0 && has($, "JFIF") && length >= 16) {
            char identifier[5];
            u8 version_major;
            u8 version_minor;
            u8 units;
            u16 x_density;
            u16 y_density;
            u8 thumb_width;
            u8 thumb_height;
            str unit = "";
            if (units == 1) unit = " dpi"; else if (units == 2) unit = " dots/cm"; else unit = " (aspect)";
            note = builtin::std::format("JFIF {}.{:02}, {}x{}{}", version_major, version_minor, x_density, y_density, unit);
            if (thumb_width > 0) note = note + builtin::std::format(", a {}x{} thumbnail", thumb_width, thumb_height);
        } else if (code == 0xE1 && has($, "Exif") && length >= 16) {
            char identifier[6];
            u8 kind = 0;
            g_tiffEnd = end;
            Tiff tiff;
            note = "Exif";
            if (g_camera != "") note = note + ": " + g_camera;
            if (g_taken != "") note = note + ", " + g_taken;
            if (g_gps) note = note + ", GPS position";
        } else if (code == 0xE1 && has($, "http://ns.adobe.com/xap/1.0/")) {
            note = builtin::std::format("XMP, {}", size_text(end - $ - 29));
        } else if (code == 0xE2 && has($, "MPF") && length >= 16) {
            char identifier[4];
            u8 kind = 4;
            g_tiffEnd = end;
            Tiff tiff;
            note = "MPF: the other images of this one follow its EOI";
        } else if (code == 0xE2 && has($, "ICC_PROFILE") && length >= 16) {
            note = builtin::std::format("ICC profile, part {} of {}", $[$ + 12], $[$ + 13]);
        } else if (code >= 0xE0 && code <= 0xEF) {
            note = app_id($, end);
        }
        if ($ < min(end, sizeof($))) u8 data[min(end, sizeof($)) - $] [[sealed]];
    }
    builtin::std::core::set_display_name(this, name);
} [[format_read("segment_label")]];
fn segment_label(ref auto s) { return s.note; };

// Another segment of this image follows: a marker, and after a scan one that can follow it.
fn segment_next(u64 at) {
    if (g_done) return false;
    if (at + 2 > sizeof($)) { g_why = "CUT: no EOI"; return false; }
    if ($[at] != 0xFF) {
        g_why = builtin::std::format("not a marker at 0x{:X}: damaged, or another file from there", at);
        return false;
    }
    return true;
};

struct Image {
    u64 begin = $;
    g_w = 0; g_h = 0; g_comps = 0; g_kind = ""; g_ri = 0; g_scans = 0;
    g_done = false; g_eoi = false; g_afterScan = false; g_why = ""; g_damage = "";
    g_camera = ""; g_taken = ""; g_gps = false;
    g_images = g_images + 1;
    u32 number = g_images;
    Segment segments[while(segment_next($) && builtin::std::core::array_index() < 4096)] [[inline]];
    g_after = $;
    u32 w = g_w;
    u32 h = g_h;
    str kind = g_kind;
    str camera = g_camera;
    str taken = g_taken;
    bool eoi = g_eoi;
    str why = g_why;
    str damage = g_damage;
    if (number == 1) builtin::std::core::set_display_name(this, "JPEG");
    else builtin::std::core::set_display_name(this, builtin::std::format("JPEG {}", number));
} [[format_read("image_label")]];

// What is wrong first (the row is cut short when long), then what the image is.
fn image_label(ref auto i) {
    str t = "";
    if (!i.eoi) t = i.why == "" ? "no EOI" : i.why;
    if (i.damage != "") t = t + (t == "" ? "" : "; ") + i.damage;
    if (t != "") t = t + "; ";
    if (i.w != 0) t = t + builtin::std::format("{}x{} {}", i.w, i.h, i.kind);
    else t = t + "no frame (SOF)";
    if (i.camera != "") t = t + "; " + i.camera;
    if (i.taken != "") t = t + "; " + i.taken;
    if (i.eoi && i.damage == "") t = t + "; ends at EOI";
    return t;
};

Image images[while($ + 3 <= sizeof($) && $[$] == 0xFF && $[$ + 1] == 0xD8 && builtin::std::core::array_index() < SHOW())] @ 0x00 [[inline]];

// What follows the last image: often the end of a carved run, sometimes part of the file.
struct Tail {
    u64 begin = $;
    u8 data[sizeof($) - $] [[sealed]];
    builtin::std::core::set_display_name(this, "after the image");
} [[format_read("tail_label")]];
fn tail_label(ref auto t) {
    str s = builtin::std::format("{} after the image", size_text(sizeof($) - t.begin));
    if (t.begin + 8 <= sizeof($) && has(t.begin + 4, "ftyp")) return s + ": an MP4 / MOV video (a phone's motion photo)";
    if ($[t.begin] == 0xFF && $[t.begin + 1] == 0xD8) return s + ": more JPEG images";
    u64 zeros = 0;
    while (zeros < 16 && t.begin + zeros < sizeof($) && $[t.begin + zeros] == 0) zeros = zeros + 1;
    if (zeros == 16 || t.begin + zeros == sizeof($)) return s + ": zeros";
    return s + ": not part of the image (another file, or the end of a carved run)";
};
fn tail_at() { if (g_after < sizeof($)) return g_after; return 0; };
Tail after_the_image[g_after < sizeof($) ? 1 : 0] @ tail_at() [[inline]];
