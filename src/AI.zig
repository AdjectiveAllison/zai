const std = @import("std");
const Provider = @import("shared.zig").Provider;
const Message = @import("shared.zig").Message;
const CompletionPayload = @import("shared.zig").CompletionPayload;
const StreamHandler = @import("shared.zig").StreamHandler;
const Embeddings = @import("Embeddings.zig");

pub const AI = @This();

base_url: []const u8,
authorization_header_value: []const u8,
organization: ?[]const u8 = null,
gpa: std.mem.Allocator,
extra_headers: std.ArrayList(std.http.Header),

pub const AIError = error{
    HttpRequestFailed,
    InvalidResponse,
    UnexpectedStatus,
    ApiError,
} || std.mem.Allocator.Error || std.json.ParseFromSliceError;

pub fn init(self: *AI, gpa: std.mem.Allocator, provider: Provider) !void {
    self.* = .{
        .gpa = gpa,
        .base_url = provider.getBaseUrl(),
        .extra_headers = std.ArrayList(std.http.Header).init(gpa),
        .authorization_header_value = undefined,
    };

    try self.setAuthorizationHeader(provider);
    try self.setExtraHeaders();
}

pub fn deinit(self: *AI) void {
    self.gpa.free(self.authorization_header_value);
    self.extra_headers.deinit();
}

pub fn chatCompletionParsed(
    self: *AI,
    payload: CompletionPayload,
) AIError!std.json.Parsed(ChatCompletionResponse) {
    const response = try self.chatCompletionRaw(payload);
    defer self.gpa.free(response);

    return std.json.parseFromSlice(
        ChatCompletionResponse,
        self.gpa,
        response,
        .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        },
    ) catch |err| {
        std.debug.print("Error parsing JSON: {}\n", .{err});
        return AIError.InvalidResponse;
    };
}

pub fn chatCompletionLeaky(
    self: *AI,
    arena: std.mem.Allocator,
    payload: CompletionPayload,
) AIError!ChatCompletionResponse {
    const response = try self.chatCompletionRaw(payload);
    defer self.gpa.free(response);

    return std.json.parseFromSliceLeaky(
        ChatCompletionResponse,
        arena,
        response,
        .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        },
    ) catch |err| {
        std.debug.print("Error parsing JSON: {}\n", .{err});
        return AIError.InvalidResponse;
    };
}

pub fn chatCompletionRaw(
    self: *AI,
    payload: CompletionPayload,
) AIError![]const u8 {
    var client = std.http.Client{
        .allocator = self.gpa,
    };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = try std.fmt.allocPrint(self.gpa, "{s}/chat/completions", .{self.base_url});
    defer self.gpa.free(uri_string);
    const uri = try std.Uri.parse(uri_string);

    const body = try std.json.stringifyAlloc(self.gpa, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    });
    defer self.gpa.free(body);

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
        .authorization = .{ .override = self.authorization_header_value },
    };

    var req = try client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = headers,
        .extra_headers = self.extra_headers.items,
    });
    defer req.deinit();

    req.transfer_encoding = .chunked;

    try req.send();
    try req.writer().writeAll(body);
    try req.finish();
    try req.wait();

    const status = req.response.status;
    if (status != .ok) {
        const error_response = try req.reader().readAllAlloc(self.gpa, 3276800);
        defer self.gpa.free(error_response);

        std.debug.print("Error response: {s}\n", .{error_response});
        return AIError.ApiError;
    }

    return req.reader().readAllAlloc(self.gpa, 3276800) catch {
        return AIError.HttpRequestFailed;
    };
}

