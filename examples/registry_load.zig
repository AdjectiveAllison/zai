const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Check if we need to create test_registry.json
    const need_to_create = blk: {
        std.fs.cwd().access("test_registry.json", .{}) catch |err| switch (err) {
            error.FileNotFound => break :blk true,
            else => |e| return e,
        };
        break :blk false;
    };

    if (need_to_create) {
        // Get AWS credentials from environment
        const access_id = try std.process.getEnvVarOwned(allocator, "AWS_ACCESS_KEY_ID");
        defer allocator.free(access_id);

        const access_key = try std.process.getEnvVarOwned(allocator, "AWS_SECRET_ACCESS_KEY");
        defer allocator.free(access_key);

        const amazon_config = zai.ProviderConfig{ .AmazonBedrock = .{
            .region = "us-west-2",
            .access_key_id = access_id,
            .secret_access_key = access_key,
        } };

        const models = [_]zai.ModelSpec{.{
            .id = "anthropic.claude-3-5-sonnet-20241022-v2:0",
            .name = "sonnet-3.5",
            .capabilities = std.EnumSet(zai.registry.Capability).init(.{
                .chat = true,
            }),
        }};

        var registry = zai.Registry.init(allocator);
        try registry.createProvider("aws", amazon_config, &models);
        try registry.saveToFile("test_registry.json");
        registry.deinit(); // Explicit deinit here
    }

    // Now load and use the registry
    var loaded_registry = try zai.Registry.loadFromFile(allocator, "test_registry.json");
    defer loaded_registry.deinit();

    // Try to get the AWS provider
    const aws_provider = loaded_registry.getProvider("aws") orelse {
        std.debug.print("Could not find AWS provider\n", .{});
        return;
    };

    std.debug.print("Found AWS provider: {s}\n", .{aws_provider.name});

    // Initialize the provider
    try loaded_registry.initProvider("aws");

    // Try to use the provider for a chat completion
    if (aws_provider.instance) |provider| {
        const messages = [_]zai.Message{
            .{ .role = "system", .content = "You are a helpful assistant." },
            .{ .role = "user", .content = "Say hello!" },
        };

        const chat_options = zai.ChatRequestOptions{
            .model = "anthropic.claude-3-5-sonnet-20241022-v2:0",
            .messages = &messages,
            .temperature = 0.7,
            .stream = false,
        };

        const response = try provider.chat(chat_options);
        defer allocator.free(response);
        std.debug.print("\nChat response:\n{s}\n", .{response});
    }
}
