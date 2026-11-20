#pragma description BMP / DIB: the file header, the bitmap header, the palette and the pixel rows, and whether all the rows are there
#pragma endian little
#pragma array_limit 0xFFFFFFFFFFFF
#pragma pattern_limit 0x200000
#pragma loop_limit 0x100000
#pragma eval_depth 64

// A BMP is a 14-byte file header ("BM", the file's size, where the pixels start), a
// bitmap header (BITMAPINFOHEADER, 40 bytes, or its longer V4 / V5 forms, or the old
// 12-byte OS/2 one), colour masks or a palette, and the pixel rows: each padded to 4
// bytes, the bottom row first unless the height is negative.
//
// What a recovery asks: the format has no end marker and no checksum, so the sizes are
// the check - the file header's size against the file, and the rows the bitmap header
// promises against the bytes there. A cut BMP keeps its BOTTOM rows (when bottom-up),
// and this says how many. The pixels are never read.

fn min(auto a, auto b) { if (a < b) return a; return b; };

fn size_text(auto b) {
    if (b < 1024) return builtin::std::format("{} B", b);
    if (b < 1048576) return builtin::std::format("{:.1f} KB", b / 1024.0);
    if (b < 1073741824) return builtin::std::format("{:.1f} MB", b / 1048576.0);
    return builtin::std::format("{:.2f} GB", b / 1073741824.0);
};

fn compression_text(auto c) {
    match (c) {
        (0): return "uncompressed";
        (1): return "RLE8";
        (2): return "RLE4";
        (3): return "bit fields";
        (4): return "JPEG inside";
        (5): return "PNG inside";
        (6): return "alpha bit fields";
        (11): return "CMYK";
        (12): return "CMYK RLE8";
        (13): return "CMYK RLE4";
        (_): return builtin::std::format("compression {} (unknown)", c);
    }
};

fn header_name(auto n) {
    match (n) {
        (12): return "BITMAPCOREHEADER (OS/2 1)";
        (40): return "BITMAPINFOHEADER";
        (52): return "BITMAPV2INFOHEADER";
        (56): return "BITMAPV3INFOHEADER";
        (64): return "OS/2 2 header";
        (108): return "BITMAPV4HEADER";
        (124): return "BITMAPV5HEADER";
        (_): return builtin::std::format("a header of {} bytes (UNKNOWN)", n);
    }
};

// ── what the headers say, for the rows after them ─────────────────────────────

u64  g_fileSize = 0;
u64  g_pixels = 0;       // where the pixel rows start
s64  g_w = 0;
s64  g_h = 0;
u64  g_bpp = 0;
u64  g_compression = 0;
u64  g_imageSize = 0;
u64  g_colours = 0;
bool g_core = false;     // the OS/2 header: 3-byte palette entries
u64  g_profile = 0;      // a V5 header's embedded profile, from the file start
u64  g_profileSize = 0;
str  g_why = "";
u64  g_end = 14;         // where the described data ends

fn abs(auto v) { if (v < 0) return -v; return v; };
fn stride() { return ((abs(g_w) * g_bpp + 31) / 32) * 4; };
fn uncompressed() { return g_compression == 0 || g_compression == 3 || g_compression == 6; };
// The pixel bytes the headers promise.
fn expected() {
    if (uncompressed()) return stride() * abs(g_h);
    return g_imageSize;
};

struct FileHeader {
    char magic[2];
    u32 file_size;
    u16 reserved1;
    u16 reserved2;
    u32 pixel_offset;
    g_fileSize = file_size;
    g_pixels = pixel_offset;
} [[format_read("file_label")]];
fn file_label(ref auto f) {
    if (f.file_size == sizeof($)) return builtin::std::format("{}, as the file is; pixels at 0x{:X}", size_text(f.file_size), f.pixel_offset);
    if (f.file_size > sizeof($))
        return builtin::std::format("CUT: says {}, the file has {} ({} missing); pixels at 0x{:X}", size_text(f.file_size),
                                    size_text(sizeof($)), size_text(f.file_size - sizeof($)), f.pixel_offset);
    return builtin::std::format("says {}, the file has {} more after it; pixels at 0x{:X}", size_text(f.file_size),
                                size_text(sizeof($) - f.file_size), f.pixel_offset);
};

struct CoreHeader {
    u32 header_size [[format("header_name")]];
    u16 width;
    u16 height;
    u16 planes;
    u16 bit_count;
    g_w = width; g_h = height; g_bpp = bit_count; g_core = true;
} [[format_read("dib_label")]];

struct InfoHeader {
    u64 begin = $;
    u32 header_size [[format("header_name")]];
    s32 width;
    s32 height;
    u16 planes;
    u16 bit_count;
    u32 compression [[format("compression_text")]];
    u32 image_size;
    s32 x_pixels_per_metre;
    s32 y_pixels_per_metre;
    u32 colours_used;
    u32 colours_important;
    if (header_size >= 52) { u32 red_mask; u32 green_mask; u32 blue_mask; }
    if (header_size >= 56) u32 alpha_mask;
    if (header_size >= 108) {
        char colour_space[4];
        u8 endpoints[36];
        u32 gamma_red;
        u32 gamma_green;
        u32 gamma_blue;
    }
    if (header_size >= 124) {
        u32 intent;
        u32 profile_offset;
        u32 profile_size;
        u32 reserved;
        if (profile_size > 0) { g_profile = begin + profile_offset; g_profileSize = profile_size; }
    }
    if ($ < begin + header_size) u8 rest[begin + header_size - $] [[sealed]];
    g_w = width; g_h = height; g_bpp = bit_count; g_compression = compression;
    g_imageSize = image_size; g_colours = colours_used;
} [[format_read("dib_label")]];

