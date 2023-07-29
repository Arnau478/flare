const std = @import("std");
const generic = @import("../pmm.zig");

const log = generic.log;

const BLOCK_SIZE = 4096; // TODO: This should be passed as implementation-specific PMM options
comptime {
    if (BLOCK_SIZE == 0) @compileError("BLOCK_SIZE cannot be zero");
}

const BlockRegion = struct {
    start: usize,
    size: usize,
};

var bitmapSlice: []u8 = undefined;

fn ptrFromBlock(block: usize) [*]u8 {
    return @ptrFromInt(block * BLOCK_SIZE);
}

fn blockFromPtr(ptr: [*]u8) usize {
    return @intFromPtr(ptr) / BLOCK_SIZE;
}

fn upperBlockFromPtr(ptr: [*]u8) usize {
    return std.math.divCeil(usize, @intFromPtr(ptr), BLOCK_SIZE) catch unreachable;
}

pub fn init(mmap: generic.MemoryMap) void {
    log.debug("Initializing", .{});
    defer log.debug("Initialization done", .{});
    log.info("Using {}-byte blocks", .{BLOCK_SIZE});

    var usableSectionCount: usize = 0;

    for (mmap) |section| {
        if (section.type == .usable) {
            log.debug("Usable memory section detected at {} size={}", .{ @intFromPtr(section.slice.ptr), section.slice.len });
            usableSectionCount += 1;
        }
    }

    if (usableSectionCount == 0) log.err("No usable memory sections", .{});

    const expandedRegions: []BlockRegion = generic.fba_allocator.alloc(BlockRegion, usableSectionCount) catch @panic("PMM FBA is full");

    {
        var i: usize = 0;
        for (mmap) |section| {
            if (section.type == .usable) {
                expandedRegions[i] = .{
                    .start = upperBlockFromPtr(section.slice.ptr),
                    .size = blockFromPtr(section.slice.ptr + section.slice.len) - upperBlockFromPtr(section.slice.ptr),
                };
                i += 1;
            }
        }
    }

    var metaregion: BlockRegion = expandedRegions[0];

    for (expandedRegions) |region| {
        log.debug("Block region at {} of size {}", .{ region.start, region.size });

        if (region.start < metaregion.start) metaregion.start = region.start;
        if (region.start + region.size > metaregion.start + metaregion.size) metaregion.size = region.start + region.size - metaregion.start;
    }

    log.debug("Metaregion at {} of size {}", .{ metaregion.start, metaregion.size });

    const bitmapSize = metaregion.size;
    const bitmapByteSize = std.math.divCeil(usize, bitmapSize, 8) catch unreachable;
    const bitmapBlockSize = std.math.divCeil(usize, bitmapSize, 4096) catch unreachable;

    log.debug("{} bytes ({} blocks) will be used for the bitmap", .{ bitmapByteSize, bitmapBlockSize });

    var bitmapRegion: BlockRegion = undefined;

    blk: {
        for (expandedRegions) |region| {
            if (region.size >= bitmapBlockSize) {
                bitmapRegion = .{
                    .start = region.start,
                    .size = bitmapBlockSize,
                };
                break :blk;
            }
        }

        log.err("No region big enough to fit bitmap", .{});
        unreachable;
    }

    bitmapSlice = ptrFromBlock(bitmapRegion.start)[0 .. bitmapRegion.size * BLOCK_SIZE];

    // 1. Mark everything used
    @memset(bitmapSlice, 0xFF);

    // 2. Unmark all regions
    for (expandedRegions) |region| {
        // TODO: Should use @memset for the byte-aligned ones and then bitmapSetBlock() for the few ones that aren't
        for (region.start..region.start + region.size) |i| {
            bitmapSetBlock(i, false);
        }
    }

    // 3. Remark the bitmap region
    for (bitmapRegion.start..bitmapRegion.start + bitmapRegion.size) |i| {
        bitmapSetBlock(i, true);
    }

    // TODO: Print free blocks when the function gets faster
}

inline fn bitmapSetBlock(index: usize, is_used: bool) void {
    if (is_used) {
        bitmapSlice[index / 8] |= @as(u8, 1) << @truncate(index % 8);
    } else {
        bitmapSlice[index / 8] &= ~(@as(u8, 1) << @truncate(index % 8));
    }
}

inline fn bitmapGetBlock(index: usize) bool {
    return bitmapSlice[index / 8] & (@as(u8, 1) << @truncate(index % 8)) > 0;
}

// TODO: This is slow. Maybe using some comptime-generated switch that goes byte by byte? (eg 0x6C => 4)
fn getFreeBlocks() usize {
    var count: usize = 0;
    for (0..bitmapSlice.len * 8) |i| {
        if (!bitmapGetBlock(i)) count += 1;
    }
    return count;
}

fn alloc(bytes: usize) ![]u8 {
    if (bytes % BLOCK_SIZE != 0) log.warn("Allocation size is not block-aligned, rounding up", .{});
    const blocks_to_alloc = std.math.divCeil(usize, bytes, BLOCK_SIZE) catch unreachable;
    var count: usize = 0;
    const start: usize = for (0..bitmapSlice.len * 8) |i| {
        count += 1;
        if (bitmapGetBlock(i)) count = 0;

        if (count >= blocks_to_alloc) break i - count + 1;
    } else {
        return error.OutOfMemory;
    };

    for (start..start + count) |i| {
        bitmapSetBlock(i, true);
    }

    return @as([*]u8, @ptrFromInt(start * BLOCK_SIZE))[0 .. count * BLOCK_SIZE];
}

fn free(slice: []u8) void {
    for (blockFromPtr(slice.ptr)..upperBlockFromPtr(slice.ptr + slice.len)) |i| {
        if (!bitmapGetBlock(i)) log.warn("Block {} is being freed but was not used", .{i});
        bitmapSetBlock(i, false);
    }
}
