const std = @import("std");
const limine = @import("../limine.zig");
const vfs = @import("../fs/vfs.zig");
const devfs = @import("../fs/devfs.zig");
const heap = @import("../libk/heap.zig");

const log = std.log.scoped(.framebuffer);

var heap_allocator = heap.HeapAllocator.init();
const allocator = heap_allocator.allocator();

var framebuffers: []*limine.Framebuffer = &.{};

pub export var framebuffer_request: limine.FramebufferRequest = .{};

pub fn init() void {
    log.debug("Initializing", .{});
    defer log.debug("Initialization done", .{});
    if (framebuffer_request.response) |framebuffer_response| {
        if (framebuffer_response.framebuffer_count > 0) {
            framebuffers = framebuffer_response.framebuffers();

            for (framebuffers, 0..) |framebuffer, i| {
                var dev_node = allocator.create(vfs.Node) catch @panic("OOM");
                dev_node.* = .{
                    .name = std.fmt.allocPrint(allocator, "fb{}", .{i}) catch @panic("OOM"),
                    .flags = .{
                        .type = .char_device,
                        .mountpoint = false,
                    },
                    .inode = i,
                    .length = framebuffer.pitch * framebuffer.height,
                    .ptr = null,

                    .read = null,
                    .write = bufferWrite,
                    .open = null,
                    .close = null,
                    .readDir = null,
                    .findDir = null,
                };

                devfs.addDev(dev_node);
            }
        }
    }
}

fn bufferWrite(node: *vfs.Node, offset: usize, buffer: []const u8) !usize {
    if (node.real().inode >= framebuffers.len) return error.NotFound;
    if (offset + buffer.len > node.real().length) return error.OutOfBounds;
    const framebuffer = framebuffers[node.real().inode];

    @memcpy(framebuffer.data()[offset .. offset + buffer.len], buffer);

    return buffer.len;
}
