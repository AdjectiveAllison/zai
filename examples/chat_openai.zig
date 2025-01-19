const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize TogetherAI with OpenAI-compatible API
    const api_key = try std.process.getEnvVarOwned(allocator, "OPENROUTER_API_KEY");
    defer allocator.free(api_key);

    const provider_config = zai.ProviderConfig{ .OpenAI = .{
        .api_key = api_key,
        .base_url = "https://openrouter.ai/api/v1",
    } };
    var provider = try zai.init(allocator, provider_config);
    defer provider.deinit();

    // Example 1: Basic chat completion
    const messages = [_]zai.Message{
        .{
            .role = "system",
            .content = "You are a haiku-writing assistant. Always respond with a single haiku.",
        },
        .{
            .role = "user",
            .content = "Write a haiku about programming in Zig.",
        },
    };

    const chat_options = zai.ChatRequestOptions{
        .model = "meta-llama/llama-3.3-70b-instruct",
        .messages = &messages,
        .temperature = 0.7,
        .top_p = 1.0,
        .stream = false,
    };

    const chat_response = try provider.chat(chat_options);
    defer allocator.free(chat_response);

    std.debug.print("\nNon-streaming response:\n{s}\n", .{chat_response});

    // Example 2: Streaming chat completion
    const streaming_messages = [_]zai.Message{
        .{
            .role = "system",
            .content = "You are a friendly assistant that gives very brief, one-sentence answers.",
        },
        .{
            .role = "user",
            .content = "What's your favorite thing about computer programming?",
        },
    };

    const streaming_chat_options = zai.ChatRequestOptions{
        .model = "meta-llama/llama-3.3-70b-instruct",
        .messages = &streaming_messages,
        .temperature = 0.7,
        .top_p = 1.0,
        .stream = true,
    };

    std.debug.print("\nStreaming response:\n", .{});
    try provider.chatStream(streaming_chat_options, std.io.getStdOut().writer());
}
