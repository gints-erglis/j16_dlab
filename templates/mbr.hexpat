#pragma description Master Boot Record (MBR) partition table
#pragma endian little

enum PartitionType : u8 {
    Empty          = 0x00,
    FAT12          = 0x01,
    FAT16_Small    = 0x04,
    Extended_CHS   = 0x05,
    FAT16          = 0x06,
    NTFS_exFAT     = 0x07,
    FAT32_CHS      = 0x0B,
    FAT32_LBA      = 0x0C,
    FAT16_LBA      = 0x0E,
    Extended_LBA   = 0x0F,
    LinuxSwap      = 0x82,
    Linux          = 0x83,
    LinuxLVM       = 0x8E,
    GPT_Protective = 0xEE,
    EFI_System     = 0xEF,
};

bitfield CHS {
    head      : 8;
    sector    : 6;
    cylinder  : 10;
};

struct PartitionEntry {
    u8            status;        // 0x80 = active/bootable
    CHS           startCHS;
    PartitionType type;
    CHS           endCHS;
    u32           lbaStart;      // first sector (LBA)
    u32           sectorCount;   // size in sectors
};

struct MBR {
    u8             bootCode[446];
    PartitionEntry partitions[4];
    u16            bootSignature; // expected 0xAA55
};

MBR mbr @ 0x00;
