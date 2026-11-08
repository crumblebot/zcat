const std = @import("std");
const ztreesitter = @import("ztreesitter");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep = b.dependency("ztreesitter", .{ .target = target, .optimize = optimize });
    const grammars = ztreesitter.addGrammars(b, dep, &.{ "zig", "javascript", "typescript", "tsx", "python", "json", "bash", "c", "rust" }, .{}) orelse return;
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ztreesitter", .module = dep.module("ztreesitter") },
            .{ .name = "grammars", .module = grammars },
        },
    });
    module.link_libc = true;
    module.addCSourceFile(.{ .file = b.path("src/image_decode.c"), .flags = &.{"-std=c11"} });
    const exe = b.addExecutable(.{ .name = "zc", .root_module = module });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Run zc").dependOn(&run.step);
    const tests = b.addTest(.{ .root_module = module });
    b.step("test", "Run unit and parser tests").dependOn(&b.addRunArtifact(tests).step);
    const integration = b.addSystemCommand(&.{ "python3", "tests/integration.py" });
    integration.addArtifactArg(exe);
    const image_tests = b.addSystemCommand(&.{ "python3", "tests/images.py" });
    image_tests.addArtifactArg(exe);
    const integration_step = b.step("integration", "Run CLI and PTY tests (Python 3, Unix)");
    integration_step.dependOn(&integration.step);
    integration_step.dependOn(&image_tests.step);
}
