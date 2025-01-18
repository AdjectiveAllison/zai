const std = @import("std");
const zai = @import("zai");
const config_path = @import("config_path.zig");

pub fn ensureConfigExists(allocator: std.mem.Allocator) !void {
    try config_path.ensureConfigDirExists();

    const config_file = try config_path.getConfigPath(allocator);
    defer allocator.free(config_file);

    // Check if config file exists
    std.fs.accessAbsolute(config_file, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            // Create default config
            const default_config =
                \\{
                \\    "providers": []
                \\}
            ;
            const file = try std.fs.createFileAbsolute(config_file, .{});
            defer file.close();
            try file.writeAll(default_config);
        },
        else => return err,
    };
}

pub fn validateModel(provider_name: []const u8, model_name: ?[]const u8, registry: *zai.Registry) !void {
    if (model_name == null) return;

    const provider_info = registry.getProvider(provider_name) orelse return error.ProviderNotFound;
    const model = model_name.?;

    // Check if model is in the provider's supported models
    for (provider_info.models) |supported_model| {
        if (std.mem.eql(u8, model, supported_model.name)) {
            return;
        }
    }

    return error.InvalidModel;
}

pub fn getDefaultProvider(allocator: std.mem.Allocator) !*zai.Provider {
    const config_file = try config_path.getConfigPath(allocator);
    defer allocator.free(config_file);

    var registry = try zai.Registry.loadFromFile(allocator, config_file);
    defer registry.deinit();

    if (registry.providers.items.len == 0) {
        return error.NoProvidersConfigured;
    }

    const first_provider = registry.providers.items[0];
    try registry.initProvider(first_provider.name);
    return first_provider.instance.?;
}

pub fn getProviderByName(allocator: std.mem.Allocator, name: []const u8) !*zai.Provider {
    const config_file = try config_path.getConfigPath(allocator);
    defer allocator.free(config_file);

    var registry = try zai.Registry.loadFromFile(allocator, config_file);
    defer registry.deinit();

    const provider_info = registry.getProvider(name) orelse return error.ProviderNotFound;
    try registry.initProvider(name);
    return provider_info.instance.?;
}
