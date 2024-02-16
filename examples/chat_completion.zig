const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_state.deinit() == .ok);
    const gpa = gpa_state.allocator();

    var ai: zai.AI = undefined;

    try ai.init(gpa, zai.Provider.OctoAI);
    defer ai.deinit();

    var messages = [_]zai.Message{
        zai.Message{
            .role = "system",
            .content = "You are a helpful AI!",
        },
        zai.Message{
            .role = "user",
            .content = "Write one sentence about how cool it would be to use zig to call language models.",
        },
    };

    const payload = zai.CompletionPayload{
        .model = "mixtral-8x7b-instruct-fp16",
        .messages = messages[0..],
        .temperature = 0.1,
        .stream = true,
    };

    var chat_completion: zai.ChatCompletion = undefined;
    chat_completion.init(gpa, false);
    defer chat_completion.deinit();

    try chat_completion.streamRequest(&ai, payload);

    std.debug.print("\nFull response: {s}\n", .{chat_completion.content});
    std.debug.print("\nID: {s}\n", .{chat_completion.id});
}
