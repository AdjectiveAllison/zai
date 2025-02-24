const std = @import("std");
const providers = @import("../providers.zig");
const Provider = providers.Provider;
const AnthropicConfig = @import("../config.zig").AnthropicConfig;
const core = @import("../core.zig");
const requests = @import("../requests.zig");
const ChatRequestOptions = requests.ChatRequestOptions;
const CompletionRequestOptions = requests.CompletionRequestOptions;
const EmbeddingRequestOptions = requests.EmbeddingRequestOptions;
const Message = core.Message;

allocator: std.mem.Allocator,
config: AnthropicConfig,
authorization_header: []const u8,
extra_headers: std.ArrayList(std.http.Header),

// Current Anthropic API version - hardcoded to avoid requiring it in the config
const ANTHROPIC_API_VERSION = "2023-06-01";

const Self = @This();

// Anthropic message formats
const AnthropicMessage = struct {
    role: []const u8,
    content: []const u8,
};

const AnthropicPayload = struct {
    model: []const u8,
    messages: []const AnthropicMessage,
    system: ?[]const u8 = null,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    stop_sequences: ?[]const []const u8 = null,
    stream: bool = false,
};

pub fn init(allocator: std.mem.Allocator, config: AnthropicConfig) !Provider {
    var self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.allocator = allocator;
    self.config = config;
    self.extra_headers = std.ArrayList(std.http.Header).init(allocator);

    try self.setAuthorizationHeader();
    try self.setExtraHeaders();

    return .{
        .ptr = self,
        .vtable = &.{
            .deinit = deinit,
            .completion = completion,
            .completionStream = completionStream,
            .chat = chat,
            .chatStream = chatStream,
            .createEmbedding = createEmbedding,
        },
    };
}

fn setAuthorizationHeader(self: *Self) !void {
    self.authorization_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.config.api_key});
}


fn setExtraHeaders(self: *Self) !void {
    try self.extra_headers.append(.{ .name = "User-Agent", .value = "zai/0.1.0" });
}

fn deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.allocator.free(self.authorization_header);
    self.extra_headers.deinit();
    self.allocator.destroy(self);
}

fn chat(ctx: *anyopaque, options: ChatRequestOptions) Provider.Error![]const u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));
    
    // If max_tokens isn't provided, use the default from the config
    const actual_max_tokens = options.max_tokens orelse self.config.default_max_tokens;

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = "https://api.anthropic.com/v1/messages";
    const uri = std.Uri.parse(uri_string) catch {
        return Provider.Error.InvalidRequest;
    };

    // Convert common messages to Anthropic format
    var anthropic_messages = std.ArrayList(AnthropicMessage).init(self.allocator);
    defer anthropic_messages.deinit();

    var system_content: ?[]const u8 = null;

    for (options.messages) |message| {
        if (std.mem.eql(u8, message.role, "system")) {
            system_content = message.content;
            continue;
        }

        // Map roles (Anthropic only supports user and assistant roles)
        var role = message.role;
        if (!std.mem.eql(u8, role, "user") and !std.mem.eql(u8, role, "assistant")) {
            role = "user"; // Default to user for any other roles
        }

        const anthropic_message = AnthropicMessage{
            .role = role,
            .content = message.content,
        };
        try anthropic_messages.append(anthropic_message);
    }

    const anthropic_messages_final = try anthropic_messages.toOwnedSlice();
    defer self.allocator.free(anthropic_messages_final);

    // Prepare the request payload
    var payload: AnthropicPayload = .{
        .model = options.model,
        .messages = anthropic_messages_final,
        .max_tokens = actual_max_tokens,
        .temperature = options.temperature,
        .top_p = options.top_p,
        .stop_sequences = options.stop,
        .stream = false,
    };

    if (system_content) |content| {
        payload.system = content;
    }

    const body = std.json.stringifyAlloc(self.allocator, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(body);

    var headers = std.ArrayList(std.http.Header).init(self.allocator);
    defer headers.deinit();

    try headers.append(.{ .name = "Content-Type", .value = "application/json" });
    try headers.append(.{ .name = "X-Api-Key", .value = self.config.api_key });
    try headers.append(.{ .name = "Anthropic-Version", .value = ANTHROPIC_API_VERSION });
    try headers.appendSlice(self.extra_headers.items);

    var req = client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = .{},
        .extra_headers = headers.items,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            error.ConnectionRefused, error.NetworkUnreachable, error.ConnectionTimedOut => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;

    req.send() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.writer().writeAll(body) catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.finish() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.wait() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };

    const status = req.response.status;
    if (status != .ok) {
        const error_response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
            return switch (err) {
                error.OutOfMemory => Provider.Error.OutOfMemory,
                else => Provider.Error.UnexpectedError,
            };
        };
        defer self.allocator.free(error_response);
        std.debug.print("Error response: {s}\n", .{error_response});
        return Provider.Error.ApiError;
    }

    const response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer self.allocator.free(response);

    // Parse the response
    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            else => Provider.Error.ParseError,
        };
    };
    defer parsed.deinit();

    // Extract the content from the response
    const content = parsed.value.object.get("content") orelse return Provider.Error.ApiError;
    if (content.array.items.len == 0) return Provider.Error.ApiError;

    const text = content.array.items[0].object.get("text").?.string;
    return self.allocator.dupe(u8, text) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
}

