const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    std.debug.print("Embeddings Example\n", .{});

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_state.deinit() == .ok);
    const gpa = gpa_state.allocator();

    const api_key = try std.process.getEnvVarOwned(gpa, "OCTOAI_TOKEN");
    defer gpa.free(api_key);

    const provider_config = zai.ProviderConfig{ .OpenAI = .{
        .api_key = api_key,
        .base_url = "https://text.octoai.run/v1",
    } };
    var provider = try zai.init(gpa, provider_config);
    defer provider.deinit();

    const input_text = "Zig is a general-purpose programming language and toolchain for maintaining robust, optimal, and reusable software.";

    const embedding_options = zai.EmbeddingRequestOptions{
        .model = "thenlper/gte-large",
        .input = input_text,
    };

    const embedding = try provider.createEmbedding(embedding_options);
    defer gpa.free(embedding);

    std.debug.print("\nInput text: {s}\n", .{input_text});
    std.debug.print("\nEmbedding vector (first 5 elements): ", .{});
    for (embedding[0..@min(5, embedding.len)]) |value| {
        std.debug.print("{d:.6} ", .{value});
    }
    std.debug.print("...\n", .{});
    std.debug.print("Embedding vector length: {d}\n", .{embedding.len});

    // Note: Usage information is not available in this version of the API
    // You may need to modify the Provider interface if you want to return usage information

    std.debug.print("\nEmbedding created successfully.\n", .{});
}
