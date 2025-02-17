const std = @import("std");
const providers = @import("../providers.zig");
const Provider = providers.Provider;
const AmazonBedrockConfig = @import("../config.zig").AmazonBedrockConfig;
const core = @import("../core.zig");
const requests = @import("../requests.zig");
const ChatRequestOptions = requests.ChatRequestOptions;
const CompletionRequestOptions = requests.CompletionRequestOptions;
const EmbeddingRequestOptions = requests.EmbeddingRequestOptions;
const Message = core.Message;
const auth = @import("amazon/auth.zig");

allocator: std.mem.Allocator,
config: AmazonBedrockConfig,
extra_headers: std.ArrayList(std.http.Header),

const Self = @This();

const AmazonMessage = struct {
    role: []const u8,
    content: [1]AmazoneMessageContent,
};

const AmazoneMessageContent = struct { text: []const u8 };

const AmazonPayload = struct {
    messages: []const AmazonMessage,
    system: ?[]const SystemBlock = null,
    inferenceConfig: InferenceConfig,

    const InferenceConfig = struct {
        maxTokens: ?u32 = null,
        stopSequences: ?[]const []const u8 = null,
        temperature: ?f32 = null,
        topP: ?f32 = null,
    };
};

pub const EventStreamError = error{
    InsufficientData,
    MalformedMessage,
};

pub const EventStreamMessage = struct {
    total_length: u32,
    header_length: u32,
    // For now we only extract the payload; you could parse headers later if needed.
    payload: []const u8,
};

/// Parses an event-stream message out of a given byte slice.
///
/// The expected format is:
///   • First 4 bytes: total message length (big-endian)
///   • Next 4 bytes: header block length (big-endian)
///   • Next 4 bytes: prelude checksum (ignored)
///   • Headers (header block length bytes)
///   • Payload: the JSON‐encoded data (message payload)
///   • Trailing 4 bytes: message checksum (ignored)
pub fn parseEventStreamMessage(buffer: []u8) !EventStreamMessage {
    // We require at least 12 bytes (for total_length, header_length, and prelude checksum)
    if (buffer.len < 12) return EventStreamError.InsufficientData;
    const total_length = std.mem.readInt(u32, buffer[0..4], .big);
    const header_length = std.mem.readInt(u32, buffer[4..8], .big);
    if (buffer.len < total_length) return EventStreamError.InsufficientData;
    // Skip the 4-byte prelude checksum at offset 8..12.
    const header_start = 12;
    const header_end = header_start + header_length;
    // Ensure there's room for the payload as well as trailing 4-byte checksum.
    if (header_end > total_length - 4) return EventStreamError.MalformedMessage;
    const payload_start = header_end;
    const payload_end = total_length - 4; // leave off trailing checksum
    const payload = buffer[payload_start..payload_end];
    return EventStreamMessage{
        .total_length = total_length,
        .header_length = header_length,
        .payload = payload,
    };
}

const SystemBlock = struct {
    // guardContent can be added later if I want it, but I don't care right now.
    text: []const u8,
};

pub fn init(allocator: std.mem.Allocator, config: AmazonBedrockConfig) !Provider {
    var self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.allocator = allocator;
    self.config = config;
    self.extra_headers = std.ArrayList(std.http.Header).init(allocator);

    // try self.setAuthorizationHeader();
    // try self.setExtraHeaders();

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

fn deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    // self.allocator.free(self.authorization_header);
    self.extra_headers.deinit();
    self.allocator.destroy(self);
}

