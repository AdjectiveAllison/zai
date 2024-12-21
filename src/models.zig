const std = @import("std");

pub const ModelType = enum { chat, completion, embedding };

pub const ModelInfo = union(ModelType) {
    chat: struct {
        display_name: []const u8,
        name: []const u8,
        max_tokens: u32,
        // Add other chat model specific fields
    },
    completion: struct {
        display_name: []const u8,
        name: []const u8,
        max_tokens: u32,
        // Add other completion model specific fields
    },
    embedding: struct {
        display_name: []const u8,
        name: []const u8,
        dimensions: u32,
        // Add other embedding model specific fields
    },
};

//TODO: Delete this file, we aren't using it currently
pub const ModelRegistry = struct {
    allocator: std.mem.Allocator,
    models: std.StringHashMap(ModelInfo),

    pub fn init(allocator: std.mem.Allocator) ModelRegistry {
        return .{
            .allocator = allocator,
            .models = std.StringHashMap(ModelInfo).init(allocator),
        };
    }

    pub fn deinit(self: *ModelRegistry) void {
        var it = self.models.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            switch (entry.value_ptr.*) {
                .chat => |*c| {
                    self.allocator.free(c.display_name);
                    self.allocator.free(c.name);
                },
                .completion => |*c| {
                    self.allocator.free(c.display_name);
                    self.allocator.free(c.name);
                },
                .embedding => |*e| {
                    self.allocator.free(e.display_name);
                    self.allocator.free(e.name);
                },
            }
        }
        self.models.deinit();
    }

    pub fn addModel(self: *ModelRegistry, name: []const u8, info: ModelInfo) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        try self.models.put(owned_name, info);
    }

    pub fn getModel(self: *const ModelRegistry, name: []const u8) ?ModelInfo {
        return self.models.get(name);
    }

    pub fn removeModel(self: *ModelRegistry, name: []const u8) void {
        if (self.models.fetchRemove(name)) |entry| {
            self.allocator.free(entry.key);
            switch (entry.value) {
                .chat => |c| {
                    self.allocator.free(c.display_name);
                    self.allocator.free(c.name);
                },
                .completion => |c| {
                    self.allocator.free(c.display_name);
                    self.allocator.free(c.name);
                },
                .embedding => |e| {
                    self.allocator.free(e.display_name);
                    self.allocator.free(e.name);
                },
            }
        }
    }
};
