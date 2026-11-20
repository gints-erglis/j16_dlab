#pragma description Matroska / WebM (MKV, MKA, WEBM): the EBML element tree, tracks and codecs, clusters and blocks
#pragma endian big
#pragma array_limit 0xFFFFFFFFFFFF
#pragma pattern_limit 0x200000
#pragma loop_limit 0x100000
#pragma eval_depth 96

// Matroska is EBML: every element is an ID, a size and data, the ID and size written as
// variable-length integers (the leading zero bits of the first byte give the length).
// Some elements hold elements. A file is an EBML header, then one Segment: Info
// (duration, the app that wrote it), Tracks (codec of each track), Clusters (the frames,
// as blocks with a time relative to the cluster) and Cues (the index a player seeks by).
//
// A recording cut short has Clusters but no Cues, and often a Segment size of "unknown"
// (all ones), which live writers use while they do not know the end yet. The first
// CLUSTERS() clusters show their first BLOCKS() blocks; later clusters are one row.

fn CLUSTERS() { return 4; };
fn BLOCKS() { return 8; };
fn min(auto a, auto b) { if (a < b) return a; return b; };

u64 g_clusters = 0;
bool g_cues = false;

// Bytes in the variable-length integer whose first byte is `b` (1..8; 0 if invalid).
fn vlen(u8 b) {
    if (b & 0x80) return 1;
    if (b & 0x40) return 2;
    if (b & 0x20) return 3;
    if (b & 0x10) return 4;
    if (b & 0x08) return 5;
    if (b & 0x04) return 6;
    if (b & 0x02) return 7;
    if (b & 0x01) return 8;
    return 0;
};

fn read_be(u64 at, u64 n) { if (n == 0) return 0; return builtin::std::mem::read_unsigned(at, n, 1); };

// An element's size field value, or -1 for "unknown" (all value bits set).
fn size_value(u64 at) {
    u64 n = vlen($[at]);
    u64 raw = read_be(at, n);
    u64 mask = (1 << (7 * n)) - 1;
    if ((raw & mask) == mask) return -1;
    return raw & mask;
};

// Where the element at `at` ends (`limit` for an unknown size).
fn element_end(u64 at, u64 limit) {
    u64 il = vlen($[at]);
    if (il == 0 || il > 4) return limit;
    u64 sl = vlen($[at + il]);
    if (sl == 0) return limit;
    s128 sz = size_value(at + il);
    if (sz < 0) return limit;
    return at + il + sl + sz;
};

fn element_id(u64 at) { return read_be(at, vlen($[at])); };

// The clusters that follow one another from `at`: how many (what 0), or where they end (1).
fn cluster_run(u64 at, u8 what) {
    u64 n = 0;
    while (at + 8 <= sizeof($) && element_id(at) == 0x1F43B675 && n < 1000000) {
        u64 next = element_end(at, sizeof($));
        if (next <= at) break;
        at = next;
        n = n + 1;
    }
    if (what == 0) return n;
    return at;
};

// kind: 1 master, 2 unsigned, 3 signed, 4 ASCII string, 5 UTF-8, 6 float, 7 date, 0 binary
fn kind_of(u32 id) {
    match (id) {
        (0x1A45DFA3 | 0x18538067 | 0x114D9B74 | 0x4DBB | 0x1549A966 | 0x1F43B675 | 0xA0 | 0x1654AE6B | 0xAE
         | 0xE0 | 0xE1 | 0x6D80 | 0x6240 | 0x1C53BB6B | 0xBB | 0xB7 | 0x1043A770 | 0x45B9 | 0xB6 | 0x80
         | 0x1941A469 | 0x61A7 | 0x1254C367 | 0x7373 | 0x63C0 | 0x67C8 | 0x75A1 | 0xA6 | 0x8E | 0xE8): return 1;
        (0x4286 | 0x42F7 | 0x42F2 | 0x42F3 | 0x4287 | 0x4285 | 0x53AC | 0x2AD7B1 | 0xE7 | 0xA7 | 0xAB
         | 0x9B | 0xD7 | 0x73C5 | 0x83 | 0xB9 | 0x88 | 0x55AA | 0x9C | 0x23E383 | 0xB0 | 0xBA | 0x54B0
         | 0x54BA | 0x9F | 0x6264 | 0xB3 | 0xF7 | 0xF1 | 0xF0 | 0x9A | 0x56AA | 0x56BB): return 2;
        (0xFB | 0x75A2): return 3;
        (0x4282 | 0x86 | 0x22B59C | 0x447A): return 4;
        (0x7BA9 | 0x4D80 | 0x5741 | 0x536E | 0x258688 | 0x45A3 | 0x4487 | 0x466E | 0x85): return 5;
        (0x4489 | 0xB5 | 0x2383E3 | 0x78B5): return 6;
        (0x4461): return 7;
        (_): return 0;
    }
};

