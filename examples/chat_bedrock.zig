const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get AWS credentials from environment
    const access_id = try std.process.getEnvVarOwned(allocator, "AWS_ACCESS_KEY_ID");
    defer allocator.free(access_id);

    const access_key = try std.process.getEnvVarOwned(allocator, "AWS_SECRET_ACCESS_KEY");
    defer allocator.free(access_key);

    // Initialize Amazon Bedrock provider
    const amazon_config = zai.ProviderConfig{ .AmazonBedrock = .{
        .region = "us-west-2",
        .access_key_id = access_id,
        .secret_access_key = access_key,
    } };

    var amazon_provider = try zai.init(allocator, amazon_config);
    defer amazon_provider.deinit();

    // Set up chat messages
    const messages = [_]zai.Message{
        .{
            .role = "system",
            .content = "You are a cryptic fortune teller who speaks in brief, mysterious riddles.",
        },
        .{
            .role = "user",
            .content = "Tell me what the future holds for AI development.",
        },
    };

    // Configure chat options
    const chat_options = zai.ChatRequestOptions{
        .model = "anthropic.claude-3-5-sonnet-20241022-v2:0",
        .messages = &messages,
        .temperature = 0.7,
        .top_p = 1.0,
        .stream = true, // Using streaming by default
    };

    // Note: For non-streaming usage, you can use the 'chat' function instead:
    //   const response = try amazon_provider.chat(chat_options);
    //   defer allocator.free(response);
    //   std.debug.print("{s}\n", .{response});

    // Stream the response
    try amazon_provider.chatStream(chat_options, std.io.getStdOut().writer());
}
