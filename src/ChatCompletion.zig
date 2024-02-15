const ChatCompletion = @This();
const AI = @import("AI.zig");

const std = @import("std");

// TODO: Add support for multiple choices being in the response later on.
// TODO: Add support for function/tool calling.
// TODO: Consider creating an .init()
gpa: std.mem.Allocator,
stream: bool,
id: []const u8,
created: u64,
content: []const u8,

pub fn init(
    self: *ChatCompletion,
    gpa: std.mem.Allocator,
    stream: bool,
) void {
    self.gpa = gpa;
    self.stream = stream;
}

pub fn deinit(self: *ChatCompletion) void {
    self.gpa.free(self.id);
    // self.gpa.destroy(&self.created);
    self.gpa.free(self.content);
}

// Can I use ai.gpa here?
pub fn request(
    self: *ChatCompletion,
    ai: *AI,
    payload: AI.CompletionPayload,
) !void {
    // var arena_state = std.heap.ArenaAllocator.init(self.gpa);
    // defer arena_state.deinit();
    // const arena = arena_state.allocator();

    // const parsed_completion = try ai.chatCompletionLeaky(arena, payload);

    // self.content = try self.gpa.dupe(u8, parsed_completion.choices[0].message.content);
    // self.id = try self.gpa.dupe(u8, parsed_completion.id);
    // self.created = parsed_completion.created;

    var parsed_completion = try ai.chatCompletionParsed(payload);
    std.debug.print("HERE IS THE DATA:\n{any}\n", .{parsed_completion.value});
    defer parsed_completion.deinit();

    self.content = try self.gpa.dupe(u8, parsed_completion.value.choices[0].message.content);
    self.id = try self.gpa.dupe(u8, parsed_completion.value.id);
    self.created = parsed_completion.value.created;
}

pub fn streamRequest(
    self: *ChatCompletion,
    ai: *AI,
    payload: AI.CompletionPayload,
    handler: StreamHandler,
) !void {
    _ = self;
    _ = ai;
    _ = payload;
    _ = handler;
}

// TODO: Each provider slightly differs in stream response, would be really good to make this a per-provider type that adapts based on how the AI struct is initialized.
const ChatCompletionStream = struct {
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

pub const DebugHandler = struct {
    fn processChunk(ptr: *anyopaque, completion_stream: ChatCompletionStream) !void {
        const self: *DebugHandler = @ptrCast(@alignCast(ptr));
        _ = self;
        if (completion_stream.choices[0].delta.content == null) return;
        std.debug.print("{s}", .{completion_stream.choices[0].delta.content.?});
    }
    pub fn streamHandler(self: *DebugHandler) StreamHandler {
        return .{
            .ptr = self,
            .processChunkFn = processChunk,
        };
    }
};
pub const StreamHandler = struct {
    ptr: *anyopaque,
    processChunkFn: *const fn (ptr: *anyopaque, completion_stream: ChatCompletionStream) anyerror!void,

    fn processChunk(self: StreamHandler, completion_stream: ChatCompletionStream) !void {
        return self.processChunkFn(self.ptr, completion_stream);
    }
};
// pub const ChatCompletionResponse = struct {
//     id: []const u8,
//     object: []const u8,
//     created: u64,
//     model: []const u8,
//     choices: []Choice,
//     // Usage is not returned by the Completion endpoint when streamed.
//     usage: ?Usage = null,
// };
