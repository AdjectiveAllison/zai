const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const api_key = try std.process.getEnvVarOwned(allocator, "OCTOAI_TOKEN");
    defer allocator.free(api_key);

    const provider_config = zai.ProviderConfig{ .OpenAI = .{
        .api_key = api_key,
        .base_url = "https://text.octoai.run/v1",
    } };
    var provider = try zai.init(allocator, provider_config);
    defer provider.deinit();

    const messages = [_]zai.Message{
        .{
            .role = "system",
            .content = "You are a helpful AI assistant.",
        },
        .{
            .role = "user",
            .content = "What are the benefits of using zig for systems programming?",
        },
    };

    const chat_options = zai.ChatRequestOptions{
        .model = "meta-llama-3.1-8b-instruct",
        .messages = &messages,
        .temperature = 0.7,
        .top_p = 1.0,
        .stream = false,
    };

    const chat_response = try provider.chat(chat_options);
    defer allocator.free(chat_response);
    std.debug.print("Chat response: {s}\n", .{chat_response});

    const streaming_chat_options = zai.ChatRequestOptions{
        .model = "meta-llama-3.1-8b-instruct",
        .messages = &[_]zai.Message{
            .{
                .role = "system",
                .content = "You are a helpful AI assistant.",
            },
            .{
                .role = "user",
                .content = "Tell me a story about a programmer who discovers a magical programming language.",
            },
        },
        .temperature = 0.7,
        .max_tokens = 1500,
        .top_p = 1.0,
        .stream = true,
    };

    std.debug.print("\n\nStreaming chat response:\n", .{});
    try provider.chatStream(streaming_chat_options, std.io.getStdOut().writer());
}
