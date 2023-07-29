const std = @import("std");
const limine = @import("../limine.zig");
const build_options = @import("build_options");

const FBA_BUFFER_SIZE = 4096;

pub const log = std.log.scoped(.pmm);

pub const MemoryMap = []MemorySection;

pub const MemorySection = struct {
    slice: []u8,
    type: MemorySectionType,
};

pub const MemorySectionType = limine.MemoryMapEntryType;

pub export var mmap_request: limine.MemoryMapRequest = .{};

var fba_buffer: [FBA_BUFFER_SIZE]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&fba_buffer);
pub const fba_allocator = fba.allocator();

const impl = switch (build_options.pmm_impl) {
    .bitmap_first_fit => @import("pmm_impl/bitmap_first_fit.zig"),
    else => |unknown_impl| {
        @compileLog("pmm_impl=", unknown_impl);
        @compileError("Unknown PMM implementation");
    },
};

pub fn init() void {
    log.info("Implementation: {s}", .{@tagName(build_options.pmm_impl)});

    if (mmap_request.response) |mmap_response| {
        if (mmap_response.entry_count == 0) {
            log.err("Memory map has no entries", .{});
            unreachable;
        }

        const mmap: MemoryMap = fba_allocator.alloc(MemorySection, mmap_response.entry_count) catch @panic("PMM FBA is full");

        for (0..mmap_response.entry_count) |i| {
            const entry = mmap_response.entries()[i];
            mmap[i] = .{
                .slice = @as([*]u8, @ptrFromInt(entry.base))[0..entry.length],
                .type = entry.kind,
            };
        }

        impl.init(mmap);

        fba_allocator.free(mmap);
    } else {
        log.err("No memory map available", .{});
        unreachable;
    }
}

pub fn alloc(bytes: usize) ![]u8 {
    return impl.alloc(bytes);
}

pub fn free(slice: []u8) void {
    impl.free(slice);
}
