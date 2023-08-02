const std = @import("std");
const vfs = @import("vfs.zig");
const heap = @import("../libk/heap.zig");

const log = std.log.scoped(.initrd);

var heap_allocator = heap.HeapAllocator.init();
const allocator = heap_allocator.allocator();

var files = std.ArrayList(struct { node: *vfs.Node, data: ?[]const u8, offset: usize }).init(allocator);

var data: []const u8 = undefined;

fn offsetFromInode(inode: usize) !usize {
    for (files.items) |file| {
        if (file.node.real().inode == inode) return file.offset;
    }

    return error.NotFound;
}

fn nodeFromOffset(offset: usize) !*vfs.Node {
    for (files.items) |file| {
        if (file.offset == offset) return file.node.real();
    }

    return error.NotFound;
}

fn skip(offset: usize) anyerror!usize {
    var i = offset;

    switch (data[i]) {
        0x01 => {
            i += data[i + 1] + 2;
            i += std.mem.bytesToValue(u64, @as(*const [8]u8, @ptrCast(data[i .. i + 8])));
            i += 8;
        },
        0x02 => {
            i += data[i + 1] + 2;
            const child_count = data[i];
            i += 1;
            i += try skipN(i, child_count);
        },
        else => {
            log.err("Invalid initrd file header: 0x{x}", .{data[i]});
            unreachable;
        },
    }

    return i - offset;
}

fn skipN(offset: usize, n: usize) anyerror!usize {
    var res: usize = offset;
    for (0..n) |_| {
        res += try skip(res);
    }

    return res - offset;
}

pub fn init(module_data: []const u8) void {
    log.debug("Initializing", .{});
    defer log.debug("Initialization done", .{});

    data = module_data;

    log.info("Module size: {}", .{data.len});

    var i: usize = 0;
    var next_inode: usize = 3;

    while (i < data.len) {
        const offset = i;
        switch (data[i]) {
            0x01 => {
                i += 1;
                const name_length: u8 = data[i];
                i += 1;
                const name: []const u8 = data[i .. i + name_length];
                i += name_length;
                const data_size: u64 = std.mem.bytesToValue(u64, @as(*const [8]u8, @ptrCast(data[i .. i + 8])));
                i += 8;
                i += data_size;

                const node = allocator.create(vfs.Node) catch @panic("OOM");
                node.* = .{
                    .name = name,
                    .flags = .{
                        .type = .file,
                        .mountpoint = false,
                    },
                    .inode = next_inode,
                    .length = data_size,
                    .ptr = null,

                    .read = read,
                    .write = null,
                    .open = null,
                    .close = null,
                    .readDir = null,
                    .findDir = null,
                };

                files.append(.{
                    .node = node,
                    .data = data[i - data_size .. i],
                    .offset = offset,
                }) catch @panic("OOM");

                next_inode += 1;
            },
            0x02 => {
                i += 1;
                const name_length: u8 = data[i];
                i += 1;
                const name: []const u8 = data[i .. i + name_length];
                i += name_length;
                const child_count: usize = data[i];
                i += 1;

                const node = allocator.create(vfs.Node) catch @panic("OOM");
                node.* = .{
                    .name = name,
                    .flags = .{
                        .type = .directory,
                        .mountpoint = false,
                    },
                    .inode = next_inode,
                    .length = child_count,
                    .ptr = null,

                    .read = null,
                    .write = null,
                    .open = null,
                    .close = null,
                    .readDir = readDir,
                    .findDir = findDir,
                };

                files.append(.{
                    .node = node,
                    .data = null,
                    .offset = offset,
                }) catch @panic("OOM");

                next_inode += 1;
            },
            else => {
                log.err("Invalid initrd file header: 0x{x}", .{data[i]});
                unreachable;
            },
        }
    }

    vfs.mount("/", files.items[0].node) catch |e| {
        log.err("Unable to mount ({})", .{e});
    };
}

fn read(node: *vfs.Node, offset: u64, buffer: []u8) !usize {
    if (offset > node.real().length) return error.OutOfBounds;
    var size = buffer.len;
    if (offset + buffer.len > node.real().length) size = node.real().length - offset;

    const node_start_offset = try offsetFromInode(node.real().inode);
    const node_data_offset = node_start_offset + offset + data[node_start_offset + 1] + 10;
    std.mem.copy(u8, buffer[0..size], data[node_data_offset .. node_data_offset + size]);
    return size;
}

fn readDir(node: *vfs.Node, index: usize) !*vfs.Node {
    if (index >= node.real().length) return error.OutOfBounds;

    const offset = try offsetFromInode(node.real().inode);

    const res_offset = offset + data[offset + 1] + 3 + try skipN(offset + data[offset + 1] + 3, index);
    return try nodeFromOffset(res_offset);
}

fn findDir(node: *vfs.Node, name: []const u8) !*vfs.Node {
    for (0..node.real().length) |i| {
        const child = try readDir(node.real(), i);
        if (std.mem.eql(u8, child.name, name)) return child;
    }

    return error.NotFound;
}
