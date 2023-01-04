const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const exe = b.addExecutable("marbles", "src/sdl.zig");
    exe.setTarget(b.standardTargetOptions(.{}));
    exe.setBuildMode(b.standardReleaseOptions());
    exe.install();

    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_image");

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // wasm lib
    const wasm = b.addSharedLibrary("blob", "src/wasm.zig", .unversioned);
    wasm.setBuildMode(.ReleaseSmall);
    wasm.setTarget(std.zig.CrossTarget.parse(.{
        .arch_os_abi = "wasm32-freestanding",
    }) catch unreachable);
    wasm.install();
}
