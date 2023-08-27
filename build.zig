const std = @import("std");

const kernel_config = .{
    .arch = std.Target.Cpu.Arch.x86_64,
};

const kernel_version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };

const PmmImpl = enum {
    bitmap_first_fit,
    bitmap_next_fit,
    bitmap_best_fit,
    bitmap_worse_fit,
};

fn getFeatures(comptime arch: std.Target.Cpu.Arch) struct { add: std.Target.Cpu.Feature.Set, sub: std.Target.Cpu.Feature.Set } {
    var add = std.Target.Cpu.Feature.Set.empty;
    var sub = std.Target.Cpu.Feature.Set.empty;
    switch (arch) {
        .x86_64 => {
            const Features = std.Target.x86.Feature;

            add.addFeature(@intFromEnum(Features.soft_float));
            sub.addFeature(@intFromEnum(Features.mmx));
            sub.addFeature(@intFromEnum(Features.sse));
            sub.addFeature(@intFromEnum(Features.sse2));
            sub.addFeature(@intFromEnum(Features.avx));
            sub.addFeature(@intFromEnum(Features.avx2));
        },
        else => @compileError("Unimplemented architecture " ++ @tagName(arch)),
    }

    return .{ .add = add, .sub = sub };
}

pub fn build(b: *std.Build) !void {
    const features = getFeatures(kernel_config.arch);

    var target: std.zig.CrossTarget = .{
        .cpu_arch = kernel_config.arch,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = features.add,
        .cpu_features_sub = features.sub,
    };

    const kernel_optimize = b.standardOptimizeOption(.{});

    const kernel_options = b.addOptions();
    kernel_options.addOption(std.SemanticVersion, "version", kernel_version);
    kernel_options.addOption(PmmImpl, "pmm_impl", .bitmap_first_fit); // TODO: Use @Type(.EnumLiteral) when the compiler allows it

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = .{ .path = "kernel/src/main.zig" },
        .target = target,
        .optimize = kernel_optimize,
    });

    if (kernel_config.arch.isX86()) kernel.code_model = .kernel;

    kernel.setLinkerScriptPath(.{ .path = "kernel/linker.ld" });

    kernel.addAnonymousModule("arch", .{
        .source_file = .{ .path = "kernel/src/arch/" ++ comptime @tagName(kernel_config.arch) ++ "/arch.zig" },
    });

    kernel.addOptions("build_options", kernel_options);

    kernel.pie = true;

    const kernel_step = b.step("kernel", "Build the kernel");
    kernel_step.dependOn(&b.addInstallArtifact(kernel, .{}).step);

    const limine_cmd = b.addSystemCommand(&.{ "bash", "scripts/limine.sh" });
    const limine_step = b.step("limine", "Download and build limine bootloader");
    limine_step.dependOn(&limine_cmd.step);

    const initrd_cmd = b.addSystemCommand(&.{ "python3", "scripts/initrfs_util.py", "create", "zig-cache/initrd", "base" });
    const initrd_step = b.step("initrd", "Build the initial ramdisk");
    initrd_step.dependOn(&initrd_cmd.step);

    const iso_cmd = b.addSystemCommand(&.{ "bash", "scripts/iso.sh" });
    iso_cmd.step.dependOn(limine_step);
    iso_cmd.step.dependOn(kernel_step);
    iso_cmd.step.dependOn(initrd_step);
    const iso_step = b.step("iso", "Build an iso file");
    iso_step.dependOn(&iso_cmd.step);

    const run_iso_cmd = b.addSystemCommand(&.{ "bash", "scripts/run_iso.sh" });
    run_iso_cmd.setEnvironmentVariable("ARCH", @tagName(kernel_config.arch));
    run_iso_cmd.step.dependOn(iso_step);
    const run_iso_step = b.step("run-iso", "Run ISO file in emulator");
    run_iso_step.dependOn(&run_iso_cmd.step);

    const clean_cmd = b.addSystemCommand(&.{
        "rm",
        "-f",
        "flare.iso",
        "-r",
        "zig-cache",
        "zig-out",
    });
    const clean_step = b.step("clean", "Remove all generated files");
    clean_step.dependOn(&clean_cmd.step);
}
