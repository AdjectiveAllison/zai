const std = @import("std");

const Self = @This();

vectors: std.ArrayList(Vector),
allocator: std.mem.Allocator,

pub const Vector = struct {
    id: []const u8,
    embedding: []f32,
    metadata: ?std.StringHashMap([]const u8),

    pub fn deinit(self: *Vector, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.embedding);
        if (self.metadata) |*metadata| {
            var it = metadata.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            metadata.deinit();
        }
    }
};

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .vectors = std.ArrayList(Vector).init(allocator),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    for (self.vectors.items) |*vector| {
        vector.deinit(self.allocator);
    }
    self.vectors.deinit();
}

pub fn addVector(self: *Self, id: []const u8, embedding: []const f32, metadata: ?std.StringHashMap([]const u8)) !void {
    const new_id = try self.allocator.dupe(u8, id);
    errdefer self.allocator.free(new_id);

    const new_embedding = try self.allocator.dupe(f32, embedding);
    errdefer self.allocator.free(new_embedding);

    var new_metadata: ?std.StringHashMap([]const u8) = null;
    if (metadata) |m| {
        new_metadata = std.StringHashMap([]const u8).init(self.allocator);
        errdefer {
            if (new_metadata) |*nm| {
                var it = nm.iterator();
                while (it.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    self.allocator.free(entry.value_ptr.*);
                }
                nm.deinit();
            }
        }
        var it = m.iterator();
        while (it.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            errdefer self.allocator.free(key);
            const value = try self.allocator.dupe(u8, entry.value_ptr.*);
            errdefer self.allocator.free(value);
            try new_metadata.?.put(key, value);
        }
    }

    try self.vectors.append(.{
        .id = new_id,
        .embedding = new_embedding,
        .metadata = new_metadata,
    });
}

pub fn findSimilar(self: *Self, query: []const f32, k: usize) ![]Vector {
    var distances = try self.allocator.alloc(f32, self.vectors.items.len);
    defer self.allocator.free(distances);

    for (self.vectors.items, 0..) |vector, i| {
        distances[i] = cosineSimilarity(query, vector.embedding);
    }

    const Context = struct {
        distances: []const f32,
        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return ctx.distances[a] > ctx.distances[b];
        }
    };

    const indices = try self.allocator.alloc(usize, self.vectors.items.len);
    defer self.allocator.free(indices);
    for (indices, 0..) |*index, i| {
        index.* = i;
    }

    std.mem.sort(usize, indices, Context{ .distances = distances }, Context.lessThan);

    const result = try self.allocator.alloc(Vector, @min(k, self.vectors.items.len));
    for (result, 0..) |*res, i| {
        std.debug.print("{s} had {d} distance\n", .{ self.vectors.items[indices[i]].metadata.?.get("text").?, distances[i] });
        res.* = self.vectors.items[indices[i]];
    }

    return result;
}

fn cosineSimilarity(a: []const f32, b: []const f32) f32 {
    var dot_product: f32 = 0;
    var magnitude_a: f32 = 0;
    var magnitude_b: f32 = 0;

    for (a, 0..) |_, i| {
        dot_product += a[i] * b[i];
        magnitude_a += a[i] * a[i];
        magnitude_b += b[i] * b[i];
    }

    magnitude_a = @sqrt(magnitude_a);
    magnitude_b = @sqrt(magnitude_b);

    return dot_product / (magnitude_a * magnitude_b);
}
