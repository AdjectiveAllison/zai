const std = @import("std");
const config = @import("config.zig");
const core = @import("core.zig");
const requests = @import("requests.zig");
const models = @import("models.zig");
const OpenAIProvider = @import("providers/OpenAIProvider.zig");
const AmazonBedrockProvider = @import("providers/AmazonBedrockProvider.zig");

pub const Provider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (ctx: *anyopaque) void,
        completion: *const fn (ctx: *anyopaque, options: requests.CompletionRequestOptions) Error![]const u8,
        completionStream: *const fn (ctx: *anyopaque, options: requests.CompletionRequestOptions, writer: std.io.AnyWriter) Error!void,
        chat: *const fn (ctx: *anyopaque, options: requests.ChatRequestOptions) Error![]const u8,
        chatStream: *const fn (ctx: *anyopaque, options: requests.ChatRequestOptions, writer: std.io.AnyWriter) Error!void,
        createEmbedding: *const fn (ctx: *anyopaque, options: requests.EmbeddingRequestOptions) Error![]f32,
        getModelInfo: *const fn (ctx: *anyopaque, model_name: []const u8) Error!models.ModelInfo,
        getModels: *const fn (ctx: *anyopaque) Error![]const models.ModelInfo,
    };

    pub const Error = core.ZaiError;

    pub fn init(allocator: std.mem.Allocator, provider_config: config.ProviderConfig) !Provider {
        return switch (provider_config) {
            .OpenAI => |openai_config| OpenAIProvider.init(allocator, openai_config),
            .Anthropic => @panic("Anthropic provider not implemented"),
            .GoogleVertex => @panic("Google Vertex provider not implemented"),
            .AmazonBedrock => |bedrock_config| AmazonBedrockProvider.init(allocator, bedrock_config),
        };
    }

    pub fn deinit(self: *Provider) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn completion(self: *Provider, options: requests.CompletionRequestOptions) Error![]const u8 {
        return self.vtable.completion(self.ptr, options);
    }

    pub fn completionStream(self: *Provider, options: requests.CompletionRequestOptions, writer: anytype) Error!void {
        const Writer = std.io.GenericWriter(@TypeOf(writer), Error, struct {
            fn write(ctx: @TypeOf(writer), bytes: []const u8) Error!usize {
                return ctx.write(bytes) catch |err| switch (err) {
                    error.ConnectionResetByPeer => Error.NetworkError,
                    else => Error.UnexpectedError,
                };
            }
        }.write);
        var generic_writer = Writer{ .context = writer };
        return self.vtable.completionStream(self.ptr, options, generic_writer.any());
    }

    pub fn chat(self: *Provider, options: requests.ChatRequestOptions) Error![]const u8 {
        return self.vtable.chat(self.ptr, options);
    }

    pub fn chatStream(self: *Provider, options: requests.ChatRequestOptions, writer: anytype) Error!void {
        const Writer = std.io.GenericWriter(@TypeOf(writer), Error, struct {
            fn write(ctx: @TypeOf(writer), bytes: []const u8) Error!usize {
                return ctx.write(bytes) catch |err| switch (err) {
                    error.ConnectionResetByPeer => Error.NetworkError,
                    else => Error.UnexpectedError,
                };
            }
        }.write);
        var generic_writer = Writer{ .context = writer };
        return self.vtable.chatStream(self.ptr, options, generic_writer.any());
    }

    pub fn createEmbedding(self: *Provider, options: requests.EmbeddingRequestOptions) Error![]f32 {
        return self.vtable.createEmbedding(self.ptr, options);
    }

    pub fn getModelInfo(self: *Provider, model_name: []const u8) Error!models.ModelInfo {
        return self.vtable.getModelInfo(self.ptr, model_name);
    }

    pub fn getModels(self: *Provider) Error![]const models.ModelInfo {
        return self.vtable.getModels(self.ptr);
    }
};
