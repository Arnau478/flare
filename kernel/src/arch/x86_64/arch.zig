const std = @import("std");

const log = std.log.scoped(.x86_64);

pub const io = @import("io.zig");
pub const idt = @import("idt.zig");

pub fn init() void {
    log.debug("Architecture-specific initialization started", .{});
    defer log.debug("Architecture-specific initialization done", .{});

    idt.init();
}
