const std = @import("std");

const build_options = @import("build_options");

usingnamespace switch (build_options.pmm_impl) {
    else => |unknown_impl| {
        @compileLog("pmm_impl=", unknown_impl);
        @compileError("Unknown PMM implementation");
    },
};

pub fn init() void {
    // ...
}