pub fn chatCompletionStreamRaw(
    self: *AI,
    payload: CompletionPayload,
    writer: anytype,
) AIError!void {
    var client = std.http.Client{ .allocator = self.gpa };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = try std.fmt.allocPrint(self.gpa, "{s}/chat/completions", .{self.base_url});
    defer self.gpa.free(uri_string);
    const uri = try std.Uri.parse(uri_string);

    const body = try std.json.stringifyAlloc(self.gpa, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    });
    defer self.gpa.free(body);

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
        .authorization = .{ .override = self.authorization_header_value },
    };

    var req = try client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = headers,
        .extra_headers = self.extra_headers.items,
    });
    defer req.deinit();

    req.transfer_encoding = .chunked;

    try req.send();
    try req.writer().writeAll(body);
    try req.finish();
    try req.wait();

    const status = req.response.status;
    if (status != .ok) {
        const error_response = try req.reader().readAllAlloc(self.gpa, 3276800);
        defer self.gpa.free(error_response);

        std.debug.print("Error response: {s}\n", .{error_response});
        return AIError.ApiError;
    }

    var content_received = false;
    while (true) {
        const chunk = try req.reader().readUntilDelimiterOrEofAlloc(self.gpa, '\n', 1638400) orelse break;
        defer self.gpa.free(chunk);

        if (std.mem.eql(u8, chunk, "data: [DONE]")) {
            break;
        }

        if (!std.mem.startsWith(u8, chunk, "data: ")) continue;

        const write_result = try writer.write(chunk[6..]);
        if (write_result > 0) {
            content_received = true;
        }
    }

    if (!content_received) {
        return AIError.InvalidResponse;
    }
}

// ... (rest of the code remains the same)

pub fn embeddingsRaw(
    self: *AI,
    payload: Embeddings.EmbeddingsPayload,
) ![]const u8 {
    var client = std.http.Client{
        .allocator = self.gpa,
    };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = try std.fmt.allocPrint(self.gpa, "{s}/embeddings", .{self.base_url});
    defer self.gpa.free(uri_string);
    const uri = try std.Uri.parse(uri_string);

    const body = try std.json.stringifyAlloc(self.gpa, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    });
    defer self.gpa.free(body);

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
        .authorization = .{ .override = self.authorization_header_value },
    };

    var req = try client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = headers,
        .extra_headers = self.extra_headers.items,
    });
    defer req.deinit();

    req.transfer_encoding = .chunked;

    try req.send();
    try req.writer().writeAll(body);
    try req.finish();
    try req.wait();

    const status = req.response.status;
    if (status != .ok) {
        std.debug.print("STATUS NOT OKAY\n{s}\nWE GOT AN ERROR\n", .{status.phrase().?});
        return error.HttpRequestFailed;
    }

    return try req.reader().readAllAlloc(self.gpa, 3276800);
}

pub fn embeddingsParsed(
    self: *AI,
    payload: Embeddings.EmbeddingsPayload,
) !std.json.Parsed(EmbeddingsResponse) {
    const response = try self.embeddingsRaw(payload);
    defer self.gpa.free(response);

    return try std.json.parseFromSlice(EmbeddingsResponse, self.gpa, response, .{ .allocate = .alloc_always });
}

pub fn embeddingsLeaky(
    self: *AI,
    arena: std.mem.Allocator,
    payload: Embeddings.EmbeddingsPayload,
) !EmbeddingsResponse {
    const response = try self.embeddingsRaw(payload);
    defer self.gpa.free(response);

    return try std.json.parseFromSliceLeaky(EmbeddingsResponse, arena, response, .{ .allocate = .alloc_always });
}

fn setAuthorizationHeader(self: *AI, provider: Provider) !void {
    const env_var = provider.getKeyVar();
    const api_key = try std.process.getEnvVarOwned(self.gpa, env_var);
    defer self.gpa.free(api_key);

    self.authorization_header_value = try std.fmt.allocPrint(self.gpa, "Bearer {s}", .{api_key});
}

fn setExtraHeaders(self: *AI) !void {
    try self.extra_headers.append(.{ .name = "User-Agent", .value = "zai/0.1.0" });
    try self.extra_headers.append(.{ .name = "Accept", .value = "*/*" });
}

// TODO: Do something with role later on potentially.
const Role = union(enum) {
    system: "system",
    assistant: "assistant",
    user: "user",
};

const Usage = struct {
    prompt_tokens: u64,
    completion_tokens: ?u64,
    total_tokens: u64,
};

const Choice = struct { index: usize, finish_reason: ?[]const u8, message: Message };

// TODO: If I return direct response without explicitly passing in an arena then go ahead and create a deinit method inside of this that cleans it all up.
const ChatCompletionResponse = struct {
    id: []const u8,
    object: []const u8,
    created: u64,
    model: []const u8,
    choices: []Choice,
    // Usage is not returned by the Completion endpoint when streamed.
    usage: ?Usage = null,
};

const EmbeddingsResponse = struct {
    object: []const u8,
    data: []struct {
        index: u32,
        object: []const u8,
        embedding: []f32,
    },
    model: []const u8,
    usage: Embeddings.Usage,
    id: []const u8,
    created: u64,
};
