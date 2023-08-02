const std = @import("std");
const cpu = @import("cpu.zig");

pub const log = std.log.scoped(.gdt);

const Gdtd = packed struct {
    size: u16,
    offset: u64,
};

const EntryAccess = packed struct {
    accessed: bool = false,
    read_write: bool,
    direction_conforming: bool,
    executable: bool,
    type: enum(u1) {
        system = 0,
        normal = 1,
    },
    dpl: cpu.Ring,
    present: bool,
};

const EntryFlags = packed struct {
    rsv: u1 = undefined,
    long_code: bool,
    size: bool,
    granularity: bool,
};

const Entry = packed struct {
    limit_a: u16,
    base_a: u24,
    access: EntryAccess,
    limit_b: u4,
    flags: EntryFlags,
    base_b: u8,

    fn make(limit: u20, base: u32, access: EntryAccess, flags: EntryFlags) Entry {
        return .{
            .limit_a = @truncate(limit),
            .base_a = @truncate(base),
            .access = access,
            .limit_b = @truncate(limit >> 16),
            .flags = flags,
            .base_b = @truncate(base >> 24),
        };
    }
};

var gdt = [_]Entry{
    @bitCast(@as(u64, 0x0000000000000000)), // 0x00: NULL
    @bitCast(@as(u64, 0x00009a000000ffff)), // 0x08: LIMINE 16-BIT KCODE
    @bitCast(@as(u64, 0x000092000000ffff)), // 0x10: LIMINE 16-BIT KDATA
    @bitCast(@as(u64, 0x00cf9a000000ffff)), // 0x18: LIMINE 32-BIT KCODE
    @bitCast(@as(u64, 0x00cf92000000ffff)), // 0x20: LIMINE 32-BIT KDATA
    @bitCast(@as(u64, 0x00209A0000000000)), // 0x28: 64-BIT KCODE
    @bitCast(@as(u64, 0x0000920000000000)), // 0x30: 64-BIT KDATA
    @bitCast(@as(u64, 0x0000F20000000000)), // 0x3B: 64-BIT UDATA
    @bitCast(@as(u64, 0x0020FA0000000000)), // 0x43: 64-BIT UCODE
};

var gdtd: Gdtd = undefined;

pub fn init() void {
    log.debug("Initializing", .{});
    defer log.debug("Initialization done", .{});
    gdtd = .{
        .offset = @intFromPtr(&gdt),
        .size = @sizeOf(@TypeOf(gdt)) - 1,
    };

    log.debug("Loading GDTD", .{});
    lgdt(&gdtd);
    log.debug("GDTD loaded", .{});
}

fn lgdt(desc: *const Gdtd) void {
    asm volatile ("lgdt (%%rax)"
        :
        : [desc] "{rax}" (desc),
    );

    // We don't need to reload the segments, as they are an extension of limine's
}
