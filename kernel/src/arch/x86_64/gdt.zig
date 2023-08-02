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
    // Null
    Entry.make(0, 0, @bitCast(@as(u8, 0)), @bitCast(@as(u4, 0))),

    // Kernel code
    Entry.make(0, 0xFFFFF, .{
        .read_write = true,
        .direction_conforming = false,
        .executable = true,
        .type = .normal,
        .dpl = 0,
        .present = true,
    }, .{
        .long_code = true,
        .size = false,
        .granularity = true,
    }),

    // Kernel data
    Entry.make(0, 0xFFFFF, .{
        .read_write = true,
        .direction_conforming = false,
        .executable = false,
        .type = .normal,
        .dpl = 0,
        .present = true,
    }, .{
        .long_code = true,
        .size = false,
        .granularity = true,
    }),

    // User code
    Entry.make(0, 0xFFFFF, .{
        .read_write = true,
        .direction_conforming = false,
        .executable = true,
        .type = .normal,
        .dpl = 3,
        .present = true,
    }, .{
        .long_code = true,
        .size = false,
        .granularity = true,
    }),

    // User data
    Entry.make(0, 0xFFFFF, .{
        .read_write = true,
        .direction_conforming = false,
        .executable = false,
        .type = .normal,
        .dpl = 3,
        .present = true,
    }, .{
        .long_code = true,
        .size = false,
        .granularity = true,
    }),
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
}
