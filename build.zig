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
    const exe = b.addExecutable(.{ .name = "zcat", .root_module = module });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Run zcat").dependOn(&run.step);
    const tests = b.addTest(.{ .root_module = module });
    b.step("test", "Run unit and parser tests").dependOn(&b.addRunArtifact(tests).step);
    const integration = b.addSystemCommand(&.{ "python3", "tests/integration.py" });
    integration.addArtifactArg(exe);
    b.step("integration", "Run CLI and PTY tests (Python 3, Unix)").dependOn(&integration.step);
}
