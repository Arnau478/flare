const std = @import("std");
const pmm = @import("../mm/pmm.zig");

pub const HeapAllocator = struct {
    pub fn init() HeapAllocator {
        return .{};
    }

    pub fn allocator(self: *HeapAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = std.mem.Allocator.noResize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = ret_addr;
        if (ptr_align > 12) return null; // Requested alignment is not supported by PMM :(
        return (pmm.alloc((std.math.divCeil(usize, len, 4096) catch unreachable) * 4096) catch return null).ptr;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = ctx;
        _ = buf_align;
        _ = ret_addr;
        pmm.free(buf.ptr[0 .. (std.math.divCeil(usize, buf.len, 4096) catch unreachable) * 4096]);
    }
};