fn name_of(u32 id) {
    match (id) {
        (0x1A45DFA3): return "EBML";
        (0x4286): return "EBMLVersion";
        (0x42F7): return "EBMLReadVersion";
        (0x42F2): return "EBMLMaxIDLength";
        (0x42F3): return "EBMLMaxSizeLength";
        (0x4282): return "DocType";
        (0x4287): return "DocTypeVersion";
        (0x4285): return "DocTypeReadVersion";
        (0x18538067): return "Segment";
        (0x114D9B74): return "SeekHead";
        (0x4DBB): return "Seek";
        (0x53AB): return "SeekID";
        (0x53AC): return "SeekPosition";
        (0x1549A966): return "Info";
        (0x73A4): return "SegmentUID";
        (0x2AD7B1): return "TimestampScale";
        (0x4489): return "Duration";
        (0x4461): return "DateUTC";
        (0x7BA9): return "Title";
        (0x4D80): return "MuxingApp";
        (0x5741): return "WritingApp";
        (0x1F43B675): return "Cluster";
        (0xE7): return "Timestamp";
        (0xA7): return "Position";
        (0xAB): return "PrevSize";
        (0xA3): return "SimpleBlock";
        (0xA0): return "BlockGroup";
        (0xA1): return "Block";
        (0x9B): return "BlockDuration";
        (0xFB): return "ReferenceBlock";
        (0x1654AE6B): return "Tracks";
        (0xAE): return "TrackEntry";
        (0xD7): return "TrackNumber";
        (0x73C5): return "TrackUID";
        (0x83): return "TrackType";
        (0xB9): return "FlagEnabled";
        (0x88): return "FlagDefault";
        (0x55AA): return "FlagForced";
        (0x9C): return "FlagLacing";
        (0x23E383): return "DefaultDuration";
        (0x536E): return "Name";
        (0x22B59C): return "Language";
        (0x86): return "CodecID";
        (0x63A2): return "CodecPrivate";
        (0x258688): return "CodecName";
        (0x56AA): return "CodecDelay";
        (0x56BB): return "SeekPreRoll";
        (0xE0): return "Video";
        (0x9A): return "FlagInterlaced";
        (0xB0): return "PixelWidth";
        (0xBA): return "PixelHeight";
        (0x54B0): return "DisplayWidth";
        (0x54BA): return "DisplayHeight";
        (0xE1): return "Audio";
        (0xB5): return "SamplingFrequency";
        (0x9F): return "Channels";
        (0x6264): return "BitDepth";
        (0x6D80): return "ContentEncodings";
        (0x1C53BB6B): return "Cues";
        (0xBB): return "CuePoint";
        (0xB3): return "CueTime";
        (0xB7): return "CueTrackPositions";
        (0xF7): return "CueTrack";
        (0xF1): return "CueClusterPosition";
        (0xF0): return "CueRelativePosition";
        (0x1043A770): return "Chapters";
        (0x1941A469): return "Attachments";
        (0x1254C367): return "Tags";
        (0x7373): return "Tag";
        (0x63C0): return "Targets";
        (0x67C8): return "SimpleTag";
        (0x45A3): return "TagName";
        (0x4487): return "TagString";
        (0xEC): return "Void";
        (0xBF): return "CRC-32";
        (_): return builtin::std::format("0x{:X}", id);
    }
};

fn size_text(auto b) {
    if (b < 1024) return builtin::std::format("{} B", b);
    if (b < 1048576) return builtin::std::format("{:.1f} KB", b / 1024.0);
    if (b < 1073741824) return builtin::std::format("{:.1f} MB", b / 1048576.0);
    return builtin::std::format("{:.2f} GB", b / 1073741824.0);
};

// Nanoseconds since 2001-01-01, Matroska's DateUTC.
fn date_text(s128 ns) {
    s128 s = ns / 1000000000;
    s128 z = s / 86400 + 11323 + 719468;     // days since 2001, to the civil algorithm's epoch
    s128 t = s % 86400;
    if (t < 0) { t = t + 86400; z = z - 1; }
    s128 era = z / 146097;
    s128 doe = z - era * 146097;
    s128 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    s128 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    s128 mp = (5 * doy + 2) / 153;
    s128 d = doy - (153 * mp + 2) / 5 + 1;
    s128 m = mp < 10 ? mp + 3 : mp - 9;
    s128 y = yoe + era * 400 + (m <= 2 ? 1 : 0);
    return builtin::std::format("{:04}-{:02}-{:02} {:02}:{:02}:{:02} UTC", y, m, d, t / 3600, t / 60 % 60, t % 60);
};

fn track_type(auto t) {
    match (t) {
        (1): return "1 (video)";
        (2): return "2 (audio)";
        (3): return "3 (complex)";
        (16): return "16 (logo)";
        (17): return "17 (subtitle)";
        (18): return "18 (buttons)";
        (32): return "32 (control)";
        (33): return "33 (metadata)";
        (_): return builtin::std::format("{}", t);
    }
};

