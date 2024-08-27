const std = @import("std");
const OpenAIProvider = @import("providers/OpenAIProvider.zig");

pub const ProviderType = enum {
    OpenAI,
    Anthropic,
    GoogleVertex,
    AmazonBedrock,
};

pub const ModelType = enum { chat, completion, embedding };

// TODO: Add cost to these later on.
pub const ModelInfo = union(ModelType) {
    chat: struct {
        display_name: []const u8,
        name: []const u8,
        max_tokens: u32,
        // Add other chat model specific fields
    },
    completion: struct {
        display_name: []const u8,
        name: []const u8,
        max_tokens: u32,
        // Add other completion model specific fields
    },
    embedding: struct {
        display_name: []const u8,
        name: []const u8,
        dimensions: u32,
        // Add other embedding model specific fields
    },
};

pub const ProviderConfig = union(ProviderType) {
    OpenAI: OpenAIConfig,
    Anthropic: AnthropicConfig,
    GoogleVertex: GoogleVertexConfig,
    AmazonBedrock: AmazonBedrockConfig,
};

pub const OpenAIConfig = struct {
    api_key: []const u8,
    base_url: []const u8,
    organization: ?[]const u8 = null,
};

// Define other config structs similarly
pub const AnthropicConfig = struct {
    api_key: []const u8,
    anthropic_version: []const u8,
};

pub const GoogleVertexConfig = struct {
    api_key: []const u8,
    project_id: []const u8,
    location: []const u8,
};

pub const AmazonBedrockConfig = struct {
    // put stuff here
};

pub const ChatRequestOptions = struct {
    model: []const u8,
    messages: []const Message,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    n: ?u32 = null,
    stream: ?bool = null,
    stop: ?[]const []const u8 = null,
    presence_penalty: ?f32 = null,
    frequency_penalty: ?f32 = null,
    // logit_bias: ?std.StringHashMap(f32) = null,
    user: ?[]const u8 = null,
    // TODO: implement tool calling?
    // Additional fields for function calling
    // tools: ?[]const Tool = null,
    // tool_choice: ?ToolChoice = null,
    // Additional fields for image input
    // response_format: ?[]const u8 = null,
    seed: ?i64 = null,
};

pub const CompletionRequestOptions = struct {
    model: []const u8,
    prompt: []const u8,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    n: ?u32 = null,
    stream: ?bool = null,
    logprobs: ?u32 = null,
    echo: ?bool = null,
    stop: ?[]const []const u8 = null,
    presence_penalty: ?f32 = null,
    frequency_penalty: ?f32 = null,
    best_of: ?u32 = null,
    // TODO: Figure out how to json convert logic_bias for completion and chat. StringHashMap doesn't automatically stringifyAlloc.
    // logit_bias: ?std.StringHashMap(f32) = null,
    user: ?[]const u8 = null,
};

pub const EmbeddingRequestOptions = struct {
    model: []const u8,
    input: []const u8,
    user: ?[]const u8 = null,
    encoding_format: ?[]const u8 = null,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const Provider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (ctx: *anyopaque) void,
        completion: *const fn (ctx: *anyopaque, options: CompletionRequestOptions) Error![]const u8,
        completionStream: *const fn (ctx: *anyopaque, options: CompletionRequestOptions, writer: std.io.AnyWriter) Error!void,
        chat: *const fn (ctx: *anyopaque, options: ChatRequestOptions) Error![]const u8,
        chatStream: *const fn (ctx: *anyopaque, options: ChatRequestOptions, writer: std.io.AnyWriter) Error!void,
        createEmbedding: *const fn (ctx: *anyopaque, options: EmbeddingRequestOptions) Error![]f32,
        getModelInfo: *const fn (ctx: *anyopaque, model_name: []const u8) Error!ModelInfo,
        getModels: *const fn (ctx: *anyopaque) Error![]const ModelInfo,
    };

    pub const Error = error{
        OutOfMemory,
        ApiError,
        InvalidRequest,
        NetworkError,
        ParseError,
        UnexpectedError,
    };

    pub fn init(allocator: std.mem.Allocator, config: ProviderConfig) !Provider {
        return switch (config) {
            .OpenAI => |openai_config| OpenAIProvider.init(allocator, openai_config),
            .Anthropic => @panic("Anthropic provider not implemented"),
            .GoogleVertex => @panic("Google Vertex provider not implemented"),
            .AmazonBedrock => @panic("Amazon Bedrock provider not implemented"),
        };
    }

    pub fn deinit(self: *Provider) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn completion(self: *Provider, options: CompletionRequestOptions) Error![]const u8 {
        return self.vtable.completion(self.ptr, options);
    }

    pub fn completionStream(self: *Provider, options: CompletionRequestOptions, writer: anytype) Error!void {
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

    pub fn chat(self: *Provider, options: ChatRequestOptions) Error![]const u8 {
        return self.vtable.chat(self.ptr, options);
    }

    pub fn chatStream(self: *Provider, options: ChatRequestOptions, writer: anytype) Error!void {
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

    pub fn createEmbedding(self: *Provider, options: EmbeddingRequestOptions) Error![]f32 {
        return self.vtable.createEmbedding(self.ptr, options);
    }

    pub fn getModelInfo(self: *Provider, model_name: []const u8) Error!ModelInfo {
        return self.vtable.getModelInfo(self.ptr, model_name);
    }

    pub fn getModels(self: *Provider) Error![]const ModelInfo {
        return self.vtable.getModels(self.ptr);
    }
};
