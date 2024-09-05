const std = @import("std");
const core = @import("core.zig");

pub const ProviderConfig = union(core.ProviderType) {
    OpenAI: OpenAIConfig,
    Anthropic: AnthropicConfig,
    GoogleVertex: GoogleVertexConfig,
    AmazonBedrock: AmazonBedrockConfig,
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
    base_url: []const u8,
};

pub const ConfigManager = struct {
    allocator: std.mem.Allocator,
    current_config: ProviderConfig,

    pub fn init(allocator: std.mem.Allocator, config: ProviderConfig) ConfigManager {
        return .{
            .allocator = allocator,
            .current_config = config,
        };
    }

    pub fn deinit(self: *ConfigManager) void {
        switch (self.current_config) {
            .OpenAI => |*c| {
                self.allocator.free(c.api_key);
                self.allocator.free(c.base_url);
                if (c.organization) |org| self.allocator.free(org);
            },
            .Anthropic => |*c| {
                self.allocator.free(c.api_key);
                self.allocator.free(c.anthropic_version);
            },
            .GoogleVertex => |*c| {
                self.allocator.free(c.api_key);
                self.allocator.free(c.project_id);
                self.allocator.free(c.location);
            },
            .AmazonBedrock => |*c| {
                self.allocator.free(c.access_key_id);
                self.allocator.free(c.secret_access_key);
                self.allocator.free(c.region);
            },
        }
    }

    pub fn updateConfig(self: *ConfigManager, new_config: ProviderConfig) !void {
        // Free the old config
        self.deinit();

        // Set the new config
        self.current_config = switch (new_config) {
            .OpenAI => |c| .{
                .OpenAI = .{
                    .api_key = try self.allocator.dupe(u8, c.api_key),
                    .base_url = try self.allocator.dupe(u8, c.base_url),
                    .organization = if (c.organization) |org| try self.allocator.dupe(u8, org) else null,
                },
            },
            .Anthropic => |c| .{
                .Anthropic = .{
                    .api_key = try self.allocator.dupe(u8, c.api_key),
                    .anthropic_version = try self.allocator.dupe(u8, c.anthropic_version),
                },
            },
            .GoogleVertex => |c| .{
                .GoogleVertex = .{
                    .api_key = try self.allocator.dupe(u8, c.api_key),
                    .project_id = try self.allocator.dupe(u8, c.project_id),
                    .location = try self.allocator.dupe(u8, c.location),
                },
            },
            .AmazonBedrock => |c| .{
                .AmazonBedrock = .{
                    .access_key_id = try self.allocator.dupe(u8, c.access_key_id),
                    .secret_access_key = try self.allocator.dupe(u8, c.secret_access_key),
                    .region = try self.allocator.dupe(u8, c.region),
                },
            },
        };
    }

    pub fn getConfig(self: *const ConfigManager) ProviderConfig {
        return self.current_config;
    }

    pub fn getProviderType(self: *const ConfigManager) core.ProviderType {
        return switch (self.current_config) {
            .OpenAI => .OpenAI,
            .Anthropic => .Anthropic,
            .GoogleVertex => .GoogleVertex,
            .AmazonBedrock => .AmazonBedrock,
        };
    }

    pub fn getApiKey(self: *const ConfigManager) ?[]const u8 {
        return switch (self.current_config) {
            .OpenAI => |c| c.api_key,
            .Anthropic => |c| c.api_key,
            .GoogleVertex => |c| c.api_key,
            .AmazonBedrock => null, // AmazonBedrock uses different authentication
        };
    }

    pub fn getBaseUrl(self: *const ConfigManager) ?[]const u8 {
        return switch (self.current_config) {
            .OpenAI => |c| c.base_url,
            else => null, // Other providers might not use a base URL
        };
    }

    pub fn getOrganization(self: *const ConfigManager) ?[]const u8 {
        return switch (self.current_config) {
            .OpenAI => |c| c.organization,
            else => null, // Other providers don't use an organization field
        };
    }

    pub fn getAnthropicVersion(self: *const ConfigManager) ?[]const u8 {
        return switch (self.current_config) {
            .Anthropic => |c| c.anthropic_version,
            else => null,
        };
    }

    pub fn getGoogleVertexDetails(self: *const ConfigManager) ?struct { project_id: []const u8, location: []const u8 } {
        return switch (self.current_config) {
            .GoogleVertex => |c| .{ .project_id = c.project_id, .location = c.location },
            else => null,
        };
    }

    pub fn getAmazonBedrockDetails(self: *const ConfigManager) ?struct { access_key_id: []const u8, secret_access_key: []const u8, region: []const u8 } {
        return switch (self.current_config) {
            .AmazonBedrock => |c| .{
                .access_key_id = c.access_key_id,
                .secret_access_key = c.secret_access_key,
                .region = c.region,
            },
            else => null,
        };
    }
};
