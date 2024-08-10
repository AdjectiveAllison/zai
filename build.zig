const std = @import("std");

const package_name = "zai";
const package_path = "src/zai.zig";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Define the generate_providers step
    const generate_providers = b.addExecutable(.{
        .name = "generate_providers",
        .root_source_file = b.path("tools/generate_providers.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create a run step for fetch_models
    const run_generate_providers = b.addRunArtifact(generate_providers);

    // Create a generate step that depends on running fetch_models
    const generate_step = b.step("generate", "Generate provider models");
    generate_step.dependOn(&run_generate_providers.step);

    // Create the zai module
    const zai_mod = b.addModule(package_name, .{
        .root_source_file = b.path(package_path),
        .target = target,
        .optimize = optimize,
    });

    // Add the generate step as a dependency of any step that uses the zai module
    b.getInstallStep().dependOn(generate_step);

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

    const vector_store = b.addExecutable(.{
        .name = "vector_store",
        .root_source_file = b.path("examples/vector_store.zig"),
        .target = target,
        .optimize = optimize,
    });

    vector_store.root_module.addImport("zai", zai_mod);
    const build_vector_store = b.addInstallArtifact(vector_store, .{});
    const build_vector_store_step = b.step("vector_store", "Build the vector store example.");
    build_vector_store_step.dependOn(&build_vector_store.step);
}
