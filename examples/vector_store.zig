const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ai: zai.AI = undefined;
    try ai.init(allocator, .OctoAI);
    defer ai.deinit();

    var vector_store = zai.VectorStore.init(allocator);
    defer vector_store.deinit();

    // Generate embeddings and add to store
    const texts = [_][]const u8{
        "The quick brown fox jumps over the lazy dog",
        "A journey of a thousand miles begins with a single step",
        "To be or not to be, that is the question",
    };

    for (texts, 0..) |text, i| {
        var embeddings: zai.Embeddings = undefined;
        embeddings.init(allocator);
        defer embeddings.deinit();

        try embeddings.request(&ai, .{
            .input = text,
            .model = "thenlper/gte-large",
        });

        var metadata = std.StringHashMap([]const u8).init(allocator);
        errdefer metadata.deinit();
        try metadata.put("text", text); // No need to dupe here, as VectorStore will handle it

        const id = try std.fmt.allocPrint(allocator, "text_{d}", .{i});
        errdefer allocator.free(id);

        try vector_store.addVector(id, embeddings.embedding, metadata);

        // Clean up temporary allocations
        allocator.free(id);
        metadata.deinit();
    }

    // Query the vector store
    const query_text = "What did the fox do?";
    var query_embedding: zai.Embeddings = undefined;
    query_embedding.init(allocator);
    defer query_embedding.deinit();

    try query_embedding.request(&ai, .{
        .input = query_text,
        .model = "thenlper/gte-large",
    });

    const similar_vectors = try vector_store.findSimilar(query_embedding.embedding, 2);
    defer allocator.free(similar_vectors);

    std.debug.print("Most similar texts to '{s}':\n", .{query_text});
    for (similar_vectors) |vector| {
        if (vector.metadata) |metadata| {
            if (metadata.get("text")) |text| {
                std.debug.print("- {s}\n", .{text});
            }
        }
    }
}
