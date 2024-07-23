const std = @import("std");
const AI = @import("AI.zig");
const shared = @import("shared.zig");

pub const Embeddings = @This();

gpa: std.mem.Allocator,
id: []u8 = "",
created: u64 = undefined,
embedding: []f32 = &[_]f32{},
usage: Usage,

pub const EmbeddingsPayload = struct {
    input: []const u8,
    model: []const u8,
};

pub const Usage = struct {
    prompt_tokens: u64,
    total_tokens: u64,
};

pub fn init(self: *Embeddings, gpa: std.mem.Allocator) void {
    self.* = .{
        .gpa = gpa,
        .id = "",
        .created = undefined,
        .embedding = &[_]f32{},
        .usage = undefined,
    };
}

pub fn deinit(self: *Embeddings) void {
    self.gpa.free(self.id);
    self.gpa.free(self.embedding);
}

pub fn request(
    self: *Embeddings,
    ai: *AI,
    payload: EmbeddingsPayload,
) !void {
    var parsed_response = try ai.embeddingsParsed(payload);
    defer parsed_response.deinit();

    self.id = try self.gpa.dupe(u8, parsed_response.value.id);
    self.created = parsed_response.value.created;
    self.usage = parsed_response.value.usage;

    if (parsed_response.value.data.len > 0) {
        self.embedding = try self.gpa.dupe(f32, parsed_response.value.data[0].embedding);
    }
}
