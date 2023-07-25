const std = @import("std");

const version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };

pub fn build(b: *std.Build) !void {
    const cpu_arch: std.Target.Cpu.Arch = .x86_64;

    var target: std.zig.CrossTarget = .{
        .cpu_arch = cpu_arch,
        .os_tag = .freestanding,
        .abi = .none,
    };

    const Features = std.Target.x86.Feature;
    target.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    target.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption(std.SemanticVersion, "version", version);
    options.addOption([]const u8, "pmm_impl", "bitmap_first_fit"); // TODO: Use @Type(.EnumLiteral) when the compiler allows it

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    kernel.code_model = .kernel;
    kernel.setLinkerScriptPath(.{ .path = "linker.ld" });
    kernel.addAnonymousModule("arch", .{
        .source_file = .{ .path = "src/arch/" ++ comptime @tagName(cpu_arch) ++ "/arch.zig" },
    });
    kernel.addOptions("build_options", options);
    kernel.pie = true;

    b.installArtifact(kernel);
}