fn dib_label(ref auto d) {
    str t = builtin::std::format("{}x{}, {} bit, {}", abs(g_w), abs(g_h), g_bpp, compression_text(g_compression));
    if (g_w <= 0 || g_h == 0 || g_bpp == 0 || g_bpp > 32) return t + ": INVALID size or depth, the header is damaged";
    if (g_h < 0) return t + ", top row first";
    return t + ", bottom row first";
};

struct Masks {
    u32 red_mask;
    u32 green_mask;
    u32 blue_mask;
    if (g_compression == 6) u32 alpha_mask;
};

u64 g_palette = 0;        // palette bytes

struct Palette {
    u8 entries[g_palette] [[sealed]];
} [[format_read("palette_label")]];
fn palette_label(ref auto p) { return builtin::std::format("{} colours", sizeof(p.entries) / (g_core ? 3 : 4)); };

struct Pixels {
    u64 begin = $;
    u64 want = expected();
    u64 have = min(want, sizeof($) - begin);
    u8 rows[have] [[sealed]];
} [[format_read("pixels_label")]];

fn pixels_label(ref auto p) {
    if (!uncompressed()) {
        if (p.have < p.want) return builtin::std::format("CUT: {} of {} of {} data", size_text(p.have), size_text(p.want), compression_text(g_compression));
        return builtin::std::format("{} of {} data", size_text(p.want), compression_text(g_compression));
    }
    u64 s = stride();
    u64 rows = abs(g_h);
    if (p.have >= p.want) return builtin::std::format("{} rows of {}, all here", rows, size_text(s));
    u64 got = p.have / s;
    str part = "the top";
    if (g_h > 0) part = "the bottom";
    return builtin::std::format("CUT: {} of {} rows here ({} of the picture), {} missing", got, rows, part,
                                size_text(p.want - p.have));
};

struct Bmp {
    FileHeader file_header;
    if (14 + 4 > sizeof($)) {
        g_why = "CUT inside the headers";
    } else {
        u64 dib = builtin::std::mem::read_unsigned(14, 4, 2);
        if (14 + dib > sizeof($)) {
            // a header the file ends inside: its fields are not all here, so it stays bytes
            g_why = "CUT inside the bitmap header";
            u8 bitmap_header[sizeof($) - 14] [[sealed]];
        } else if (dib == 12) CoreHeader bitmap_header;
        else if (dib >= 40) InfoHeader bitmap_header;
        else {
            g_why = builtin::std::format("a bitmap header of {} bytes: DAMAGED", dib);
            u8 bitmap_header[dib] [[sealed]];
        }
        if (g_why == "") {
            u64 room = g_pixels > $ ? g_pixels - $ : 0;
            if (dib == 40 && (g_compression == 3 || g_compression == 6)) {
                u64 n = g_compression == 6 ? 16 : 12;
                if ($ + n > sizeof($)) g_why = "CUT inside the colour masks";
                else Masks masks;
            }
            if (g_bpp <= 8 && g_bpp > 0) {
                u64 n = g_colours;
                if (n == 0 || n > 256) n = 1 << g_bpp;
                g_palette = n * (g_core ? 3 : 4);
                if (g_pixels > $ && g_palette > g_pixels - $) g_palette = g_pixels - $;
                if ($ + g_palette > sizeof($)) { g_palette = sizeof($) - $; g_why = "CUT inside the palette"; }
                Palette palette;
            }
            if ($ < g_pixels && g_pixels <= sizeof($)) u8 gap[g_pixels - $] [[sealed]];
            if (g_pixels >= sizeof($)) {
                if (g_why == "") g_why = builtin::std::format("CUT: the pixels would start at 0x{:X}, past the end", g_pixels);
            } else if (g_why == "" && g_pixels >= $) {
                Pixels pixels;
                u64 want = expected();
                g_end = g_pixels + min(want, sizeof($) - g_pixels);
                if (g_end < g_pixels + want) g_why = "CUT: rows missing";
            }
        }
    }
    if (g_end < $) g_end = $;
    builtin::std::core::set_display_name(this, "BMP");
} [[format_read("bmp_label")]];

fn bmp_label(ref auto b) {
    str t = g_why;
    if (t != "") t = t + "; ";
    t = t + builtin::std::format("{}x{}, {} bit, {}", abs(g_w), abs(g_h), g_bpp, compression_text(g_compression));
    if (g_why == "") t = t + "; all the rows are here";
    return t;
};

Bmp bmp[sizeof($) >= 14 ? 1 : 0] @ 0x00 [[inline]];

// What follows the pixel rows: a V5 header's colour profile, or not part of the image.
struct Tail {
    u64 begin = $;
    u8 data[sizeof($) - $] [[sealed]];
    builtin::std::core::set_display_name(this, "after the pixels");
} [[format_read("tail_label")]];
fn tail_label(ref auto t) {
    str s = builtin::std::format("{} after the pixels", size_text(sizeof($) - t.begin));
    if (g_profile != 0 && g_profile >= t.begin && g_profile < sizeof($)) return s + ": holds the colour profile the header names";
    if (g_fileSize > t.begin && g_fileSize <= sizeof($)) return s + builtin::std::format(", {} of it inside the size the header gives", size_text(g_fileSize - t.begin));
    return s + ": not part of the image (another file, or the end of a carved run)";
};
fn tail_at() { if (g_end < sizeof($)) return g_end; return 0; };
Tail after_the_pixels[g_end < sizeof($) && sizeof($) >= 14 ? 1 : 0] @ tail_at() [[inline]];
