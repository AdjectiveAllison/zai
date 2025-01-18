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

pub fn validateModel(provider_name: []const u8, model: ?[]const u8, registry: *zai.Registry) !void {
    const model_name = model orelse return;

    if (registry.getModel(provider_name, model_name)) |_| {
        return;
    }

    std.debug.print("Invalid model '{s}' for provider '{s}'\n", .{ model_name, provider_name });
    return error.InvalidModel;
}

pub fn getDefaultProvider(allocator: std.mem.Allocator) !*zai.Provider {
    try ensureConfigExists(allocator);

    const config_file = try config_path.getConfigPath(allocator);
    defer allocator.free(config_file);

    var registry = try zai.Registry.loadFromFile(allocator, config_file);
    errdefer registry.deinit();

    if (registry.providers.items.len == 0) {
        std.debug.print("No providers configured. Please configure a provider first.\n", .{});
        return error.NoProviders;
    }

    const provider_spec = registry.providers.items[0];
    try registry.initProvider(provider_spec.name);
    return provider_spec.instance.?;
}

pub fn getProviderByName(allocator: std.mem.Allocator, name: []const u8) !*zai.Provider {
    try ensureConfigExists(allocator);

    const config_file = try config_path.getConfigPath(allocator);
    defer allocator.free(config_file);

    var registry = try zai.Registry.loadFromFile(allocator, config_file);
    errdefer registry.deinit();

    // Find provider with matching name
    for (registry.providers.items) |provider_spec| {
        if (std.mem.eql(u8, provider_spec.name, name)) {
            try registry.initProvider(name);
            return provider_spec.instance.?;
        }
    }

    std.debug.print("Provider not found: {s}\n", .{name});
    return error.ProviderNotFound;
}