fn chat(ctx: *anyopaque, options: ChatRequestOptions) Provider.Error![]const u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    // Construct the request path with model ID
    const uri_path = try std.fmt.allocPrint(self.allocator, "/model/{s}/converse", .{options.model});
    defer self.allocator.free(uri_path);

    // Generate timestamp for request
    const timestamp = try auth.getTimeStamp(self.allocator);
    defer self.allocator.free(timestamp);

    // Prepare the host value
    const host = try std.fmt.allocPrint(self.allocator, "bedrock-runtime.{s}.amazonaws.com", .{self.config.region});
    defer self.allocator.free(host);

    // Build headers list
    var headers = std.ArrayList(std.http.Header).init(self.allocator);
    defer headers.deinit();

    try headers.append(.{ .name = "Host", .value = host });
    try headers.append(.{ .name = "Content-Type", .value = "application/json" });
    try headers.append(.{ .name = "X-Amz-Date", .value = timestamp });

    // Prepare the request payload
    var amazon_messages = std.ArrayList(AmazonMessage).init(self.allocator);
    defer amazon_messages.deinit();

    var system_messages = std.ArrayList(SystemBlock).init(self.allocator);
    defer system_messages.deinit();

    for (options.messages) |message| {
        if (std.mem.eql(u8, message.role, "system")) {
            const system_message = SystemBlock{ .text = message.content };
            try system_messages.append(system_message);
            continue;
        }
        const amazon_message = AmazonMessage{
            .role = message.role,
            .content = .{
                AmazoneMessageContent{ .text = message.content },
            },
        };
        try amazon_messages.append(amazon_message);
    }

    if (amazon_messages.items.len == 0) {
        std.debug.print("At least one message other than the system message is required.", .{});
        return Provider.Error.InvalidRequest;
    }

    const amazon_messages_final = try amazon_messages.toOwnedSlice();
    defer self.allocator.free(amazon_messages_final);

    var payload: AmazonPayload = .{ .messages = amazon_messages_final, .inferenceConfig = .{
        .maxTokens = options.max_tokens,
        .stopSequences = options.stop,
        .temperature = options.temperature,
        .topP = options.top_p,
    } };

    // Currently we are not handling all possible options. Potentially can reference `additionalModelRequestFields`
    // TODO: Figure out the equivilent rest of options being passed in.

    if (system_messages.items.len >= 1) {
        payload.system = system_messages.items;
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

    // Generate signature
    const signature_input = auth.SignatureInput{
        .method = "POST",
        .uri_path = uri_path,
        .region = self.config.region,
        .access_key = self.config.access_key_id,
        .secret_key = self.config.secret_access_key,
        .payload = body,
        .headers = headers,
        .timestamp = timestamp,
    };

    const authorization = auth.createSignature(self.allocator, signature_input) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer self.allocator.free(authorization);

    // Add authorization header
    try headers.append(.{ .name = "Authorization", .value = authorization });

    // Construct the full URL string first
    const url = try std.fmt.allocPrint(self.allocator, "https://{s}{s}", .{ host, uri_path });
    defer self.allocator.free(url);

    // Create request URI
    const uri = std.Uri.parse(url) catch |err| {
        return switch (err) {
            error.UnexpectedCharacter, error.InvalidFormat, error.InvalidPort => Provider.Error.InvalidRequest,
        };
    };

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

    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            else => Provider.Error.ParseError,
        };
    };
    defer parsed.deinit();

    // Extract the content from the response
    const message = parsed.value.object.get("output").?.object.get("message") orelse return Provider.Error.ApiError;
    const content = message.object.get("content") orelse return Provider.Error.ApiError;
    if (content.array.items.len == 0) return Provider.Error.ApiError;

    const text = content.array.items[0].object.get("text").?.string;
    return self.allocator.dupe(u8, text) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
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

