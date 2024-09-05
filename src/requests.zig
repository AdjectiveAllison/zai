const std = @import("std");
const core = @import("core.zig");

pub const ChatRequestOptions = struct {
    model: []const u8,
    messages: []const core.Message,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    n: ?u32 = null,
    stream: ?bool = null,
    stop: ?[]const []const u8 = null,
    presence_penalty: ?f32 = null,
    frequency_penalty: ?f32 = null,
    user: ?[]const u8 = null,
    seed: ?i64 = null,
};

pub const CompletionRequestOptions = struct {
    model: []const u8,
    prompt: []const u8,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    n: ?u32 = null,
    stream: ?bool = null,
    logprobs: ?u32 = null,
    echo: ?bool = null,
    stop: ?[]const []const u8 = null,
    presence_penalty: ?f32 = null,
    frequency_penalty: ?f32 = null,
    best_of: ?u32 = null,
    user: ?[]const u8 = null,
};

pub const EmbeddingRequestOptions = struct {
    model: []const u8,
    input: []const u8,
    user: ?[]const u8 = null,
    encoding_format: ?[]const u8 = null,
};
