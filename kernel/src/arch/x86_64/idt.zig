const std = @import("std");

pub const log = std.log.scoped(.idt);

const GateType = enum(u4) {
    interrupt = 0b1110,
    trap = 0b1111,
};

const Entry = packed struct {
    isr_address_low: u16,
    kernel_cs: u16,
    ist: u3,
    _0: u5 = undefined,
    gate_type: GateType,
    _1: u1 = 0,
    dpl: u2,
    p: bool = true,
    isr_address_high: u48,
    _2: u32 = undefined,
};

const Idtd = packed struct {
    limit: u16,
    base: u64,
};

const IntFrame = extern struct {
    rip: u64,
    cs: u64,
    rflags: u64,
    rsp: u64,
    ss: u64,
};

const Isr = fn () callconv(.Interrupt) void;

var idt: [256]Entry = undefined;
var idtd: Idtd = undefined;

fn setEntry(index: u8, comptime isr: Isr, gate_type: GateType) void {
    idt[index] = .{
        .isr_address_low = @truncate(@intFromPtr(&isr)),
        .kernel_cs = 0x08,
        .ist = 0,
        .gate_type = gate_type,
        .dpl = 0,
        .p = true,
        .isr_address_high = @truncate(@intFromPtr(&isr) >> 16),
    };
}

pub fn init() void {
    log.debug("Ininitalizing", .{});
    defer log.debug("Initialization done", .{});

    idtd = .{
        .limit = @sizeOf(@TypeOf(idt)) - 1,
        .base = @intFromPtr(&idt),
    };

    log.debug("Loading default handlers", .{});
    inline for (0..256) |i| {
        setEntry(
            i,
            comptime getIsr(i),
            switch (@as(u8, @truncate(i))) {
                0...31 => .trap,
                32...255 => .interrupt,
            },
        );
    }
    log.debug("Default handlers loaded", .{});

    log.debug("Loading IDTD", .{});
    lidt(&idtd);
    log.debug("IDTD loaded", .{});
}

fn lidt(desc: *const Idtd) void {
    asm volatile ("lidt (%%rax)"
        :
        : [desc] "{rax}" (desc),
    );
}

fn getIsr(comptime index: u8) Isr {
    return struct {
        fn func() callconv(.Interrupt) void {
            switch (index) {
                0...31 => {
                    log.err("Unhandled exception ({})", .{index});
                },
                32...255 => {
                    log.warn("Unhandled interrupt ({})", .{index});
                },
            }
        }
    }.func;
}
