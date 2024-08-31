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

const Self = @This();

allocator: std.mem.Allocator,
config: AmazonBedrockConfig,
authorization_header: []const u8,
extra_headers: std.ArrayList(std.http.Header),

pub fn init(allocator: std.mem.Allocator, config: AmazonBedrockConfig) !Provider {
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
            .getModelInfo = getModelInfo,
            .getModels = getModels,
        },
    };
}

fn setAuthorizationHeader(self: *Self) !void {
    // Amazon Bedrock uses AWS Signature V4 for authorization
    // This is a placeholder and needs to be implemented properly
    self.authorization_header = try self.allocator.dupe(u8, "AWS4-HMAC-SHA256 Credential=...");
}

fn setExtraHeaders(self: *Self) !void {
    try self.extra_headers.append(.{ .name = "Content-Type", .value = "application/json" });
}

fn deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.allocator.free(self.authorization_header);
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

    const uri_string = try std.fmt.allocPrint(
        self.allocator,
        "{s}/model/{s}/invoke",
        .{ self.config.base_url, options.model }
    );
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

    const body = try std.json.stringifyAlloc(self.allocator, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    });
    defer self.allocator.free(body);

    var req = try client.request(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .authorization = .{ .override = self.authorization_header },
        },
        .extra_headers = self.extra_headers.items,
    });
    defer req.deinit();

    req.transfer_encoding = .chunked;

    try req.start();
    try req.writeAll(body);
    try req.finish();
    try req.wait();

    const status = req.response.status;
    if (status != .ok) {
        const error_response = try req.reader().readAllAlloc(self.allocator, 3276800);
        defer self.allocator.free(error_response);
        std.debug.print("Error response: {s}\n", .{error_response});
        return Provider.Error.ApiError;
    }

    const response = try req.reader().readAllAlloc(self.allocator, 3276800);
    defer self.allocator.free(response);

    // Parse the response
    const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, response, .{});
    defer parsed.deinit();

    // Extract the content from the response
    const completion = parsed.value.object.get("completion") orelse return Provider.Error.ApiError;
    return try self.allocator.dupe(u8, completion.string);
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
    defer prompt.deinit();

    for (messages) |message| {
        const role = switch (message.role) {
            .system => "Human: ",
            .user => "Human: ",
            .assistant => "Assistant: ",
            .function => unreachable, // Not supported in this implementation
        };

        try prompt.appendSlice(role);
        try prompt.appendSlice(message.content);
        try prompt.appendSlice("\n");
    }

    try prompt.appendSlice("Assistant: ");

    return prompt.toOwnedSlice();
}