fn block_flags(auto f) {
    str t = builtin::std::format("0x{:02X}", f);
    if (f & 0x80) t = t + " key frame";
    if (f & 0x08) t = t + " invisible";
    if ((f >> 1) & 3) t = t + " laced";
    if (f & 0x01) t = t + " discardable";
    return t;
};

// The head of a (Simple)Block: track as a vint, time relative to the cluster, flags.
struct BlockHeader {
    u64 tl = vlen($[$]);
    u64 track = read_be($, tl) & ((1 << (7 * tl)) - 1);
    u8 track_vint[tl] [[sealed]];
    s16 relative_time;
    u8 flags [[format("block_flags")]];
} [[format_read("block_label")]];

fn block_label(ref auto b) {
    return builtin::std::format("track {}, {:+} ms{}", b.track, b.relative_time, (b.flags & 0x80) ? ", key frame" : "");
};

using Element;

fn element_label(ref auto e) {
    str t = name_of(e.id_value);
    if (e.run > 1) {
        t = builtin::std::format("{} more clusters, {}", e.run, size_text(e.end - e.begin));
        if (e.end > sizeof($)) t = t + " - the last is CUT at the end of the file";
        return t;
    }
    if (e.unknown) t = t + ", size unknown (a live or unfinished recording)";
    else t = builtin::std::format("{}, {}", t, size_text(e.end - e.begin));
    if (e.end > sizeof($)) t = t + builtin::std::format(" - CUT: {} past the end of the file", size_text(e.end - sizeof($)));
    if (e.id_value == 0x18538067 && !g_cues) t = t + " - no Cues: the seek index is missing";
    return t;
};

struct Element {
    u64 begin = $;
    u64 limit = sizeof($);
    u64 il = vlen($[$]);
    if (il == 0 || il > 4) il = 1;            // not an ID: one byte, and the tree stops below
    if ($ + il > limit) il = limit - $;       // the file ends inside the ID
    u32 id_value = read_be($, il);
    u8 id[il] [[sealed]];
    u64 sl = vlen($[$]);
    if (sl == 0) sl = 8;
    if ($ + sl > limit) sl = limit - $;       // ... or inside the size
    u64 size_field = read_be($, sl);
    u8 size[sl] [[sealed]];
    u64 mask = (1 << (7 * sl)) - 1;
    bool unknown = (size_field & mask) == mask;
    u64 end = unknown ? limit : $ + (size_field & mask);
    u64 run = 0;
    u8 kind = kind_of(id_value);

    if (id_value == 0x1F43B675) g_clusters = g_clusters + 1;
    if (id_value == 0x1C53BB6B) g_cues = true;
    if (id_value == 0x1F43B675 && g_clusters > CLUSTERS()) {
        // This cluster and the ones right after it, as one row.
        run = cluster_run(begin, 0);
        end = cluster_run(begin, 1);
        u8 clusters[min(end, sizeof($)) - $] [[sealed]];
    } else if (kind == 1) {
        if (id_value == 0x1F43B675) {
            Element children[while($ + 2 <= min(end, sizeof($)) && builtin::std::core::array_index() < BLOCKS() + 2)] [[inline]];
        } else {
            Element children[while($ + 2 <= min(end, sizeof($)))] [[inline]];
        }
    } else if (end > sizeof($)) {
        // an element the file ends inside: its value is not all here, so it stays bytes
    } else if (kind == 2 && end - $ <= 8) {
        if (id_value == 0x83) u8 value [[format("track_type")]];
        else if (end - $ == 1) u8 value;
        else if (end - $ == 2) u16 value;
        else if (end - $ == 3) u24 value;
        else if (end - $ == 4) u32 value;
        else if (end - $ == 6) u48 value;
        else if (end - $ == 8) u64 value;
    } else if (kind == 3 && end - $ <= 8) {
        u8 value_bytes[end - $] [[sealed]];
    } else if ((kind == 4 || kind == 5) && end - $ <= 256) {
        char value[end - $];
    } else if (kind == 6 && end - $ == 4) {
        float value;
    } else if (kind == 6 && end - $ == 8) {
        double value;
    } else if (kind == 7 && end - $ == 8) {
        s64 value [[format("date_text")]];
    } else if ((id_value == 0xA3 || id_value == 0xA1) && end - $ >= 4) {
        BlockHeader block;
    }
    u64 stop = min(end, sizeof($));
    if ($ < stop) u8 data[stop - $] [[sealed]];
    builtin::std::core::set_display_name(this, name_of(id_value));
} [[format_read("element_label")]];


// An unknown-size Segment or Cluster ends where the next element of its own level
// starts; this template lets it run to the end of the file, which shows the same tree.
Element elements[while($ + 2 <= sizeof($))] @ 0x00 [[inline]];
