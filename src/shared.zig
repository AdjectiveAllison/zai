const std = @import("std");

// TODO: Consider reworking StreamHandler into something like below for more composibility.
// pub fn StreamHandler(comptime Handler: type) type {
//     return struct {
//         const Self = @This();
//     }
// }
pub const StreamHandler = struct {
    ptr: *anyopaque,
    gpa: std.mem.Allocator,
    id: []const u8,
    created: u64,
    content: []const u8,
    processChunkFn: *const fn (ptr: *anyopaque, chunk: []const u8) anyerror!void,
    streamFinishedFn: *const fn (ptr: *anyopaque) anyerror!void,

    pub fn processChunk(self: StreamHandler, chunk: []const u8) !void {
        return self.processChunkFn(self.ptr, chunk);
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

// TODO: This isn't being used anywhere, why was it here? Why did we have it?
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
