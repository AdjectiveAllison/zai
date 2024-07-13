const std = @import("std");

const package_name = "zai";
const package_path = "src/zai.zig";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //library module
    const zai_mod = b.addModule(package_name, .{
        .root_source_file = b.path(package_path),
        .target = target,
        .optimize = optimize,
    });

    //example section
    const chat_completion = b.addExecutable(.{
        .name = "chat_completion",
        .root_source_file = b.path("examples/chat_completion.zig"),
        .target = target,
        .optimize = optimize,
    });

    chat_completion.root_module.addImport("zai", zai_mod);
    const build_chat_completion = b.addInstallArtifact(chat_completion, .{});
    const build_chat_completion_step = b.step("chat-completion", "build the chat completion example.");
    build_chat_completion_step.dependOn(&build_chat_completion.step);
}
