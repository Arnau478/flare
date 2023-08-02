const std = @import("std");

const log = std.log.scoped(.x86_64);

pub const io = @import("io.zig");
pub const cpu = @import("cpu.zig");
pub const gdt = @import("gdt.zig");
pub const idt = @import("idt.zig");
pub const syscall = @import("syscall.zig");

pub fn init() void {
    log.debug("Architecture-specific initialization started", .{});
    defer log.debug("Architecture-specific initialization done", .{});

    gdt.init();
    idt.init();
    syscall.init();
}
