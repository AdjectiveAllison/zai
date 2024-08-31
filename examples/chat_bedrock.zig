const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load Amazon Bedrock credentials from environment variables
    const access_key_id = try std.process.getEnvVarOwned(allocator, "AWS_ACCESS_KEY_ID");
    defer allocator.free(access_key_id);
    const secret_access_key = try std.process.getEnvVarOwned(allocator, "AWS_SECRET_ACCESS_KEY");
    defer allocator.free(secret_access_key);
    const region = try std.process.getEnvVarOwned(allocator, "AWS_REGION");
    defer allocator.free(region);

    const provider_config = zai.ProviderConfig{ .AmazonBedrock = .{
        .access_key_id = access_key_id,
        .secret_access_key = secret_access_key,
        .region = region,
        .base_url = try std.fmt.allocPrint(allocator, "https://bedrock-runtime.{s}.amazonaws.com", .{region}),
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
        .model = "anthropic.claude-3-5-sonnet-20240620-v1:0",
        .messages = &messages,
        .temperature = 0.7,
        .top_p = 1.0,
        .stream = false,
    };

    const chat_response = try provider.chat(chat_options);
    defer allocator.free(chat_response);
    std.debug.print("Chat response: {s}\n", .{chat_response});

    const streaming_chat_options = zai.ChatRequestOptions{
        .model = "anthropic.claude-3-5-sonnet-20240620-v1:0",
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
