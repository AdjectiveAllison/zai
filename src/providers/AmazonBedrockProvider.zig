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
const models = @import("../models.zig");
const ModelInfo = models.ModelInfo;
const Signer = @import("amazon/auth.zig").Signer;

const Self = @This();

allocator: std.mem.Allocator,
config: AmazonBedrockConfig,
signer: Signer,

pub fn init(allocator: std.mem.Allocator, config: AmazonBedrockConfig) Provider.Error!Provider {
    var self = allocator.create(Self) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    errdefer allocator.destroy(self);

    self.allocator = allocator;
    self.config = config;
    self.signer = Signer.init(allocator, config.access_key_id, config.secret_access_key, config.region);

    return .{
        .ptr = self,
        .vtable = &.{
            .deinit = deinit,
            .completion = completion,
            .completionStream = completionStream,
            .chat = chat,
            .chatStream = chatStream,
            .createEmbedding = createEmbedding,
            .getModelInfo = getModelInfo,
            .getModels = getModels,
        },
    };
}

fn deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.allocator.destroy(self);
}

fn completion(ctx: *anyopaque, options: CompletionRequestOptions) Provider.Error![]const u8 {
    _ = ctx;
    _ = options;
    @panic("Not implemented for Amazon Bedrock"); // Stub
}

fn completionStream(ctx: *anyopaque, options: CompletionRequestOptions, writer: std.io.AnyWriter) Provider.Error!void {
    _ = ctx;
    _ = options;
    _ = writer;
    @panic("Not implemented for Amazon Bedrock"); // Stub
}

fn chat(ctx: *anyopaque, options: ChatRequestOptions) Provider.Error![]const u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = std.fmt.allocPrint(self.allocator, "{s}/model/{s}/converse", .{
        self.config.base_url,
        options.model,
    }) catch |err| switch (err) {
        error.OutOfMemory => return Provider.Error.OutOfMemory,
    };
    defer self.allocator.free(uri_string);

    const uri = std.Uri.parse(uri_string) catch {
        return Provider.Error.InvalidRequest;
    };

    const formatted_messages = try formatMessages(self.allocator, options.messages);
    defer {
        for (formatted_messages) |msg| {
            self.allocator.free(msg.content);
        }
        self.allocator.free(formatted_messages);
    }

    const payload = .{
        .prompt = try std.fmt.allocPrint(self.allocator, "\n\nHuman: {s}\n\nAssistant:", .{options.messages[0].content}),
        .max_tokens_to_sample = options.max_tokens orelse 256,
        .temperature = options.temperature orelse 0.7,
        .top_p = options.top_p orelse 1,
        .stop_sequences = if (options.stop) |stop| stop else &[_][]const u8{"\n\nHuman:"},
        .anthropic_version = "bedrock-2023-05-31",
    };

    const body = std.json.stringifyAlloc(self.allocator, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(body);

    const host = try std.fmt.allocPrint(self.allocator, "bedrock-runtime.{s}.amazonaws.com", .{self.config.region});
    defer self.allocator.free(host);

    const date = try self.signer.getFormattedDate();
    defer self.allocator.free(date);

    var headers = std.StringHashMap([]const u8).init(self.allocator);
    defer headers.deinit();
    try headers.put("Content-Type", "application/json");
    try headers.put("Host", host);
    try headers.put("X-Amz-Date", date);

    const payload_hash = self.signer.hashSha256(body) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(payload_hash);
    try headers.put("X-Amz-Content-Sha256", payload_hash);

    const auth_header = self.signer.sign("POST", uri_string, &headers, body) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            error.MissingDateHeader => Provider.Error.InvalidRequest,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer self.allocator.free(auth_header);

    // Free the prompt after we're done with it
    defer self.allocator.free(payload.prompt);

    var extra_headers = std.ArrayList(std.http.Header).init(self.allocator);
    defer extra_headers.deinit();

    var headers_it = headers.iterator();
    while (headers_it.next()) |entry| {
        try extra_headers.append(.{ .name = entry.key_ptr.*, .value = entry.value_ptr.* });
    }
    try extra_headers.append(.{ .name = "Authorization", .value = auth_header });

    var req = client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .authorization = .{ .override = auth_header },
        },
        .extra_headers = extra_headers.items,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            error.ConnectionRefused, error.NetworkUnreachable, error.ConnectionTimedOut, error.TlsInitializationFailed, error.TemporaryNameServerFailure, error.NameServerFailure, error.UnknownHostName, error.HostLacksNetworkAddresses, error.UnexpectedConnectFailure, error.ConnectionResetByPeer => Provider.Error.NetworkError,
            error.UnsupportedUriScheme, error.UriMissingHost, error.InvalidContentLength, error.UnsupportedTransferEncoding => Provider.Error.InvalidRequest,
            error.CertificateBundleLoadFailure, error.UnexpectedWriteFailure => Provider.Error.UnexpectedError,
            error.Overflow, error.InvalidCharacter => Provider.Error.InvalidRequest,
        };
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;

    req.send() catch |err| return switch (err) {
        error.ConnectionResetByPeer => Provider.Error.NetworkError,
        error.UnexpectedWriteFailure => Provider.Error.UnexpectedError,
        error.InvalidContentLength, error.UnsupportedTransferEncoding => Provider.Error.InvalidRequest,
    };
    req.writer().writeAll(body) catch |err| return switch (err) {
        error.ConnectionResetByPeer => Provider.Error.NetworkError,
        else => Provider.Error.UnexpectedError,
    };
    req.finish() catch |err| return switch (err) {
        error.ConnectionResetByPeer => Provider.Error.NetworkError,
        else => Provider.Error.UnexpectedError,
    };
    req.wait() catch |err| return switch (err) {
        error.ConnectionResetByPeer => Provider.Error.NetworkError,
        else => Provider.Error.UnexpectedError,
    };

    const status = req.response.status;

    if (status != .ok) {
        const error_response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
            return switch (err) {
                error.OutOfMemory => Provider.Error.OutOfMemory,
                error.ConnectionResetByPeer, error.ConnectionTimedOut => Provider.Error.NetworkError,
                error.TlsFailure, error.TlsAlert => Provider.Error.NetworkError,
                error.UnexpectedReadFailure => Provider.Error.UnexpectedError,
                error.EndOfStream => Provider.Error.UnexpectedError,
                error.HttpChunkInvalid, error.HttpHeadersOversize, error.DecompressionFailure, error.InvalidTrailers => Provider.Error.ApiError,
                error.StreamTooLong => Provider.Error.UnexpectedError,
            };
        };
        defer self.allocator.free(error_response);
        std.debug.print("Error response: {s}\n", .{error_response});
        std.debug.print("Status: {d}\n", .{@intFromEnum(status)});
        std.debug.print("Request URL: {s}\n", .{uri_string});
        std.debug.print("Request body: {s}\n", .{body});
        std.debug.print("Request headers:\n", .{});
        for (extra_headers.items) |header| {
            std.debug.print("{s}: {s}\n", .{ header.name, header.value });
        }
        std.debug.print("Response headers:\n", .{});
        var header_it = req.response.iterateHeaders();
        while (header_it.next()) |header| {
            std.debug.print("{s}: {s}\n", .{ header.name, header.value });
        }
        return switch (status) {
            .bad_request => Provider.Error.InvalidRequest,
            .unauthorized => Provider.Error.Unauthorized,
            .forbidden => Provider.Error.Forbidden,
            .not_found => Provider.Error.NotFound,
            .too_many_requests => Provider.Error.RateLimitExceeded,
            .internal_server_error => Provider.Error.ServerError,
            else => Provider.Error.ApiError,
        };
    }

    const response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            error.ConnectionResetByPeer, error.ConnectionTimedOut => Provider.Error.NetworkError,
            error.TlsFailure, error.TlsAlert => Provider.Error.NetworkError,
            error.UnexpectedReadFailure => Provider.Error.UnexpectedError,
            error.EndOfStream => Provider.Error.UnexpectedError,
            error.HttpChunkInvalid, error.HttpHeadersOversize, error.DecompressionFailure, error.InvalidTrailers => Provider.Error.ApiError,
            error.StreamTooLong => Provider.Error.UnexpectedError,
        };
    };
    defer self.allocator.free(response);

    // Parse the response
    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch |err| return switch (err) {
        error.OutOfMemory => Provider.Error.OutOfMemory,
        else => Provider.Error.ParseError,
    };
    defer parsed.deinit();

    // Extract the content from the response
    const messages = parsed.value.object.get("messages") orelse return Provider.Error.ApiError;
    if (messages.array.items.len == 0) return Provider.Error.ApiError;

    const last_message = messages.array.items[messages.array.items.len - 1];
    const content = last_message.object.get("content") orelse return Provider.Error.ApiError;

    if (content.array.items.len == 0) return Provider.Error.ApiError;
    const text = content.array.items[0].object.get("text") orelse return Provider.Error.ApiError;

    return self.allocator.dupe(u8, text.string);
}

