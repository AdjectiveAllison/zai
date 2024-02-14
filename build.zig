const std = @import("std");

const package_name = "zai";
const package_path = "src/zai.zig";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule(package_name, .{
        .root_source_file = .{ .path = package_path },
        .target = target,
        .optimize = optimize,
    });
}
