//date picker ref: https://www.npmjs.com/package/@w3cj/magic-date-picker
//ultralight ref: https://ultralig.ht/api/c/1_4_0/
// - in deps/ultralight/.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-ultralight-x11",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    //ULTRALIGHT
    //headers
    exe.addIncludePath(b.path("deps/ultralight/include"));

    //import-lib search path
    exe.addLibraryPath(b.path("deps/ultralight/bin"));

    //runtime search path
    exe.addRPath(b.path("deps/ultralight/bin"));

    exe.linkSystemLibrary("Ultralight");
    exe.linkSystemLibrary("UltralightCore");
    exe.linkSystemLibrary("WebCore");

    //X11
    exe.linkSystemLibrary("X11");

    exe.linkLibC();

    //install
    const install_exe = b.addInstallArtifact(exe, .{});

    //copy the ultralight files so the whole thing is self-contained
    const copy_libs = b.addInstallDirectory(.{
        .source_dir = b.path("deps/ultralight/bin"),
        .install_dir = .bin,
        .install_subdir = "",
    });
    const copy_resources = b.addInstallDirectory(.{
        .source_dir = b.path("deps/ultralight/resources"),
        .install_dir = .bin,
        .install_subdir = "resources",
    });

    const install_step = b.getInstallStep();
    install_step.dependOn(&install_exe.step);
    install_step.dependOn(&copy_libs.step);
    install_step.dependOn(&copy_resources.step);

    //Run - set cwd so that ./resources path works
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.setCwd(b.path("zig-out/bin"));
    run_cmd.step.dependOn(install_step);
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Build and run the application");
    run_step.dependOn(&run_cmd.step);
}