fn chatStream(ctx: *anyopaque, options: ChatRequestOptions, writer: std.io.AnyWriter) Provider.Error!void {
    _ = ctx;
    _ = options;
    _ = writer;
    @panic("Not implemented for Amazon Bedrock"); // Stub
}

fn createEmbedding(ctx: *anyopaque, options: EmbeddingRequestOptions) Provider.Error![]f32 {
    _ = ctx;
    _ = options;
    @panic("Not implemented for Amazon Bedrock"); // Stub
}

fn getModelInfo(ctx: *anyopaque, model_name: []const u8) Provider.Error!ModelInfo {
    _ = ctx;
    _ = model_name;
    @panic("Not implemented for Amazon Bedrock"); // Stub
}

fn getModels(ctx: *anyopaque) Provider.Error![]const ModelInfo {
    _ = ctx;
    @panic("Not implemented for Amazon Bedrock"); // Stub
}

fn getFormattedDate(self: *Self) ![]const u8 {
    // Get the current timestamp
    const now = std.time.timestamp();

    // Convert to UTC
    const utc = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
    const epoch_day = utc.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = utc.getDaySeconds();

    // Format the date string
    return try std.fmt.allocPrint(self.allocator, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
}

const AmazonMessage = struct {
    role: []const u8,
    content: []const u8,
};

const ChatResponse = struct {
    output: struct {
        message: struct {
            content: []struct {
                text: []const u8,
            },
        },
    },
    usage: ?struct {
        inputTokens: i64,
        outputTokens: i64,
        totalTokens: i64,
    },
    stop_reason: ?[]const u8,
    latency_ms: ?i64,
};

fn formatMessages(allocator: std.mem.Allocator, messages: []const Message) ![]AmazonMessage {
    var formatted_messages = try allocator.alloc(AmazonMessage, messages.len);
    errdefer allocator.free(formatted_messages);
    for (messages, 0..) |msg, i| {
        const content = try allocator.dupe(u8, msg.content);
        errdefer allocator.free(content);
        formatted_messages[i] = .{
            .role = msg.role,
            .content = content,
        };
    }
    return formatted_messages;
}

const TokenUsage = struct {
    inputTokens: i64,
    outputTokens: i64,
    totalTokens: i64,
};
