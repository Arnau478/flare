const std = @import("std");
const cpu = @import("cpu.zig");

pub const log = std.log.scoped(.gdt);

const Tss = extern struct {
    rsv_a: u32 align(1) = undefined,
    rsp: [3]u64 align(1) = [_]u64{0} ** 3,
    rsv_b: u64 align(1) = undefined,
    ist: [7]u64 align(1) = [_]u64{0} ** 7,
    rsv_c: u64 align(1) = undefined,
    rsv_d: u16 align(1) = undefined,
    iomap_base: u16 align(1) = 0,
};

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
    @bitCast(@as(u64, 0x0000000000000000)), // 0x48: TSS
    @bitCast(@as(u64, 0x0000000000000000)), // 0x50: TSS
};

var gdtd: Gdtd = undefined;

var tss: Tss = undefined;

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

    log.debug("Loading TSS", .{});
    asm volatile (
        \\mov %rsp, %rdi
        \\call setTssRsp0
    );

    gdt[9] = @bitCast(@as(u64, 0x0000E90000000000 | @sizeOf(Tss) - 1 | ((@intFromPtr(&tss) & 0xFFFFFF) << 16) | (((@intFromPtr(&tss) & 0xFF000000) >> 24) << 56)));
    gdt[10] = @bitCast(@as(u64, @intFromPtr(&tss) >> 32));

    ltr();
    log.debug("TSS loaded", .{});
}

fn lgdt(desc: *const Gdtd) void {
    asm volatile ("lgdt (%%rax)"
        :
        : [desc] "{rax}" (desc),
    );

    // We don't need to reload the segments, as they are an extension of limine's
}

fn ltr() void {
    asm volatile (
        \\mov $0x48, %ax
        \\ltr %ax
    );
}

export fn setTssRsp0(stack: u64) callconv(.C) void {
    tss.rsp[0] = stack;
}
