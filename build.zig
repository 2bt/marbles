const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const exe = b.addExecutable(.{
        .name = "marbles",
        .root_source_file = .{ .path = "src/sdl.zig" },
    });
    b.installArtifact(exe);

    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_image");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // wasm
    const wasm = b.addExecutable(.{
        .name = "blob",
        .root_source_file = .{ .path = "src/wasm.zig" },
        .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
        .optimize = .ReleaseSmall,
    });
    wasm.entry = .disabled;
    wasm.export_symbol_names = &.{
        "init",
        "update",
        "pixels",
        "width",
        "height",
    };
    b.installArtifact(wasm);
}
