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

    var registry = zai.Registry.init(allocator);
    defer registry.deinit();

    const models: []const zai.ModelSpec = &[_]zai.ModelSpec{
        .{
            .id = "anthropic.claude-3-5-sonnet-20241022-v2:0",
            .name = "sonnet-3.5",
            .capabilities = std.EnumSet(zai.registry.Capability).init(.{
                .chat = true,
            }),
        },
    };

    try registry.createProvider(
        "aws",
        amazon_config,
        models,
    );

    try registry.saveToFile("/home/allison/git/zai/test_registry.json");
}
