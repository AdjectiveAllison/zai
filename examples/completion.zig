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

    const completion_options = zai.CompletionRequestOptions{
        .model = "meta-llama-3.1-8b-instruct",
        .prompt = "Hello, I'm exploring the wonderful land of",
        .temperature = 0.7,
        .top_p = 1.0,
        .stream = false,
    };

    const completion_response = try provider.completion(completion_options);
    defer allocator.free(completion_response);
    std.debug.print("Completion response: {s}\n", .{completion_response});

    const streaming_completion_options = zai.CompletionRequestOptions{
        .model = "meta-llama-3.1-8b-instruct",
        .prompt = "Following this line is a long story about zig, the programming language:\n",
        .temperature = 0.7,
        .max_tokens = 1500,
        .top_p = 1.0,
        .stream = true,
    };
    const stdout = std.io.getStdOut().writer();

    std.debug.print("\n\nStreaming completion response:\n", .{});
    try provider.completionStream(streaming_completion_options, stdout);
}