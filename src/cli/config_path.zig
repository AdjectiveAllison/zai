const std = @import("std");

pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg_config| {
        return try std.fmt.allocPrint(allocator, "{s}/zai", .{xdg_config});
    } else |_| {
        if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
            return try std.fmt.allocPrint(allocator, "{s}/.config/zai", .{home});
        } else |_| {
            return error.NoValidConfigPath;
        }
    }
}

pub fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);
    return try std.fmt.allocPrint(allocator, "{s}/config.json", .{config_dir});
}

pub fn ensureConfigDirExists() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const config_dir = try getConfigDir(allocator);
    try std.fs.makeDirAbsolute(config_dir);
}
