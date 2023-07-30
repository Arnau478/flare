const std = @import("std");

pub const Ring = u2;

pub inline fn halt() noreturn {
    while (true) asm volatile ("hlt");
}

test {
    try std.testing.expectEqual(@bitSizeOf(Ring), 2);
}
