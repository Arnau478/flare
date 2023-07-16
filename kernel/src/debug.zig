const builtin = @import("builtin");

pub fn printChar(c: u8) void {
    switch (builtin.cpu.arch) {
        .x86_64 => {
            const io = @import("arch").io;
            io.outb(0xe9, c);
        },
        else => |arch| @compileError("printChar() not implemented for " ++ arch),
    }
}
