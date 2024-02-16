const ChatCompletion = @This();
const AI = @import("AI.zig");
const StreamHandler = @import("shared.zig").StreamHandler;
const std = @import("std");
const ChatCompletionStream = @import("shared.zig").ChatCompletionStream;
const CompletionPayload = @import("shared.zig").CompletionPayload;

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
    self.gpa.free(self.content);
}

// Can I use ai.gpa here?
pub fn request(
    self: *ChatCompletion,
    ai: *AI,
    payload: CompletionPayload,
) !void {
    var parsed_completion = try ai.chatCompletionParsed(payload);
    defer parsed_completion.deinit();

    self.content = try self.gpa.dupe(u8, parsed_completion.value.choices[0].message.content);
    self.id = try self.gpa.dupe(u8, parsed_completion.value.id);
    self.created = parsed_completion.value.created;
}

pub fn streamRequest(
    self: *ChatCompletion,
    ai: *AI,
    payload: CompletionPayload,
    // handler: StreamHandler,
) !void {
    var debug_handler = DebugHandler{};
    const stream_handler = debug_handler.streamHandler();

    try ai.chatCompletionStreamRaw(payload, stream_handler);

    self.content = try std.fmt.allocPrint(self.gpa, "Hello!", .{});
    self.id = try std.fmt.allocPrint(self.gpa, "1245125", .{});
}

// fn process_chat_completion_stream(
//     self: *AI,
//     http_request: *std.http.Client.Request,
//     partial_response: *ChatCompletionStreamPartialReturn,
// ) !void {
//     var response_asigned = false;
//     var content_list = std.ArrayList(u8).init(self.gpa);
//     // defer content_list.deinit();

//     // TODO: Decide how stream handlers can be passed in.
//     var debug_handler = DebugHandler{};
//     const stream_handler = debug_handler.streamHandler();

//     while (true) {
//         const chunk_reader = try http_request.reader().readUntilDelimiterOrEofAlloc(self.gpa, '\n', 1638400);
//         if (chunk_reader == null) break;

//         const chunk = chunk_reader.?;
//         defer self.gpa.free(chunk);

//         if (std.mem.eql(u8, chunk, "data: [DONE]")) break;

//         if (!std.mem.startsWith(u8, chunk, "data: ")) continue;

//         // std.debug.print("Here is the chunk: {any}\n", .{chunk[6..]});

//         const parsed_chunk = try std.json.parseFromSlice(
//             ChatCompletionStream,
//             chunk[6..],
//             .{ .ignore_unknown_fields = true },
//         );

//         if (!response_asigned) {
//             partial_response.id = parsed_chunk.id;
//             partial_response.created = parsed_chunk.created;
//             response_asigned = true;
//         }

//         try stream_handler.processChunk(parsed_chunk);

//         if (parsed_chunk.choices[0].delta.content == null) continue;

//         try content_list.appendSlice(parsed_chunk.choices[0].delta.content.?);
//     }

//     partial_response.content = try content_list.toOwnedSlice();
// }

pub const DebugHandler = struct {
    fn processChunk(ptr: *anyopaque, gpa: std.mem.Allocator, chunk: []const u8) !void {
        const self: *DebugHandler = @ptrCast(@alignCast(ptr));
        _ = self;

        const parsed_chunk = try std.json.parseFromSlice(
            ChatCompletionStream,
            gpa,
            chunk,
            .{
                .ignore_unknown_fields = true,
                .allocate = .alloc_always,
            },
        );
        defer parsed_chunk.deinit();
        const content = parsed_chunk.value.choices[0].delta.content orelse return;
        std.debug.print("{s}", .{content});
    }
    fn streamFinished(ptr: *anyopaque) !void {
        const self: *DebugHandler = @ptrCast(@alignCast(ptr));
        _ = self;
        std.debug.print("\n\n------We did it!------\n\n", .{});
    }
    pub fn streamHandler(self: *DebugHandler) StreamHandler {
        return .{
            .ptr = self,
            .processChunkFn = processChunk,
            .streamFinishedFn = streamFinished,
        };
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
