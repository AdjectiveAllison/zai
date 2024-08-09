const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_state.deinit() == .ok);
    const gpa = gpa_state.allocator();

    const provider = zai.Provider.init(.OpenRouter);

    // // BELOW I cannot auto complete with my language server. The fact that `type` in models is not specific, I can't auto selext the enum for the models represented by the specific provider that I've chosen to initializse with. That is a problem!
    // provider.models.

    // // This one works well, because we can use the provider to decide how the string is intepereted and if we have the model available. This is the easy one to do.
    // provider.modelFromString("llama-blah-blah");

    // // This one has the same problem as the regular `provider.models` part. Since it's just a `type`, we don't get auto complete!
    // provider.modelToId(model: self.models)

    var ai: zai.AI = undefined;
    try ai.init(gpa, provider);
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
        .model = "llama",
        .messages = messages[0..],
        .temperature = 0.1,
        .stream = true,
        .max_tokens = null,
    };

    var chat_completion: zai.ChatCompletion = undefined;
    chat_completion.init(gpa);
    defer chat_completion.deinit();

    // Use streamAndPrint to see the response as it comes in
    try chat_completion.streamAndPrint(&ai, payload);

    // Print the full response and ID after streaming is complete
    std.debug.print("\nFull response: {s}\n", .{chat_completion.content.items});
    std.debug.print("\nID: {s}\n", .{chat_completion.id});

    // Alternatively, if you don't want to print while streaming:
    // try chat_completion.request(&ai, payload);
    // std.debug.print("\nFull response: {s}\n", .{chat_completion.content.items});
    // std.debug.print("\nID: {s}\n", .{chat_completion.id});
}
