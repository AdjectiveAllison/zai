const std = @import("std");
const core = @import("core.zig");

pub const ParseError = error{
    MissingOptionValue,
    MissingRequiredField,
    InvalidProviderType,
} || std.mem.Allocator.Error;

// List of configs that are passed to `providers.zig`
pub const ProviderConfig = union(core.ProviderType) {
    OpenAI: OpenAIConfig,
    Anthropic: AnthropicConfig,
    GoogleVertex: GoogleVertexConfig,
    AmazonBedrock: AmazonBedrockConfig,
    Local: LocalConfig,

    pub fn parseFromOptions(allocator: std.mem.Allocator, provider_type: []const u8, options: []const []const u8) ParseError!ProviderConfig {
        var i: usize = 0;
        if (std.mem.eql(u8, provider_type, "openai")) {
            var api_key: ?[]const u8 = null;
            var base_url: ?[]const u8 = null;
            var organization: ?[]const u8 = null;
            errdefer {
                if (api_key) |key| allocator.free(key);
                if (base_url) |url| allocator.free(url);
                if (organization) |org| allocator.free(org);
            }

            while (i < options.len) : (i += 2) {
                const arg = options[i];
                if (i + 1 >= options.len) return error.MissingOptionValue;
                const value = options[i + 1];

                if (std.mem.eql(u8, arg, "--api-key")) {
                    if (api_key) |key| allocator.free(key);
                    api_key = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, arg, "--base-url")) {
                    if (base_url) |url| allocator.free(url);
                    base_url = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, arg, "--organization")) {
                    if (organization) |org| allocator.free(org);
                    organization = try allocator.dupe(u8, value);
                }
            }

            if (api_key == null or base_url == null) return error.MissingRequiredField;

            return ProviderConfig{ .OpenAI = .{
                .api_key = api_key.?,
                .base_url = base_url.?,
                .organization = organization,
            } };
        } else if (std.mem.eql(u8, provider_type, "amazon_bedrock")) {
            var access_key_id: ?[]const u8 = null;
            var secret_access_key: ?[]const u8 = null;
            var region: ?[]const u8 = null;
            errdefer {
                if (access_key_id) |key| allocator.free(key);
                if (secret_access_key) |key| allocator.free(key);
                if (region) |r| allocator.free(r);
            }

            while (i < options.len) : (i += 2) {
                const arg = options[i];
                if (i + 1 >= options.len) return error.MissingOptionValue;
                const value = options[i + 1];

                if (std.mem.eql(u8, arg, "--access-key-id")) {
                    if (access_key_id) |key| allocator.free(key);
                    access_key_id = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, arg, "--secret-access-key")) {
                    if (secret_access_key) |key| allocator.free(key);
                    secret_access_key = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, arg, "--region")) {
                    if (region) |r| allocator.free(r);
                    region = try allocator.dupe(u8, value);
                }
            }

            if (access_key_id == null or secret_access_key == null or region == null) return error.MissingRequiredField;

            return ProviderConfig{ .AmazonBedrock = .{
                .access_key_id = access_key_id.?,
                .secret_access_key = secret_access_key.?,
                .region = region.?,
            } };
        } else if (std.mem.eql(u8, provider_type, "anthropic")) {
            var api_key: ?[]const u8 = null;
            var default_max_tokens: ?u32 = null;
            errdefer {
                if (api_key) |key| allocator.free(key);
            }

            while (i < options.len) : (i += 2) {
                const arg = options[i];
                if (i + 1 >= options.len) return error.MissingOptionValue;
                const value = options[i + 1];

                if (std.mem.eql(u8, arg, "--api-key")) {
                    if (api_key) |key| allocator.free(key);
                    api_key = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, arg, "--default-max-tokens")) {
                    default_max_tokens = std.fmt.parseInt(u32, value, 10) catch |err| switch (err) {
                        error.Overflow, error.InvalidCharacter => return error.InvalidProviderType,
                    };
                }
            }

            if (api_key == null) return error.MissingRequiredField;
            if (default_max_tokens == null) return error.MissingRequiredField;

            return ProviderConfig{ .Anthropic = .{
                .api_key = api_key.?,
                .default_max_tokens = default_max_tokens.?,
            } };
        } else if (std.mem.eql(u8, provider_type, "google_vertex")) {
            var api_key: ?[]const u8 = null;
            var project_id: ?[]const u8 = null;
            var location: ?[]const u8 = null;
            errdefer {
                if (api_key) |key| allocator.free(key);
                if (project_id) |id| allocator.free(id);
                if (location) |loc| allocator.free(loc);
            }

            while (i < options.len) : (i += 2) {
                const arg = options[i];
                if (i + 1 >= options.len) return error.MissingOptionValue;
                const value = options[i + 1];

                if (std.mem.eql(u8, arg, "--api-key")) {
                    if (api_key) |key| allocator.free(key);
                    api_key = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, arg, "--project-id")) {
                    if (project_id) |id| allocator.free(id);
                    project_id = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, arg, "--location")) {
                    if (location) |loc| allocator.free(loc);
                    location = try allocator.dupe(u8, value);
                }
            }

            if (api_key == null or project_id == null or location == null) return error.MissingRequiredField;

            return ProviderConfig{ .GoogleVertex = .{
                .api_key = api_key.?,
                .project_id = project_id.?,
                .location = location.?,
            } };
        } else if (std.mem.eql(u8, provider_type, "local")) {
            var runtime: ?[]const u8 = null;
            errdefer if (runtime) |r| allocator.free(r);

            while (i < options.len) : (i += 2) {
                const arg = options[i];
                if (i + 1 >= options.len) return error.MissingOptionValue;
                const value = options[i + 1];

                if (std.mem.eql(u8, arg, "--runtime")) {
                    if (runtime) |r| allocator.free(r);
                    runtime = try allocator.dupe(u8, value);
                }
            }

            if (runtime == null) return error.MissingRequiredField;

            return ProviderConfig{ .Local = .{
                .runtime = runtime.?,
            } };
        }

        return error.InvalidProviderType;
    }

    pub fn deinit(self: *ProviderConfig, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .OpenAI => |*openai_config| {
                allocator.free(openai_config.api_key);
                allocator.free(openai_config.base_url);
                if (openai_config.organization) |org| allocator.free(org);
            },
            .AmazonBedrock => |*amazon_config| {
                allocator.free(amazon_config.access_key_id);
                allocator.free(amazon_config.secret_access_key);
                allocator.free(amazon_config.region);
            },
            .Anthropic => |*anthropic_config| {
                allocator.free(anthropic_config.api_key);
            },
            .GoogleVertex => |*google_config| {
                allocator.free(google_config.api_key);
                allocator.free(google_config.project_id);
                allocator.free(google_config.location);
            },
            .Local => |*local_config| {
                allocator.free(local_config.runtime);
            },
        }
    }

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
                try serializer.objectField("default_max_tokens");
                try serializer.write(c.default_max_tokens);
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
    default_max_tokens: u32,
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
