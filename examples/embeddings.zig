const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    std.debug.print("Embeddings Example\n", .{});

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_state.deinit() == .ok);
    const gpa = gpa_state.allocator();

    var ai: zai.AI = undefined;
    try ai.init(gpa, zai.Provider.OctoAI);
    defer ai.deinit();

    const input_text = "Zig is a general-purpose programming language and toolchain for maintaining robust, optimal, and reusable software.";

    const payload = zai.Embeddings.EmbeddingsPayload{
        .input = input_text,
        .model = "thenlper/gte-large",
    };

    var embeddings: zai.Embeddings = undefined;
    embeddings.init(gpa);
    defer embeddings.deinit();

    try embeddings.request(&ai, payload);

    std.debug.print("\nInput text: {s}\n", .{input_text});
    std.debug.print("\nEmbedding vector (first 5 elements): ", .{});
    for (embeddings.embedding[0..@min(5, embeddings.embedding.len)]) |value| {
        std.debug.print("{d:.6} ", .{value});
    }
    std.debug.print("...\n", .{});
    std.debug.print("Embedding vector length: {d}\n", .{embeddings.embedding.len});

    std.debug.print("\nUsage:\n", .{});
    std.debug.print("  Prompt Tokens: {d}\n", .{embeddings.usage.prompt_tokens});
    std.debug.print("  Total Tokens: {d}\n", .{embeddings.usage.total_tokens});

    std.debug.print("\nMetadata:\n", .{});
    std.debug.print("  ID: {s}\n", .{embeddings.id});
    std.debug.print("  Created: {d}\n", .{embeddings.created});
}
