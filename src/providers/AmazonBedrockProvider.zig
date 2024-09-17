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

pub fn init(allocator: std.mem.Allocator, config: AmazonBedrockConfig) !Provider {
    var self = try allocator.create(Self);
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

fn chat(ctx: *anyopaque, options: ChatRequestOptions) (Provider.Error || error{UnexpectedCharacter,InvalidFormat,InvalidPort,MissingDateHeader})![]const u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = try std.fmt.allocPrint(self.allocator, "{s}/model/{s}/invoke", .{
        self.config.base_url,
        options.model,
    });
    defer self.allocator.free(uri_string);

    const uri = try std.Uri.parse(uri_string);

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

    const host = try std.fmt.allocPrint(self.allocator, "bedrock-runtime.{s}.amazonaws.com", .{self.config.region});
    defer self.allocator.free(host);

    const date = try self.getFormattedDate();
    defer self.allocator.free(date);

    var headers = std.StringHashMap([]const u8).init(self.allocator);
    defer headers.deinit();
    try headers.put("Content-Type", "application/json");
    try headers.put("Host", host);
    try headers.put("X-Amz-Date", date);

    const payload_hash = try self.signer.hashSha256(body);
    defer self.allocator.free(payload_hash);
    try headers.put("X-Amz-Content-Sha256", payload_hash);

    const auth_header = try self.signer.sign("POST", uri_string, headers, body);
    defer self.allocator.free(auth_header);

    var req = try client.request(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .authorization = .{ .override = auth_header },
        },
    });
    defer req.deinit();

    try req.headers.append("Host", host);
    try req.headers.append("X-Amz-Date", date);
    try req.headers.append("X-Amz-Content-Sha256", payload_hash);

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
        std.debug.print("Status: {d}\n", .{@intFromEnum(status)});
        return Provider.Error.ApiError;
    }

    const response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer self.allocator.free(response);

    std.debug.print("Response body: {s}\n", .{response});

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
