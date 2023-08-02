const std = @import("std");
const vfs = @import("vfs.zig");
const heap = @import("../libk/heap.zig");

const log = std.log.scoped(.devfs);

var heap_allocator = heap.HeapAllocator.init();
const allocator = heap_allocator.allocator();

var devices = std.ArrayList(*vfs.Node).init(allocator);

var root: *vfs.Node = undefined;

pub fn init() void {
    root = allocator.create(vfs.Node) catch @panic("OOM");
    root.* = .{
        .name = "dev",
        .flags = .{
            .type = .directory,
            .mountpoint = false,
        },
        .inode = 0,
        .length = 0,
        .ptr = null,

        .read = null,
        .write = null,
        .open = null,
        .close = null,
        .readDir = readDir,
        .findDir = findDir,
    };

    vfs.mount("/dev/", root) catch |e| {
        log.err("Error while mounting: {}", .{e});
    };
}

pub fn addDev(node: *vfs.Node) void {
    devices.append(node) catch @panic("OOM");
    root.length = devices.items.len;
}

fn readDir(node: *vfs.Node, index: usize) !*vfs.Node {
    _ = node;
    if (index >= devices.items.len) return error.OutOfBounds;
    return devices.items[index];
}

fn findDir(node: *vfs.Node, name: []const u8) !*vfs.Node {
    _ = node;
    for (devices.items) |device| {
        if (std.mem.eql(u8, device.name, name)) return device;
    }

    return error.NotFound;
}
