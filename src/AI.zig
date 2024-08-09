const std = @import("std");
const Providers = @import("providers.zig");
const Provider = Providers.Provider;
const Message = @import("shared.zig").Message;
const CompletionPayload = @import("shared.zig").CompletionPayload;
const StreamHandler = @import("shared.zig").StreamHandler;
const Embeddings = @import("Embeddings.zig");

pub const AI = @This();

provider: Provider,
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
    InvalidUri,
    ConnectionError,
    TlsError,
    RequestError,
    SendError,
    WriteError,
    FinishError,
    WaitError,
} || std.mem.Allocator.Error || std.json.ParseFromValueError;

pub fn init(self: *AI, gpa: std.mem.Allocator, provider: Provider) !void {
    self.* = .{
        .provider = provider,
        .gpa = gpa,
        .base_url = Providers.getProviderInfo(provider).base_url,
        .extra_headers = std.ArrayList(std.http.Header).init(gpa),
        .authorization_header_value = undefined,
    };

    try self.setAuthorizationHeader();
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
    const uri = std.Uri.parse(uri_string) catch |err| {
        std.debug.print("Error parsing URI: {}\n", .{err});
        return AIError.InvalidUri;
    };

    const body = try std.json.stringifyAlloc(self.gpa, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    });
    defer self.gpa.free(body);

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
        .authorization = .{ .override = self.authorization_header_value },
    };

    var req = client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = headers,
        .extra_headers = self.extra_headers.items,
    }) catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer,
            error.ConnectionRefused,
            error.NetworkUnreachable,
            error.ConnectionTimedOut,
            error.TemporaryNameServerFailure,
            error.NameServerFailure,
            error.UnknownHostName,
            error.HostLacksNetworkAddresses,
            error.UnexpectedConnectFailure,
            => AIError.ConnectionError,
            error.TlsInitializationFailed => AIError.TlsError,
            error.UnsupportedUriScheme,
            error.UnexpectedWriteFailure,
            error.InvalidContentLength,
            error.UnsupportedTransferEncoding,
            error.UriMissingHost,
            error.CertificateBundleLoadFailure,
            => AIError.RequestError,
            else => AIError.HttpRequestFailed,
        };
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;

    req.send() catch |err| {
        std.debug.print("Send error: {}\n", .{err});
        return AIError.SendError;
    };
    req.writer().writeAll(body) catch |err| {
        std.debug.print("Write error: {}\n", .{err});
        return AIError.WriteError;
    };
    req.finish() catch |err| {
        std.debug.print("Finish error: {}\n", .{err});
        return AIError.FinishError;
    };
    req.wait() catch |err| {
        std.debug.print("Wait error: {}\n", .{err});
        return AIError.WaitError;
    };

    const status = req.response.status;
    if (status != .ok) {
        const error_response = req.reader().readAllAlloc(self.gpa, 3276800) catch |err| {
            std.debug.print("Error reading response: {}\n", .{err});
            return AIError.HttpRequestFailed;
        };
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
    const uri = std.Uri.parse(uri_string) catch |err| {
        std.debug.print("Error parsing URI: {}\n", .{err});
        return AIError.InvalidUri;
    };

    const body = try std.json.stringifyAlloc(self.gpa, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    });
    defer self.gpa.free(body);

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
        .authorization = .{ .override = self.authorization_header_value },
    };

    var req = client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = headers,
        .extra_headers = self.extra_headers.items,
    }) catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer,
            error.ConnectionRefused,
            error.NetworkUnreachable,
            error.ConnectionTimedOut,
            error.TemporaryNameServerFailure,
            error.NameServerFailure,
            error.UnknownHostName,
            error.HostLacksNetworkAddresses,
            error.UnexpectedConnectFailure,
            => AIError.ConnectionError,
            error.TlsInitializationFailed => AIError.TlsError,
            error.UnsupportedUriScheme,
            error.UnexpectedWriteFailure,
            error.InvalidContentLength,
            error.UnsupportedTransferEncoding,
            error.UriMissingHost,
            error.CertificateBundleLoadFailure,
            => AIError.RequestError,
            else => AIError.HttpRequestFailed,
        };
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;

    req.send() catch |err| {
        std.debug.print("Send error: {}\n", .{err});
        return AIError.SendError;
    };
    req.writer().writeAll(body) catch |err| {
        std.debug.print("Write error: {}\n", .{err});
        return AIError.WriteError;
    };
    req.finish() catch |err| {
        std.debug.print("Finish error: {}\n", .{err});
        return AIError.FinishError;
    };
    req.wait() catch |err| {
        std.debug.print("Wait error: {}\n", .{err});
        return AIError.WaitError;
    };

    const status = req.response.status;
    if (status != .ok) {
        const error_response = req.reader().readAllAlloc(self.gpa, 3276800) catch |err| {
            std.debug.print("Error reading response: {}\n", .{err});
            return AIError.HttpRequestFailed;
        };
        defer self.gpa.free(error_response);

        std.debug.print("Error response: {s}\n", .{error_response});
        return AIError.ApiError;
    }

    var content_received = false;
    while (true) {
        const chunk = req.reader().readUntilDelimiterOrEofAlloc(self.gpa, '\n', 1638400) catch |err| {
            return switch (err) {
                error.ConnectionResetByPeer, error.ConnectionTimedOut => AIError.ConnectionError,
                error.TlsFailure, error.TlsAlert => AIError.TlsError,
                error.UnexpectedReadFailure => AIError.HttpRequestFailed,
                error.EndOfStream => break, // End of stream, exit the loop
                error.OutOfMemory => return error.OutOfMemory,
                error.StreamTooLong => AIError.InvalidResponse,
                else => AIError.HttpRequestFailed,
            };
        } orelse break;
        defer self.gpa.free(chunk);

        if (std.mem.eql(u8, chunk, "data: [DONE]")) {
            break;
        }

        if (!std.mem.startsWith(u8, chunk, "data: ")) continue;

        _ = writer.write(chunk[6..]) catch |err| {
            std.debug.print("Write error: {}\n", .{err});
            return AIError.WriteError;
        };
        content_received = true;
    }

    if (!content_received) {
        return AIError.InvalidResponse;
    }
}

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

fn setAuthorizationHeader(self: *AI) !void {
    const env_var = Providers.getProviderInfo(self.provider).api_key_env_var;
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
