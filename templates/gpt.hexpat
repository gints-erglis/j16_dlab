#pragma description GUID Partition Table (GPT) header
#pragma endian little

struct GUID {
    u32 data1;
    u16 data2;
    u16 data3;
    u8  data4[8];
};

struct GPTHeader {
    char signature[8];      // "EFI PART"
    u32  revision;
    u32  headerSize;
    u32  headerCRC32;
    u32  reserved;
    u64  currentLBA;
    u64  backupLBA;
    u64  firstUsableLBA;
    u64  lastUsableLBA;
    GUID diskGUID;
    u64  partEntryLBA;      // usually LBA 2
    u32  numPartEntries;
    u32  sizeOfPartEntry;
    u32  partArrayCRC32;
};

// GPT header lives in LBA 1 (offset 0x200 on a 512-byte-sector disk).
GPTHeader header @ 0x200;
