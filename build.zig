const std = @import("std");

const package_name = "zai";
const package_path = "src/zai.zig";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the zai module
    const zai_mod = b.addModule(package_name, .{
        .root_source_file = b.path(package_path),
        .target = target,
        .optimize = optimize,
    });

    // Example section
    const chat = b.addExecutable(.{
        .name = "chat",
        .root_source_file = b.path("examples/chat.zig"),
        .target = target,
        .optimize = optimize,
    });

    chat.root_module.addImport("zai", zai_mod);
    const build_chat = b.addInstallArtifact(chat, .{});
    const build_chat_step = b.step("chat", "build the chat example.");
    build_chat_step.dependOn(&build_chat.step);

    const completion = b.addExecutable(.{
        .name = "completion",
        .root_source_file = b.path("examples/completion.zig"),
        .target = target,
        .optimize = optimize,
    });

    completion.root_module.addImport("zai", zai_mod);
    const build_completion = b.addInstallArtifact(completion, .{});
    const build_completion_step = b.step("completion", "build the completion example.");
    build_completion_step.dependOn(&build_completion.step);

    const embeddings = b.addExecutable(.{
        .name = "embeddings",
        .root_source_file = b.path("examples/embeddings.zig"),
        .target = target,
        .optimize = optimize,
    });

    embeddings.root_module.addImport("zai", zai_mod);
    const build_embeddings = b.addInstallArtifact(embeddings, .{});
    const build_embeddings_step = b.step("embeddings", "build the embeddings example.");
    build_embeddings_step.dependOn(&build_embeddings.step);

    // New Bedrock chat example
    const bedrock_chat = b.addExecutable(.{
        .name = "bedrock_chat",
        .root_source_file = b.path("examples/chat_bedrock.zig"),
        .target = target,
        .optimize = optimize,
    });

    bedrock_chat.root_module.addImport("zai", zai_mod);
    const build_bedrock_chat = b.addInstallArtifact(bedrock_chat, .{});

    const run_bedrock_chat = b.addRunArtifact(bedrock_chat);
    if (b.args) |args| {
        run_bedrock_chat.addArgs(args);
    }

    const bedrock_step = b.step("bedrock", "Build and run the Amazon Bedrock chat example");
    bedrock_step.dependOn(&build_bedrock_chat.step);
    bedrock_step.dependOn(&run_bedrock_chat.step);

    // TODO: add tests
}
