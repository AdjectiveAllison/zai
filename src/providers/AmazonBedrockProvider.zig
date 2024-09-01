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

pub fn init(allocator: std.mem.Allocator, config: AmazonBedrockConfig) !Provider {
    var self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.allocator = allocator;
    self.config = config;

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
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(uri_string);

    const uri = std.Uri.parse(uri_string) catch {
        return Provider.Error.InvalidRequest;
    };

    const amazon_messages = convertMessagesToAmazonFormat(self.allocator, options.messages) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer {
        for (amazon_messages) |msg| {
            self.allocator.free(msg.content);
        }
        self.allocator.free(amazon_messages);
    }

    const payload = .{
        .messages = amazon_messages,
        .inferenceConfig = .{
            .maxTokens = options.max_tokens,
            .temperature = options.temperature,
            .topP = options.top_p,
            .stream = options.stream,
        },
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

    const date = try self.getFormattedDate();
    defer self.allocator.free(date);

    // Convert uri.path to []const u8
    const path = switch (uri.path) {
        .raw => |p| p,
        .percent_encoded => |p| p,
    };

    const auth_header = try self.generateSignatureV4("POST", path, "", &[_]std.http.Header{.{ .name = "Content-Type", .value = "application/json" }}, body);
    defer self.allocator.free(auth_header);

    std.debug.print("Request payload: {s}\n", .{body});
    std.debug.print("Authorization header: {s}\n", .{auth_header});
    std.debug.print("X-Amz-Date header: {s}\n", .{date});
    std.debug.print("Request URL: {s}\n", .{uri_string});

    var req = client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .extra_headers = &[_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Authorization", .value = auth_header },
            .{ .name = "X-Amz-Date", .value = date },
        },
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
    const output = parsed.value.object.get("output") orelse return Provider.Error.ApiError;
    const message = output.object.get("message") orelse return Provider.Error.ApiError;
    const content = message.object.get("content") orelse return Provider.Error.ApiError;

    if (content.array.items.len == 0) return Provider.Error.ApiError;

    const text = content.array.items[0].object.get("text") orelse return Provider.Error.ApiError;

    return self.allocator.dupe(u8, text.string) catch |err| {
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

fn generateSignatureV4(self: *Self, method: []const u8, uri: []const u8, query: []const u8, headers: []const std.http.Header, payload: []const u8) Provider.Error![]const u8 {
    const algorithm = "AWS4-HMAC-SHA256";
    const service = "bedrock";
    const date = try self.getFormattedDate();
    const credential_scope = std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}/aws4_request", .{ date[0..8], self.config.region, service }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(credential_scope);

    var canonical_headers = std.ArrayList(u8).init(self.allocator);
    defer canonical_headers.deinit();
    var signed_headers = std.ArrayList(u8).init(self.allocator);
    defer signed_headers.deinit();

    for (headers) |header| {
        var lower_name: [256]u8 = undefined; // Adjust size as needed
        const lowered = std.ascii.lowerString(&lower_name, header.name);
        canonical_headers.writer().print("{s}:{s}\n", .{ lowered, header.value }) catch |err| {
            return switch (err) {
                error.OutOfMemory => Provider.Error.OutOfMemory,
            };
        };
        signed_headers.writer().print("{s};", .{lowered}) catch |err| {
            return switch (err) {
                error.OutOfMemory => Provider.Error.OutOfMemory,
            };
        };
    }
    _ = signed_headers.pop();

    var payload_hash: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(payload, &payload_hash, .{});

    const canonical_request = std.fmt.allocPrint(self.allocator, "{s}\n{s}\n{s}\n{s}\n{s}\n{x}", .{
        method,
        uri,
        query,
        canonical_headers.items,
        signed_headers.items,
        payload_hash,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(canonical_request);

    var canonical_request_hash: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(canonical_request, &canonical_request_hash, .{});

    const string_to_sign = std.fmt.allocPrint(self.allocator, "{s}\n{s}\n{s}\n{x}", .{
        algorithm,
        date,
        credential_scope,
        canonical_request_hash,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(string_to_sign);

    const aws4_key = std.fmt.allocPrint(self.allocator, "AWS4{s}", .{self.config.secret_access_key}) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(aws4_key);

    const k_date = try self.hmacSha256(aws4_key, date[0..8]);
    const k_region = try self.hmacSha256(&k_date, self.config.region);
    const k_service = try self.hmacSha256(&k_region, service);
    const k_signing = try self.hmacSha256(&k_service, "aws4_request");

    var signature: [32]u8 = undefined;
    HmacSha256.create(&signature, string_to_sign, &k_signing);

    return std.fmt.allocPrint(self.allocator, "{s} Credential={s}/{s}, SignedHeaders={s}, Signature={x}", .{
        algorithm,
        self.config.access_key_id,
        credential_scope,
        signed_headers.items,
        signature,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
}

fn hmacSha256(self: *Self, key: []const u8, data: []const u8) Provider.Error![32]u8 {
    _ = self;
    var out: [32]u8 = undefined;
    HmacSha256.create(&out, data, key);
    return out;
}

const AmazonMessage = struct {
    role: []const u8,
    content: []const AmazonContent,

    const AmazonContent = struct {
        text: []const u8,
    };
};

fn convertMessagesToAmazonFormat(allocator: std.mem.Allocator, messages: []const Message) ![]AmazonMessage {
    var amazon_messages = try allocator.alloc(AmazonMessage, messages.len);
    errdefer allocator.free(amazon_messages);

    for (messages, 0..) |msg, i| {
        const content = try allocator.alloc(AmazonMessage.AmazonContent, 1);
        errdefer allocator.free(content);
        content[0] = .{ .text = msg.content };

        amazon_messages[i] = AmazonMessage{
            .role = msg.role,
            .content = content,
        };
    }

    return amazon_messages;
}
