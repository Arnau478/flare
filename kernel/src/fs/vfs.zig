const std = @import("std");
const heap = @import("../libk/heap.zig");

const log = std.log.scoped(.vfs);

var heap_allocator = heap.HeapAllocator.init();
const allocator = heap_allocator.allocator();

pub var root: *Node = undefined;

pub const NodeType = enum(u3) {
    file,
    directory,
    char_device,
    block_device,
    pipe,
    symlink,
};

pub const NodeFlags = packed struct {
    type: NodeType,
    mountpoint: bool,
};

pub const Node = struct {
    name: []const u8,
    flags: NodeFlags,
    inode: usize, // Special: 0 = none, 1 = invalid, 2 = root
    length: usize,
    ptr: ?*Node,

    read: ?*const ReadFn,
    write: ?*const WriteFn,
    open: ?*const OpenFn,
    close: ?*const CloseFn,
    readDir: ?*const ReadDirFn,
    findDir: ?*const FindDirFn,

    pub inline fn real(node: *Node) *Node {
        if (node.flags.mountpoint) return node.ptr.?;
        return node;
    }
};

pub const ReadFn = fn (node: *Node, offset: u64, buffer: []u8) anyerror!usize;
pub const WriteFn = fn (node: *Node, offset: u64, buffer: []const u8) anyerror!usize;
pub const OpenFn = fn (node: *Node) anyerror!void;
pub const CloseFn = fn (node: *Node) anyerror!void;
pub const ReadDirFn = fn (node: *Node, index: usize) anyerror!*Node;
pub const FindDirFn = fn (node: *Node, name: []const u8) anyerror!*Node;

pub fn read(node: *Node, offset: u64, buffer: []u8) !usize {
    return (node.real().read orelse return error.Uninmplemented)(node.real(), offset, buffer);
}

pub fn write(node: *Node, offset: u64, buffer: []const u8) !usize {
    return (node.real().write orelse return error.Uninmplemented)(node.real(), offset, buffer);
}

pub fn open(node: *Node) !void {
    return (node.real().open orelse return error.Uninmplemented)(node.real());
}

pub fn close(node: *Node) !void {
    return (node.real().close orelse return error.Uninmplemented)(node.real());
}

pub fn readDir(node: *Node, index: usize) !*Node {
    if (node.real().flags.type != .directory) return error.NotADirectory;
    return (node.real().readDir orelse return error.Uninmplemented)(node.real(), index);
}

pub fn findDir(node: *Node, name: []const u8) !*Node {
    if (node.real().flags.type != .directory) return error.NotADirectory;
    return (node.real().findDir orelse return error.Uninmplemented)(node.real(), name);
}

pub fn mount(path: []const u8, node: *Node) !void {
    if (path.len == 0 or path[0] != '/') return error.NonAbsolutePath;

    if (path.len == 1) {
        root.flags.mountpoint = true;
        root.ptr = node;
    } else {
        return error.Unimplemented;
    }
}

pub fn init() void {
    log.debug("Initializing", .{});
    defer log.debug("Initialization done", .{});

    log.debug("Creating root node", .{});
    root = allocator.create(Node) catch @panic("OOM");
    root.* = .{
        .name = "[root]",
        .flags = .{
            .type = .directory,
            .mountpoint = false,
        },
        .inode = 2,
        .length = 0,
        .ptr = null,
        .read = null,
        .write = null,
        .open = null,
        .close = null,
        .readDir = null,
        .findDir = null,
    };
}