fn chatStream(ctx: *anyopaque, options: ChatRequestOptions, writer: std.io.AnyWriter) Provider.Error!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    
    // If max_tokens isn't provided, use the default from the config
    const actual_max_tokens = options.max_tokens orelse self.config.default_max_tokens;

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = "https://api.anthropic.com/v1/messages";
    const uri = std.Uri.parse(uri_string) catch {
        return Provider.Error.InvalidRequest;
    };

    // Convert common messages to Anthropic format
    var anthropic_messages = std.ArrayList(AnthropicMessage).init(self.allocator);
    defer anthropic_messages.deinit();

    var system_content: ?[]const u8 = null;

    for (options.messages) |message| {
        if (std.mem.eql(u8, message.role, "system")) {
            system_content = message.content;
            continue;
        }

        // Map roles (Anthropic only supports user and assistant roles)
        var role = message.role;
        if (!std.mem.eql(u8, role, "user") and !std.mem.eql(u8, role, "assistant")) {
            role = "user"; // Default to user for any other roles
        }

        const anthropic_message = AnthropicMessage{
            .role = role,
            .content = message.content,
        };
        try anthropic_messages.append(anthropic_message);
    }

    const anthropic_messages_final = try anthropic_messages.toOwnedSlice();
    defer self.allocator.free(anthropic_messages_final);

    // Prepare the request payload
    var payload: AnthropicPayload = .{
        .model = options.model,
        .messages = anthropic_messages_final,
        .max_tokens = actual_max_tokens,
        .temperature = options.temperature,
        .top_p = options.top_p,
        .stop_sequences = options.stop,
        .stream = true, // Enable streaming
    };

    if (system_content) |content| {
        payload.system = content;
    }

    const body = std.json.stringifyAlloc(self.allocator, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(body);

    var headers = std.ArrayList(std.http.Header).init(self.allocator);
    defer headers.deinit();

    try headers.append(.{ .name = "Content-Type", .value = "application/json" });
    try headers.append(.{ .name = "X-Api-Key", .value = self.config.api_key });
    try headers.append(.{ .name = "Anthropic-Version", .value = ANTHROPIC_API_VERSION });
    try headers.appendSlice(self.extra_headers.items);

    var req = client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = .{},
        .extra_headers = headers.items,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            error.ConnectionRefused, error.NetworkUnreachable, error.ConnectionTimedOut => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;

    req.send() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.writer().writeAll(body) catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.finish() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.wait() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };

    const status = req.response.status;
    if (status != .ok) {
        const error_response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
            return switch (err) {
                error.OutOfMemory => Provider.Error.OutOfMemory,
                else => Provider.Error.UnexpectedError,
            };
        };
        defer self.allocator.free(error_response);
        std.debug.print("Error response: {s}\n", .{error_response});
        return Provider.Error.ApiError;
    }

    var scanner = std.json.Scanner.initStreaming(self.allocator);
    defer scanner.deinit();

    var buffer: [4096]u8 = undefined;
    var stream_buffer = std.ArrayList(u8).init(self.allocator);
    defer stream_buffer.deinit();

    while (true) {
        const bytes_read = req.reader().read(&buffer) catch |err| {
            return switch (err) {
                error.ConnectionTimedOut, error.ConnectionResetByPeer => Provider.Error.NetworkError,
                error.TlsFailure, error.TlsAlert => Provider.Error.NetworkError,
                error.UnexpectedReadFailure => Provider.Error.UnexpectedError,
                error.EndOfStream => break, // End of stream, exit the loop
                error.HttpChunkInvalid, error.HttpHeadersOversize, error.DecompressionFailure, error.InvalidTrailers => Provider.Error.ApiError,
            };
        };
        if (bytes_read == 0) break; // End of stream

        try stream_buffer.appendSlice(buffer[0..bytes_read]);

        while (true) {
            const newline_index = std.mem.indexOfScalar(u8, stream_buffer.items, '\n') orelse break;
            const line = stream_buffer.items[0..newline_index];

            if (line.len > 0 and !std.mem.startsWith(u8, line, "event: ") and !std.mem.startsWith(u8, line, "data: ")) {
                // Skip non-event and non-data lines
                stream_buffer.replaceRange(0, newline_index + 1, &[_]u8{}) catch |err| {
                    return switch (err) {
                        error.OutOfMemory => Provider.Error.OutOfMemory,
                    };
                };
                continue;
            }

            if (std.mem.startsWith(u8, line, "event: content_block_delta") and 
                stream_buffer.items.len > newline_index + 1) {
                // Check for data line after event line
                const data_start = newline_index + 1;
                const data_newline = std.mem.indexOfScalarPos(u8, stream_buffer.items, data_start, '\n') orelse break;
                const data_line = stream_buffer.items[data_start..data_newline];

                if (std.mem.startsWith(u8, data_line, "data: ")) {
                    const json_data = data_line["data: ".len..];
                    
                    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{}) catch |err| {
                        stream_buffer.replaceRange(0, data_newline + 1, &[_]u8{}) catch |replace_err| {
                            return switch (replace_err) {
                                error.OutOfMemory => Provider.Error.OutOfMemory,
                            };
                        };
                        if (err == error.InvalidCharacter) {
                            // Skip invalid JSON and continue
                            continue;
                        }
                        return Provider.Error.ParseError;
                    };
                    defer parsed.deinit();

                    if (parsed.value.object.get("delta")) |delta| {
                        if (delta.object.get("text")) |text| {
                            writer.writeAll(text.string) catch |err| {
                                return switch (err) {
                                    error.OutOfMemory => Provider.Error.OutOfMemory,
                                    else => Provider.Error.UnexpectedError,
                                };
                            };
                        }
                    }

                    // Remove both event and data lines
                    stream_buffer.replaceRange(0, data_newline + 1, &[_]u8{}) catch |err| {
                        return switch (err) {
                            error.OutOfMemory => Provider.Error.OutOfMemory,
                        };
                    };
                    continue;
                }
            }

            if (std.mem.startsWith(u8, line, "event: message_stop")) {
                return; // End of stream
            }

            // Remove current line if we didn't process it
            stream_buffer.replaceRange(0, newline_index + 1, &[_]u8{}) catch |err| {
                return switch (err) {
                    error.OutOfMemory => Provider.Error.OutOfMemory,
                };
            };
        }
    }
}

fn completion(ctx: *anyopaque, options: CompletionRequestOptions) Provider.Error![]const u8 {
    _ = ctx;
    _ = options;
    @panic("Not implemented"); // Stub
}

fn completionStream(ctx: *anyopaque, options: CompletionRequestOptions, writer: std.io.AnyWriter) Provider.Error!void {
    _ = ctx;
    _ = options;
    _ = writer;
    @panic("Not implemented"); // Stub
}

fn createEmbedding(ctx: *anyopaque, options: EmbeddingRequestOptions) Provider.Error![]f32 {
    _ = ctx;
    _ = options;
    @panic("Not implemented"); // Stub
}