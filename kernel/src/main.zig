const std = @import("std");
const limine = @import("limine.zig");
const debug = @import("debug.zig");
const arch = @import("arch");
const build_options = @import("build_options");
const pmm = @import("mm/pmm.zig");
const heap = @import("libk/heap.zig");
const vfs = @import("fs/vfs.zig");
const initrd = @import("fs/initrd.zig");

const log = std.log.scoped(.core);

var heap_allocator = heap.HeapAllocator.init();
const allocator = heap_allocator.allocator();

pub export var module_request: limine.ModuleRequest = .{};
pub export var framebuffer_request: limine.FramebufferRequest = .{};

pub const std_options = struct {
    pub const log_level = .debug; // TODO: Decide this based on build config
    pub const logFn = kernelLogFn;
};

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = error_return_trace;
    _ = ret_addr;
    log.err("PANIC: {s}", .{msg});

    arch.cpu.halt();
}

pub fn kernelLogFn(comptime level: std.log.Level, comptime scope: @TypeOf(.EnumLiteral), comptime fmt: []const u8, args: anytype) void {
    var log_alloc_buffer: [2048]u8 = undefined;
    var log_fba = std.heap.FixedBufferAllocator.init(&log_alloc_buffer);
    const log_alloc = log_fba.allocator();

    const scope_prefix = "(" ++ @tagName(scope) ++ ")";
    const prefix = switch (level) {
        .info => "\x1b[34m",
        .warn => "\x1b[33m",
        .err => "\x1b[31m",
        .debug => "\x1b[90m",
    } ++ "[" ++ comptime level.asText() ++ "]\x1b[0m" ++ " " ++ scope_prefix ++ ":";

    for (std.fmt.allocPrint(log_alloc, prefix ++ " " ++ fmt ++ "\n", args) catch "LOG_FN_OUT_OF_MEM") |char| {
        debug.printChar(char);
    }
}

pub fn getInitrdData() []u8 {
    if (module_request.response) |module_response| {
        for (module_response.modules()) |module| {
            if (std.mem.eql(u8, std.mem.span(module.path), "/initrd")) {
                return module.data();
            }
        }
    }

    log.err("No initrd module", .{});
    unreachable;
}

fn init() void {
    log.debug("Starting", .{});
    defer log.debug("Start sequence done", .{});

    pmm.init();

    vfs.init();
    initrd.init(getInitrdData());

    // Everything architecture-specific
    arch.init();
}

export fn _start() callconv(.C) noreturn {
    log.info("Version {}.{}.{}", .{ build_options.version.major, build_options.version.minor, build_options.version.patch });

    init();

    printMotd();

    fs_tree();

    if (framebuffer_request.response) |framebuffer_response| {
        if (framebuffer_response.framebuffer_count >= 1) {
            const framebuffer = framebuffer_response.framebuffers()[0];

            for (0..100) |i| {
                const pixel_offset = i * framebuffer.pitch + i * 4;
                @as(*u32, @ptrCast(@alignCast(framebuffer.address + pixel_offset))).* = 0xFFFFFFFF;
            }
        } else {
            log.warn("No framebuffer available", .{});
        }
    } else {
        log.warn("No response to framebuffer request", .{});
    }

    arch.cpu.halt();
}

fn fs_tree() void {
    fs_tree_node(vfs.root, 0) catch |e| {
        log.err("{}", .{e});
    };
}

fn fs_tree_node(node: *vfs.Node, depth: usize) !void {
    const tab = 4;
    const padding = allocator.alloc(u8, depth * tab) catch @panic("OOM");
    defer allocator.free(padding);

    @memset(padding, ' ');

    log.debug("{s}{s}", .{ padding, node.name });
    if (node.real().flags.type == .directory) {
        for (0..node.real().length) |i| try fs_tree_node(try vfs.readDir(node.real(), i), depth + 1);
    }
}

fn printMotd() void {
    const node = (vfs.findDir(vfs.findDir(vfs.root.real(), "etc") catch unreachable, "motd") catch unreachable).real();

    var buffer = allocator.alloc(u8, node.real().length) catch @panic("OOM");
    defer allocator.free(buffer);

    const read_len = vfs.read(node, 0, buffer) catch unreachable;

    log.debug("{s}", .{buffer[0..read_len]});
}
