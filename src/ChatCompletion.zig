const ChatCompletion = @This();
const AI = @import("AI.zig");
const StreamHandler = @import("shared.zig").StreamHandler;
const std = @import("std");
const ChatCompletionStream = @import("shared.zig").ChatCompletionStream;
const CompletionPayload = @import("shared.zig").CompletionPayload;

// TODO: Add support for multiple choices being in the response later on.
// TODO: Add support for function/tool calling.
gpa: std.mem.Allocator,
id: []u8 = "",
created: u64 = undefined,
content: []u8 = "",

pub fn init(self: *ChatCompletion, gpa: std.mem.Allocator) void {
    self.* = .{ .gpa = gpa };
}

pub fn deinit(self: *ChatCompletion) void {
    self.gpa.free(self.id);
    self.gpa.free(self.content);
}

// TODO: Make it so that we can handle the stream in different ways other than just debug printing like is done currently.
pub fn request(
    self: *ChatCompletion,
    ai: *AI,
    payload: CompletionPayload,
) !void {
    if (payload.stream) {
        try ai.chatCompletionStreamRaw(payload, self.streamHandler());
        return;
    }

    var parsed_completion = try ai.chatCompletionParsed(payload);
    defer parsed_completion.deinit();

    self.content = try self.gpa.dupe(u8, parsed_completion.value.choices[0].message.content);
    self.id = try self.gpa.dupe(u8, parsed_completion.value.id);
    self.created = parsed_completion.value.created;
}

// STREAM HANDLING GOING ON BELOW.
fn processChunk(ptr: *anyopaque, chunk: []const u8) !void {
    const self: *ChatCompletion = @ptrCast(@alignCast(ptr));

    const parsed_chunk = try std.json.parseFromSlice(
        ChatCompletionStream,
        self.gpa,
        chunk,
        .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        },
    );
    defer parsed_chunk.deinit();
    const content = parsed_chunk.value.choices[0].delta.content orelse return;
    std.debug.print("{s}", .{content});

    var content_list: std.ArrayList(u8) = undefined;

    if (self.content.len == 0) {
        content_list = try std.ArrayList(u8).initCapacity(self.gpa, content.len);
        self.id = try self.gpa.dupe(u8, parsed_chunk.value.id);
        self.created = parsed_chunk.value.created;
    } else {
        content_list = std.ArrayList(u8).fromOwnedSlice(self.gpa, self.content);
    }
    try content_list.appendSlice(content);
    self.content = try content_list.toOwnedSlice();
}
fn streamFinished(ptr: *anyopaque) !void {
    const self: *ChatCompletion = @ptrCast(@alignCast(ptr));
    _ = self;
    // std.debug.print("\n\n------We did it!------\n\n", .{});
}

fn streamHandler(self: *ChatCompletion) StreamHandler {
    return .{
        .ptr = self,
        .gpa = self.gpa,
        .id = self.id,
        .created = self.created,
        .content = self.content,
        .processChunkFn = processChunk,
        .streamFinishedFn = streamFinished,
    };
}
