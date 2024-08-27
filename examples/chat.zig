const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const api_key = try std.process.getEnvVarOwned(allocator, "OCTOAI_TOKEN");
    defer allocator.free(api_key);

    const config = zai.providers.ProviderConfig{ .OpenAI = .{
        .api_key = api_key,
        .base_url = "https://text.octoai.run/v1",
    } };
    var provider = try zai.providers.Provider.init(allocator, config);
    defer provider.deinit();

    const messages = [_]zai.providers.Message{
        .{
            .role = "system",
            .content = "You are a helpful AI assistant.",
        },
        .{
            .role = "user",
            .content = "What are the benefits of using zig for systems programming?",
        },
    };

    const chat_options = zai.providers.ChatRequestOptions{
        .model = "meta-llama-3.1-8b-instruct",
        .messages = messages[0..],
        .temperature = 0.7,
        .top_p = 1.0,
        .stream = false,
    };

    const chat_response = try provider.chat(chat_options);
    defer allocator.free(chat_response);
    std.debug.print("Chat response: {s}\n", .{chat_response});

    const completion_options = zai.providers.CompletionRequestOptions{
        .model = "meta-llama-3.1-8b-instruct",
        .prompt = "Hello, I'm exploring the wonderful land of",
        .temperature = 0.7,
        .top_p = 1.0,
        .stream = false,
    };

    const completion_response = try provider.completion(completion_options);
    defer allocator.free(completion_response);
    std.debug.print("Completion response: {s}\n", .{completion_response});

    const streaming_completion_options = zai.providers.CompletionRequestOptions{
        .model = "meta-llama-3.1-405b-instruct",
        .prompt = "Following this line is a long story about zig, the programming language:\n",
        .temperature = 0.7,
        .max_tokens = 15000,
        .top_p = 1.0,
        .stream = true,
    };
    const stdout = std.io.getStdOut().writer();

    try provider.completionStream(streaming_completion_options, stdout);
}
