const std = @import("std");
const cpu = @import("cpu.zig");

pub const log = std.log.scoped(.syscall);

const Handler = fn () void;

const TableEntry = struct {
    name: []const u8,
    handler: Handler,
};

const table = [_]TableEntry{};

export fn syscallHandler(ctx: cpu.Context) callconv(.C) void {
    log.debug("{}", .{ctx});
}

fn bareHandler() callconv(.Naked) void {
    asm volatile (
        \\.extern syscallHandler
        \\cli 
        \\swapgs
        \\mov %rsp,%gs:0x0
        \\mov %gs:0x8,%rsp
        \\push $0x3b
        \\push %gs:0x0
        \\push %r11
        \\push $0x43
        \\push %rcx
        \\push $0x0
        \\swapgs
        \\push %rax
        \\push %rbx
        \\push %rcx
        \\push %rdx
        \\push %rsi
        \\push %rdi
        \\push %rbp
        \\push %r8
        \\push %r9
        \\push %r10
        \\push %r11
        \\push %r12
        \\push %r13
        \\push %r14
        \\push %r15
        \\mov %rsp,%rdi
        \\xor %rbp,%rbp
        \\call syscallHandler
        \\pop %r15
        \\pop %r14
        \\pop %r13
        \\pop %r12
        \\pop %r11
        \\pop %r10
        \\pop %r9
        \\pop %r8
        \\pop %rbp
        \\pop %rdi
        \\pop %rsi
        \\pop %rdx
        \\pop %rcx
        \\pop %rbx
        \\pop %rax
        \\cli
        \\swapgs
        \\mov %gs:0x0,%rsp
        \\swapgs
        \\sysretq
    );
}

pub fn init() void {
    log.debug("Initializing", .{});
    defer log.debug("Initialization done", .{});
    cpu.wrmsr(0xC0000080, cpu.rdmsr(0xC0000080) | 1);
    cpu.wrmsr(0xC0000081, (0x28 << 32) | (0x33 << 48));
    cpu.wrmsr(0xC0000082, @intFromPtr(&bareHandler));
    cpu.wrmsr(0xC0000084, 0xFFFFFFFE);
}
