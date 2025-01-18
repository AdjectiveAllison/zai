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

    // OpenAI-compatible chat example (TogetherAI)
    const chat_openai = b.addExecutable(.{
        .name = "chat-openai",
        .root_source_file = b.path("examples/chat_openai.zig"),
        .target = target,
        .optimize = optimize,
    });
    chat_openai.root_module.addImport("zai", zai_mod);
    const build_chat_openai = b.addInstallArtifact(chat_openai, .{});
    const build_chat_openai_step = b.step("chat-openai", "Build the OpenAI-compatible chat example (OpenRouter)");
    build_chat_openai_step.dependOn(&build_chat_openai.step);

    // Amazon Bedrock chat example
    const chat_bedrock = b.addExecutable(.{
        .name = "chat-bedrock",
        .root_source_file = b.path("examples/chat_bedrock.zig"),
        .target = target,
        .optimize = optimize,
    });
    chat_bedrock.root_module.addImport("zai", zai_mod);
    const build_chat_bedrock = b.addInstallArtifact(chat_bedrock, .{});
    const build_chat_bedrock_step = b.step("chat-bedrock", "Build the Amazon Bedrock chat example (Streaming)");
    build_chat_bedrock_step.dependOn(&build_chat_bedrock.step);

    // Completion example
    const completion = b.addExecutable(.{
        .name = "completion",
        .root_source_file = b.path("examples/completion.zig"),
        .target = target,
        .optimize = optimize,
    });
    completion.root_module.addImport("zai", zai_mod);
    const build_completion = b.addInstallArtifact(completion, .{});
    const build_completion_step = b.step("completion", "Build the completion example");
    build_completion_step.dependOn(&build_completion.step);

    // Embeddings example
    const embeddings = b.addExecutable(.{
        .name = "embeddings",
        .root_source_file = b.path("examples/embeddings.zig"),
        .target = target,
        .optimize = optimize,
    });
    embeddings.root_module.addImport("zai", zai_mod);
    const build_embeddings = b.addInstallArtifact(embeddings, .{});
    const build_embeddings_step = b.step("embeddings", "Build the embeddings example");
    build_embeddings_step.dependOn(&build_embeddings.step);

    // Registry example
    const registry = b.addExecutable(.{
        .name = "registry",
        .root_source_file = b.path("examples/chat_with_config.zig"),
        .target = target,
        .optimize = optimize,
    });
    registry.root_module.addImport("zai", zai_mod);
    const build_registry = b.addInstallArtifact(registry, .{});
    const build_registry_step = b.step("registry", "Build the registry example");
    build_registry_step.dependOn(&build_registry.step);

    const registry_load = b.addExecutable(.{
        .name = "registry-load",
        .root_source_file = b.path("examples/registry_load.zig"),
        .target = target,
        .optimize = optimize,
    });
    registry_load.root_module.addImport("zai", zai_mod);
    const build_registry_load = b.addInstallArtifact(registry_load, .{});
    const build_registry_load_step = b.step("registry-load", "Build the registry loading example");
    build_registry_load_step.dependOn(&build_registry_load.step);

    const cli = b.addExecutable(.{
        .name = "zai",
        .root_source_file = b.path("src/cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli.root_module.addImport("zai", zai_mod);
    const build_cli = b.addInstallArtifact(cli, .{});
    const build_cli_step = b.step("cli", "Build the zai CLI");
    build_cli_step.dependOn(&build_cli.step);
}
