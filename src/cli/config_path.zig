const std = @import("std");

pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        var path = std.ArrayList(u8).init(allocator);
        errdefer path.deinit();
        try path.appendSlice(home);
        try path.appendSlice("/.config/zai");
        return path.toOwnedSlice();
    } else |_| {
        return error.HomeNotFound;
    }
}

pub fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);
    var path = std.ArrayList(u8).init(allocator);
    errdefer path.deinit();
    try path.appendSlice(config_dir);
    try path.appendSlice("/config.json");
    return path.toOwnedSlice();
}

pub fn ensureConfigDirExists() !void {
    const config_dir = try getConfigDir(std.heap.page_allocator);
    defer std.heap.page_allocator.free(config_dir);
    try std.fs.makeDirAbsolute(config_dir);
}
