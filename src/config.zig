const std = @import("std");
const core = @import("core.zig");

// List of configs that are passed to `providers.zig`
pub const ProviderConfig = union(core.ProviderType) {
    OpenAI: OpenAIConfig,
    Anthropic: AnthropicConfig,
    GoogleVertex: GoogleVertexConfig,
    AmazonBedrock: AmazonBedrockConfig,
    Local: LocalConfig,

    pub fn jsonStringify(self: @This(), serializer: anytype) !void {
        try serializer.beginObject();
        switch (self) {
            .OpenAI => |c| {
                try serializer.objectField("type");
                try serializer.write("openai");
                try serializer.objectField("api_key");
                try serializer.write(c.api_key);
                try serializer.objectField("base_url");
                try serializer.write(c.base_url);
                if (c.organization) |org| {
                    try serializer.objectField("organization");
                    try serializer.write(org);
                }
            },
            .Anthropic => |c| {
                try serializer.objectField("type");
                try serializer.write("anthropic");
                try serializer.objectField("api_key");
                try serializer.write(c.api_key);
                try serializer.objectField("anthropic_version");
                try serializer.write(c.anthropic_version);
            },
            .GoogleVertex => |c| {
                try serializer.objectField("type");
                try serializer.write("google_vertex");
                try serializer.objectField("api_key");
                try serializer.write(c.api_key);
                try serializer.objectField("project_id");
                try serializer.write(c.project_id);
                try serializer.objectField("location");
                try serializer.write(c.location);
            },
            .AmazonBedrock => |c| {
                try serializer.objectField("type");
                try serializer.write("amazon_bedrock");
                try serializer.objectField("access_key_id");
                try serializer.write(c.access_key_id);
                try serializer.objectField("secret_access_key");
                try serializer.write(c.secret_access_key);
                try serializer.objectField("region");
                try serializer.write(c.region);
            },
            .Local => |c| {
                try serializer.objectField("type");
                try serializer.write("local");
                try serializer.objectField("runtime");
                try serializer.write(c.runtime);
            },
        }
        try serializer.endObject();
    }
};

pub const OpenAIConfig = struct {
    api_key: []const u8,
    base_url: []const u8,
    organization: ?[]const u8 = null,
};

pub const AnthropicConfig = struct {
    api_key: []const u8,
    anthropic_version: []const u8,
};

pub const GoogleVertexConfig = struct {
    api_key: []const u8,
    project_id: []const u8,
    location: []const u8,
};

pub const AmazonBedrockConfig = struct {
    access_key_id: []const u8,
    secret_access_key: []const u8,
    region: []const u8,
};

pub const LocalConfig = struct {
    // https://github.com/zml/zml?tab=readme-ov-file#running-models-on-gpu--tpu
    runtime: []const u8,
};
