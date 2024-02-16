const std = @import("std");

// pub fn StreamHandler(comptime Handler: type) type {
//     return struct {
//         const Self = @This();
//     }
// }
pub const StreamHandler = struct {
    ptr: *anyopaque,
    processChunkFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, chunk: []const u8) anyerror!void,
    streamFinishedFn: *const fn (ptr: *anyopaque) anyerror!void,

    pub fn processChunk(self: StreamHandler, allocator: std.mem.Allocator, chunk: []const u8) !void {
        return self.processChunkFn(self.ptr, allocator, chunk);
    }
    pub fn streamFinished(self: StreamHandler) !void {
        return self.streamFinishedFn(self.ptr);
    }
};

// TODO: Each provider slightly differs in stream response, would be really good to make this a per-provider type that adapts based on how the AI struct is initialized.
pub const ChatCompletionStream = struct {
    id: []const u8,
    created: u64,
    choices: []struct {
        index: u32,
        delta: struct {
            content: ?[]const u8,
        },
    },
};

const ChatCompletionStreamPartialReturn = struct {
    id: []const u8,
    created: u64,
    content: []const u8,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const CompletionPayload = struct {
    model: []const u8,
    max_tokens: ?u64 = null,
    messages: []Message,
    temperature: ?f16 = null,
    top_p: ?f16 = null,
    // TODO: Check to see if this needs to be an array or something. slice of slice is hard to do in zig.
    stop: ?[][]const u8 = null,
    frequency_penalty: ?f16 = null,
    presence_penalty: ?f16 = null,
    stream: bool = false,
};

// base url options:
// openAI: https://api.openai.com/v1
// Together: https://api.together.xyz/v1
// Octo: https://text.octoai.run/v1
// TODO: Change to tagged union with individual provider types?
pub const Provider = enum {
    OpenAI,
    TogetherAI,
    OctoAI,

    pub fn getBaseUrl(self: Provider) []const u8 {
        return switch (self) {
            .OpenAI => "https://api.openai.com/v1",
            .TogetherAI => "https://api.together.xyz/v1",
            .OctoAI => "https://text.octoai.run/v1",
        };
    }

    pub fn getKeyVar(self: Provider) []const u8 {
        return switch (self) {
            .OpenAI => "OPENAI_API_KEY",
            .TogetherAI => "TOGETHER_API_KEY",
            .OctoAI => "OCTO_API_KEY",
        };
    }
};
