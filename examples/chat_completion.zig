const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    std.debug.print("Tag name: {s}\n", .{@tagName(zai.ChatCompletionModel.codellama_70b_instruct_fp16)});
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
        .model = "meta-llama-3-70b-instruct",
        .messages = messages[0..],
        .temperature = 0.1,
        .stream = true,
        .max_tokens = null,
    };

    var chat_completion: zai.ChatCompletion = undefined;
    chat_completion.init(gpa);
    defer chat_completion.deinit();

    try chat_completion.request(&ai, payload);

    std.debug.print("\nFull response: {s}\n", .{chat_completion.content});
    std.debug.print("\nID: {s}\n", .{chat_completion.id});
}
