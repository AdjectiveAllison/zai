const std = @import("std");
const AI = @import("AI.zig");
const shared = @import("shared.zig");

pub const ChatCompletion = @This();

gpa: std.mem.Allocator,
id: []u8 = "",
created: u64 = undefined,
content: std.ArrayList(u8),

pub const CompletionPayload = shared.CompletionPayload;

pub const UserWriter = struct {
    context: ?*anyopaque = null,
    write_fn: *const fn (context: ?*anyopaque, content: []const u8) anyerror!void,

    pub fn write(self: UserWriter, content: []const u8) !void {
        return self.write_fn(self.context, content);
    }
};

pub fn init(self: *ChatCompletion, gpa: std.mem.Allocator) void {
    self.* = .{
        .gpa = gpa,
        .id = "",
        .created = undefined,
        .content = std.ArrayList(u8).init(gpa),
    };
}

pub fn deinit(self: *ChatCompletion) void {
    self.gpa.free(self.id);
    self.content.deinit();
}

pub fn request(
    self: *ChatCompletion,
    ai: *AI,
    payload: CompletionPayload,
) !void {
    if (payload.stream) {
        const default_writer = UserWriter{
            .context = self,
            .write_fn = defaultWrite,
        };
        try self.requestStream(ai, payload, default_writer);
    } else {
        try self.nonStreamingRequest(ai, payload);
    }
}

pub fn requestStream(
    self: *ChatCompletion,
    ai: *AI,
    payload: CompletionPayload,
    user_writer: UserWriter,
) !void {
    if (!payload.stream) {
        return error.StreamingRequired;
    }

    var mutable_payload = payload;
    mutable_payload.stream = true;

    var wrapper_writer = StreamWrapper{
        .chat_completion = self,
        .user_writer = user_writer,
    };

    try ai.chatCompletionStreamRaw(mutable_payload, wrapper_writer.writer());
}

fn nonStreamingRequest(self: *ChatCompletion, ai: *AI, payload: CompletionPayload) !void {
    var parsed_completion = try ai.chatCompletionParsed(payload);
    defer parsed_completion.deinit();

    self.id = try self.gpa.dupe(u8, parsed_completion.value.id);
    self.created = parsed_completion.value.created;
    try self.content.appendSlice(parsed_completion.value.choices[0].message.content);
}

const StreamWrapper = struct {
    chat_completion: *ChatCompletion,
    user_writer: UserWriter,

    pub fn write(self: *StreamWrapper, chunk: []const u8) !usize {
        try self.processChunk(chunk);
        return chunk.len;
    }

    pub fn writer(self: *StreamWrapper) std.io.Writer(*StreamWrapper, anyerror, write) {
        return .{ .context = self };
    }

    fn processChunk(self: *StreamWrapper, chunk: []const u8) !void {
        const parsed_chunk = try std.json.parseFromSlice(
            shared.ChatCompletionStream,
            self.chat_completion.gpa,
            chunk,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        );
        defer parsed_chunk.deinit();

        if (self.chat_completion.id.len == 0) {
            self.chat_completion.id = try self.chat_completion.gpa.dupe(u8, parsed_chunk.value.id);
            self.chat_completion.created = parsed_chunk.value.created;
        }

        if (parsed_chunk.value.choices[0].delta.content) |content| {
            try self.chat_completion.content.appendSlice(content);
            try self.user_writer.write(content);
        }
    }
};

fn defaultWrite(context: ?*anyopaque, content: []const u8) !void {
    const self: *ChatCompletion = @ptrCast(@alignCast(context.?));
    try self.content.appendSlice(content);
}

pub fn streamAndPrint(
    self: *ChatCompletion,
    ai: *AI,
    payload: CompletionPayload,
) !void {
    const print_writer = UserWriter{
        .context = null,
        .write_fn = printWrite,
    };
    try self.requestStream(ai, payload, print_writer);
}

fn printWrite(_: ?*anyopaque, content: []const u8) !void {
    try std.io.getStdOut().writer().print("{s}", .{content});
}
