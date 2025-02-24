const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get API key from environment variable
    const api_key = std.process.getEnvVarOwned(allocator, "ANTHROPIC_API_KEY") catch |err| {
        std.debug.print("Error: ANTHROPIC_API_KEY environment variable not set or couldn't be read: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(api_key);

    // Configuration for Anthropic
    const provider_config = zai.ProviderConfig{ .Anthropic = .{
        .api_key = api_key,
    }};

    // Initialize provider
    var provider = try zai.init(allocator, provider_config);
    defer provider.deinit();

    // Set up chat messages
    const messages = [_]zai.Message{
        .{
            .role = "system",
            .content = "You are a helpful assistant that provides concise answers.",
        },
        .{
            .role = "user",
            .content = "Hello! Tell me a short joke about programming.",
        },
    };

    // Configure chat options
    const chat_options = zai.ChatRequestOptions{
        .model = "claude-3-7-sonnet-20250219", // Use Claude 3.7 Sonnet
        .messages = &messages,
        .max_tokens = 1000, // Required by Anthropic
        .temperature = 0.7,
        .stream = true, // Try streaming mode
    };

    // Display the streaming response
    std.debug.print("\nStreaming Response:\n", .{});
    try provider.chatStream(chat_options, std.io.getStdOut().writer());
    std.debug.print("\n\n", .{});

    // For non-streaming response
    const chat_options_no_stream = zai.ChatRequestOptions{
        .model = "claude-3-7-sonnet-20250219", // Use Claude 3.7 Sonnet
        .messages = &messages,
        .max_tokens = 1000, // Required by Anthropic
        .temperature = 0.7,
        .stream = false,
    };

    std.debug.print("Non-streaming Response:\n", .{});
    const response = try provider.chat(chat_options_no_stream);
    defer allocator.free(response);
    std.debug.print("{s}\n", .{response});
}