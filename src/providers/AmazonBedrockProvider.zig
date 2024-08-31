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
const Sha256 = std.crypto.hash.sha2.Sha256;
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

const Self = @This();

allocator: std.mem.Allocator,
config: AmazonBedrockConfig,
extra_headers: std.ArrayList(std.http.Header),

pub fn init(allocator: std.mem.Allocator, config: AmazonBedrockConfig) !Provider {
    var self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.allocator = allocator;
    self.config = config;
    self.extra_headers = std.ArrayList(std.http.Header).init(allocator);

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
            .getModelInfo = getModelInfo,
            .getModels = getModels,
        },
    };
}

fn setExtraHeaders(self: *Self) !void {
    try self.extra_headers.append(.{ .name = "Content-Type", .value = "application/json" });
}

fn deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.extra_headers.deinit();
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

    const uri_string = std.fmt.allocPrint(self.allocator, "{s}/model/{s}/invoke", .{ self.config.base_url, options.model }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(uri_string);

    const uri = std.Uri.parse(uri_string) catch {
        return Provider.Error.InvalidRequest;
    };

    // Prepare the request payload
    const payload = .{
        .prompt = try self.formatPrompt(options.messages),
        .max_tokens_to_sample = options.max_tokens orelse 100,
        .temperature = options.temperature orelse 0.7,
        .top_p = options.top_p orelse 1,
        .stop_sequences = options.stop orelse &[_][]const u8{},
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

    // Generate authorization header
    const method = "POST";
    const uri_path = std.fmt.allocPrint(self.allocator, "/model/{s}/invoke", .{options.model}) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(uri_path);
    const query = "";

    var headers = std.ArrayList(std.http.Header).init(self.allocator);
    defer headers.deinit();

    // Parse the base URL to get the host
    const base_uri = std.Uri.parse(self.config.base_url) catch {
        return Provider.Error.InvalidRequest;
    };
    const host = if (base_uri.host) |h| switch (h) {
        .raw, .percent_encoded => |value| value,
    } else return Provider.Error.InvalidRequest;

    headers.append(.{ .name = "host", .value = host }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    const formatted_date = self.getFormattedDate() catch |err| {
        return switch (err) {
            error.NoSpaceLeft => Provider.Error.OutOfMemory,
        };
    };
    headers.append(.{ .name = "x-amz-date", .value = formatted_date }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };

    const authorization_header = self.generateSignatureV4(method, uri_path, query, headers.items, body) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            error.NoSpaceLeft => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(authorization_header);

    var req = client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .authorization = .{ .override = authorization_header },
        },
        .extra_headers = self.extra_headers.items,
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
    const completion_content = parsed.value.object.get("completion") orelse return Provider.Error.ApiError;
    return self.allocator.dupe(u8, completion_content.string) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
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

fn formatPrompt(self: *Self, messages: []const Message) ![]const u8 {
    var prompt = std.ArrayList(u8).init(self.allocator);
    errdefer prompt.deinit();

    for (messages) |message| {
        const role = if (std.mem.eql(u8, message.role, "system") or std.mem.eql(u8, message.role, "user"))
            "Human: "
        else if (std.mem.eql(u8, message.role, "assistant"))
            "Assistant: "
        else if (std.mem.eql(u8, message.role, "function"))
            return error.InvalidRequest
        else
            return error.InvalidRequest;

        try prompt.appendSlice(role);
        try prompt.appendSlice(message.content);
        try prompt.appendSlice("\n");
    }

    try prompt.appendSlice("Assistant: ");

    return prompt.toOwnedSlice();
}

fn generateSignatureV4(self: *Self, method: []const u8, uri: []const u8, query: []const u8, headers: []const std.http.Header, payload: []const u8) ![]const u8 {
    const algorithm = "AWS4-HMAC-SHA256";
    const service = "bedrock";
    const date = try self.getFormattedDate();
    const credential_scope = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}/aws4_request", .{ date[0..8], self.config.region, service });
    defer self.allocator.free(credential_scope);

    var canonical_headers = std.ArrayList(u8).init(self.allocator);
    defer canonical_headers.deinit();
    var signed_headers = std.ArrayList(u8).init(self.allocator);
    defer signed_headers.deinit();

    for (headers) |header| {
        var lower_name: [256]u8 = undefined; // Adjust size as needed
        const lowered = std.ascii.lowerString(&lower_name, header.name);
        try canonical_headers.writer().print("{s}:{s}\n", .{ lowered, header.value });
        try signed_headers.writer().print("{s};", .{lowered});
    }
    _ = signed_headers.pop();

    var payload_hash: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(payload, &payload_hash, .{});

    const canonical_request = try std.fmt.allocPrint(self.allocator, "{s}\n{s}\n{s}\n{s}\n{s}\n{x}", .{
        method,
        uri,
        query,
        canonical_headers.items,
        signed_headers.items,
        payload_hash,
    });
    defer self.allocator.free(canonical_request);

    var canonical_request_hash: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(canonical_request, &canonical_request_hash, .{});

    const string_to_sign = try std.fmt.allocPrint(self.allocator, "{s}\n{s}\n{s}\n{x}", .{
        algorithm,
        date,
        credential_scope,
        canonical_request_hash,
    });
    defer self.allocator.free(string_to_sign);

    const aws4_key = try std.fmt.allocPrint(self.allocator, "AWS4{s}", .{self.config.secret_access_key});
    defer self.allocator.free(aws4_key);

    const k_date = try self.hmacSha256(aws4_key, date[0..8]);
    const k_region = try self.hmacSha256(&k_date, self.config.region);
    const k_service = try self.hmacSha256(&k_region, service);
    const k_signing = try self.hmacSha256(&k_service, "aws4_request");

    var signature: [32]u8 = undefined;
    HmacSha256.create(&signature, string_to_sign, &k_signing);

    return try std.fmt.allocPrint(self.allocator, "{s} Credential={s}/{s}, SignedHeaders={s}, Signature={x}", .{
        algorithm,
        self.config.access_key_id,
        credential_scope,
        signed_headers.items,
        signature,
    });
}

fn getFormattedDate(self: *Self) ![]const u8 {
    _ = self; // self is unused but kept for consistency
    var buffer: [32]u8 = undefined;
    const timestamp = std.time.timestamp();
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
    const epoch_day = epoch_seconds.getEpochDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return try std.fmt.bufPrint(&buffer, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
}

fn hmacSha256(self: *Self, key: []const u8, data: []const u8) ![32]u8 {
    _ = self;
    var out: [32]u8 = undefined;
    HmacSha256.create(&out, data, key);
    return out;
}
