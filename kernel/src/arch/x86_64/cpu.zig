const std = @import("std");

pub const Ring = u2;

test {
    try std.testing.expectEqual(@bitSizeOf(Ring), 2);
}
