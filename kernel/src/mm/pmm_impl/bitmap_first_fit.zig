const std = @import("std");

const log = std.log.scoped(.pmm);

pub fn init_impl() void {
    log.degub("Initializing");
    defer log.debug("Initialization done");
}