fn chatStream(ctx: *anyopaque, options: ChatRequestOptions, writer: std.io.AnyWriter) Provider.Error!void {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    // converse-stream for the streaming api
    const uri_path = try std.fmt.allocPrint(self.allocator, "/model/{s}/converse-stream", .{options.model});
    defer self.allocator.free(uri_path);

    // Generate timestamp for request
    const timestamp = try auth.getTimeStamp(self.allocator);
    defer self.allocator.free(timestamp);

    // Prepare the host value
    const host = try std.fmt.allocPrint(self.allocator, "bedrock-runtime.{s}.amazonaws.com", .{self.config.region});
    defer self.allocator.free(host);

    // Build headers list
    var headers = std.ArrayList(std.http.Header).init(self.allocator);
    defer headers.deinit();

    try headers.append(.{ .name = "Host", .value = host });
    try headers.append(.{ .name = "Content-Type", .value = "application/json" });
    try headers.append(.{ .name = "X-Amz-Date", .value = timestamp });

    // Prepare the request payload
    var amazon_messages = std.ArrayList(AmazonMessage).init(self.allocator);
    defer amazon_messages.deinit();

    var system_messages = std.ArrayList(SystemBlock).init(self.allocator);
    defer system_messages.deinit();

    for (options.messages) |message| {
        if (std.mem.eql(u8, message.role, "system")) {
            const system_message = SystemBlock{ .text = message.content };
            try system_messages.append(system_message);
            continue;
        }
        const amazon_message = AmazonMessage{
            .role = message.role,
            .content = .{
                AmazoneMessageContent{ .text = message.content },
            },
        };
        try amazon_messages.append(amazon_message);
    }

    if (amazon_messages.items.len == 0) {
        std.debug.print("At least one message other than the system message is required.", .{});
        return Provider.Error.InvalidRequest;
    }

    const amazon_messages_final = try amazon_messages.toOwnedSlice();
    defer self.allocator.free(amazon_messages_final);

    var payload: AmazonPayload = .{ .messages = amazon_messages_final, .inferenceConfig = .{
        .maxTokens = options.max_tokens,
        .stopSequences = options.stop,
        .temperature = options.temperature,
        .topP = options.top_p,
    } };

    // Currently we are not handling all possible options. Potentially can reference `additionalModelRequestFields`
    // TODO: Figure out the equivilent rest of options being passed in.

    if (system_messages.items.len >= 1) {
        payload.system = system_messages.items;
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

    // Generate signature
    const signature_input = auth.SignatureInput{
        .method = "POST",
        .uri_path = uri_path,
        .region = self.config.region,
        .access_key = self.config.access_key_id,
        .secret_key = self.config.secret_access_key,
        .payload = body,
        .headers = headers,
        .timestamp = timestamp,
    };

    const authorization = auth.createSignature(self.allocator, signature_input) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer self.allocator.free(authorization);

    // Add authorization header
    try headers.append(.{ .name = "Authorization", .value = authorization });

    // Construct the full URL string first
    const url = try std.fmt.allocPrint(self.allocator, "https://{s}{s}", .{ host, uri_path });
    defer self.allocator.free(url);

    // Create request URI
    const uri = std.Uri.parse(url) catch |err| {
        return switch (err) {
            error.UnexpectedCharacter, error.InvalidFormat, error.InvalidPort => Provider.Error.InvalidRequest,
        };
    };

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
        // Ensure we have at least 4 bytes to read the message length.
        if (stream_buffer.items.len < 4) {
            const bytes_read = req.reader().read(&buffer) catch |err| {
                return switch (err) {
                    error.ConnectionTimedOut, error.ConnectionResetByPeer => Provider.Error.NetworkError,
                    error.TlsFailure, error.TlsAlert => Provider.Error.NetworkError,
                    error.UnexpectedReadFailure => Provider.Error.UnexpectedError,
                    error.EndOfStream => break, // End of stream; exit loop.
                    error.HttpChunkInvalid, error.HttpHeadersOversize, error.DecompressionFailure, error.InvalidTrailers => Provider.Error.ApiError,
                };
            };
            if (bytes_read == 0) break; // End of stream
            try stream_buffer.appendSlice(buffer[0..bytes_read]);
            continue;
        }

        // First 4 bytes hold the big-endian message length.
        const msg_len = std.mem.readInt(u32, stream_buffer.items[0..4], .big);
        if (stream_buffer.items.len < msg_len) {
            const bytes_read = req.reader().read(&buffer) catch |err| {
                return switch (err) {
                    error.ConnectionTimedOut, error.ConnectionResetByPeer => Provider.Error.NetworkError,
                    error.TlsFailure, error.TlsAlert => Provider.Error.NetworkError,
                    error.UnexpectedReadFailure => Provider.Error.UnexpectedError,
                    error.EndOfStream => break,
                    error.HttpChunkInvalid, error.HttpHeadersOversize, error.DecompressionFailure, error.InvalidTrailers => Provider.Error.ApiError,
                };
            };
            if (bytes_read == 0) break;
            try stream_buffer.appendSlice(buffer[0..bytes_read]);
            continue;
        }

        const msg_slice = stream_buffer.items[0..msg_len];
        const event = parseEventStreamMessage(msg_slice) catch |err| {
            // Convert our event-stream errors to the primary error type.
            switch (err) {
                EventStreamError.InsufficientData, EventStreamError.MalformedMessage => return Provider.Error.ParseError,
            }
        };

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, event.payload, .{}) catch |err| {
            stream_buffer.replaceRange(0, msg_len, &[_]u8{}) catch |replace_err| {
                return switch (replace_err) {
                    error.OutOfMemory => Provider.Error.OutOfMemory,
                };
            };
            if (err == error.InvalidCharacter) {
                continue;
            }
            return Provider.Error.ParseError;
        };
        defer parsed.deinit();

        // Process the parsed JSON as before.
        if (parsed.value.object.get("delta")) |content| {
            if (content.object.get("text")) |text| {
                writer.writeAll(text.string) catch |err| {
                    return switch (err) {
                        error.OutOfMemory => Provider.Error.OutOfMemory,
                        else => Provider.Error.UnexpectedError,
                    };
                };
            }
        } else if (parsed.value.object.get("stopReason")) |_| {
            break;
        }

        // Remove the processed event from the buffer.
        stream_buffer.replaceRange(0, msg_len, &[_]u8{}) catch |err| {
            return switch (err) {
                error.OutOfMemory => Provider.Error.OutOfMemory,
            };
        };
    }
}

fn createEmbedding(ctx: *anyopaque, options: requests.EmbeddingRequestOptions) Provider.Error![]f32 {
    _ = ctx;
    _ = options;
    @panic("Not implemented"); // Stub
}
