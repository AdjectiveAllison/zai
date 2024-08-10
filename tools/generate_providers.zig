const std = @import("std");

const ModelType = enum { chat, completion, embedding };

const ProviderInfo = struct {
    name: []const u8,
    base_url: []const u8,
    api_key_env_var: []const u8,
    supported_model_types: []const ModelType,
};

const ModelInfo = struct {
    display_name: []const u8,
    name: []const u8,
    id: []const u8,
    type: ModelType,
    cost_per_million_tokens: f32,
    max_token_length: u32,
};

const Provider = enum {
    OpenAI,
    OctoAI,
    TogetherAI,
    OpenRouter,

    pub fn getInfo(self: Provider) ProviderInfo {
        return switch (self) {
            .OpenAI => .{
                .name = "OpenAI",
                .base_url = "https://api.openai.com/v1",
                .api_key_env_var = "OPENAI_API_KEY",
                .supported_model_types = &[_]ModelType{ .chat, .completion, .embedding },
            },
            .OctoAI => .{
                .name = "OctoAI",
                .base_url = "https://text.octoai.run/v1",
                .api_key_env_var = "OCTOAI_TOKEN",
                .supported_model_types = &[_]ModelType{ .chat, .embedding },
            },
            .TogetherAI => .{
                .name = "TogetherAI",
                .base_url = "https://api.together.xyz/v1",
                .api_key_env_var = "TOGETHER_API_KEY",
                .supported_model_types = &[_]ModelType{ .chat, .completion, .embedding },
            },
            .OpenRouter => .{
                .name = "OpenRouter",
                .base_url = "https://openrouter.ai/api/v1",
                .api_key_env_var = "OPENROUTER_API_KEY",
                .supported_model_types = &[_]ModelType{ .chat, .completion },
            },
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Generate the main providers.zig file
    try generateMainFile(allocator);

    // Generate provider-specific files
    inline for (std.meta.fields(Provider)) |provider_field| {
        try generateProviderFile(allocator, @field(Provider, provider_field.name));
    }
}

fn generateMainFile(allocator: std.mem.Allocator) !void {
    _ = allocator;
    var file = try std.fs.cwd().createFile("src/providers.zig", .{});
    defer file.close();

    var writer = file.writer();

    try writer.writeAll(
        \\// This file is auto-generated. Do not edit manually.
        \\
        \\const std = @import("std");
        \\
        \\pub const Provider = enum {
        \\
    );

    // Dynamically generate the ProviderType enum fields
    inline for (std.meta.fields(Provider)) |provider_field| {
        try writer.print("    {s},\n", .{provider_field.name});
    }

    // Close the enum and write the rest of the file
    try writer.writeAll(
        \\};
        \\
        \\pub const ModelType = enum { chat, completion, embedding };
        \\
        \\pub const ProviderInfo = struct {
        \\    base_url: []const u8,
        \\    api_key_env_var: []const u8,
        \\    supported_model_types: []const ModelType,
        \\};
        \\
        \\pub const ModelInfo = struct {
        \\    display_name: []const u8,
        \\    name: []const u8,
        \\    id: []const u8,
        \\    type: ModelType,
        \\    cost_per_million_tokens: f32,
        \\    max_token_length: u32,
        \\};
        \\
        \\
    );

    // Import provider-specific modules
    inline for (std.meta.fields(Provider)) |provider_field| {
        try writer.print("pub const {s} = @import(\"providers/{s}.zig\");\n", .{ provider_field.name, provider_field.name });
    }

    try writer.writeAll(
        \\
        \\pub fn getProviderInfo(provider: Provider) ProviderInfo {
        \\    return switch (provider) {
        \\
    );

    inline for (std.meta.fields(Provider)) |provider_field| {
        try writer.print("        .{s} => {s}.info,\n", .{ provider_field.name, provider_field.name });
    }

    try writer.writeAll(
        \\    };
        \\}
        \\
        \\pub fn getModels(provider: Provider) []const ModelInfo {
        \\    return switch (provider) {
        \\
    );

    inline for (std.meta.fields(Provider)) |provider_field| {
        try writer.print("        .{s} => {s}.getAllModels(),\n", .{ provider_field.name, provider_field.name });
    }

    try writer.writeAll(
        \\    };
        \\}
    );
}

fn generateProviderFile(allocator: std.mem.Allocator, provider: Provider) !void {
    const info = provider.getInfo();
    const models = getModelsForProvider(info.name);

    const file_path = try std.fmt.allocPrint(allocator, "src/providers/{s}.zig", .{@tagName(provider)});
    defer allocator.free(file_path);

    var file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    var writer = file.writer();

    try writer.writeAll(
        \\// This file is auto-generated. Do not edit manually.
        \\
        \\const std = @import("std");
        \\const providers = @import("../providers.zig");
        \\
        \\pub const info = providers.ProviderInfo{
        \\
    );

    const model_types = try formatModelTypes(allocator, info.supported_model_types);
    defer allocator.free(model_types);

    try writer.print(
        \\    .base_url = "{s}",
        \\    .api_key_env_var = "{s}",
        \\    .supported_model_types = &[_]providers.ModelType{{ {s} }},
        \\}};
        \\
        \\pub const Models = struct {{
        \\
    , .{
        info.base_url,
        info.api_key_env_var,
        model_types,
    });

    for (models) |model| {
        try generateModelMethod(writer, model);
    }

    try writer.writeAll(
        \\};
        \\
        \\pub fn getAllModels() []const providers.ModelInfo {
        \\    const declarations = @typeInfo(Models).Struct.decls;
        \\
        \\    var models: [declarations.len]providers.ModelInfo = undefined;
        \\    comptime var i = 0;
        \\    inline for (declarations) |declaration| {
        \\        if (@TypeOf(@field(Models, declaration.name)) == fn () providers.ModelInfo) {
        \\            models[i] = @field(Models, declaration.name)();
        \\            i += 1;
        \\        }
        \\    }
        \\    return models[0..i];
        \\}
        \\
    );
}

fn generateModelMethod(writer: anytype, model: ModelInfo) !void {
    try writer.print(
        \\    pub fn {0s}() providers.ModelInfo {{
        \\        return .{{
        \\            .display_name = "{1s}",
        \\            .name = "{2s}",
        \\            .id = "{3s}",
        \\            .type = .{4s},
        \\            .cost_per_million_tokens = {5d},
        \\            .max_token_length = {6d},
        \\        }};
        \\    }}
        \\
    , .{ model.name, model.display_name, model.name, model.id, @tagName(model.type), model.cost_per_million_tokens, model.max_token_length });
}

fn formatModelTypes(allocator: std.mem.Allocator, types: []const ModelType) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (types, 0..) |t, i| {
        if (i > 0) try result.appendSlice(", ");
        try result.writer().print(".{s}", .{@tagName(t)});
    }

    return result.toOwnedSlice();
}

fn getModelsForProvider(provider_name: []const u8) []const ModelInfo {
    if (std.mem.eql(u8, provider_name, "OpenAI")) {
        return getOpenAIModels();
    } else if (std.mem.eql(u8, provider_name, "OctoAI")) {
        return getOctoAIModels();
    } else if (std.mem.eql(u8, provider_name, "TogetherAI")) {
        // TODO: Dynamically fetch full model list for togetherAI.
        return &[_]ModelInfo{
            .{ .display_name = "Databricks DBRX Instruct", .name = "databricks_dbrx_instruct", .id = "databricks/dbrx-instruct", .type = .chat, .cost_per_million_tokens = 1.20, .max_token_length = 32768 },
            .{ .display_name = "Meta LLaMa 3 8B HF", .name = "meta_llama_Llama_3_8b_hf", .id = "meta-llama/Llama-3-8b-hf", .type = .completion, .cost_per_million_tokens = 0.20, .max_token_length = 8192 },
        };
    } else if (std.mem.eql(u8, provider_name, "OpenRouter")) {
        // TODO: dynamically fetch full model list for OpenRouter
        return &[_]ModelInfo{
            .{ .display_name = "Anthropic Claude 3.5 Sonnet", .name = "anthropic_claude_3_5_sonnet", .id = "anthropic/claude-3.5-sonnet", .type = .chat, .cost_per_million_tokens = 3.0, .max_token_length = 200000 },
            .{ .display_name = "Meta LLaMa 3.1 405B base", .name = "meta_llama_llama_3_1_405b", .id = "meta-llama/llama-3.1-405b", .type = .completion, .cost_per_million_tokens = 2.0, .max_token_length = 131072 },
        };
    } else {
        @panic("Unknown provider");
    }
}

pub fn getOctoAIModels() []const ModelInfo {
    return &[_]ModelInfo{
        .{ .display_name = "GTE Large", .name = "gte_large", .id = "thenlper/gte-large", .type = .embedding, .cost_per_million_tokens = 0.05, .max_token_length = 8192 },
        .{ .display_name = "Mistral 7B Instruct", .name = "mistral_7b_instruct", .id = "mistral-7b-instruct", .type = .chat, .cost_per_million_tokens = 0.15, .max_token_length = 32768 },
        .{ .display_name = "WizardLM 2 8x22B", .name = "wizardlm_2_8x22b", .id = "wizardlm-2-8x22b", .type = .chat, .cost_per_million_tokens = 1.20, .max_token_length = 65536 },
        .{ .display_name = "Mixtral 8x7B Instruct", .name = "mixtral_8x7b_instruct", .id = "mixtral-8x7b-instruct", .type = .chat, .cost_per_million_tokens = 0.45, .max_token_length = 32768 },
        .{ .display_name = "Mixtral 8x22B Instruct", .name = "mixtral_8x22b_instruct", .id = "mixtral-8x22b-instruct", .type = .chat, .cost_per_million_tokens = 1.20, .max_token_length = 65536 },
        .{ .display_name = "Meta LLaMa 3.1 8B Instruct", .name = "meta_llama_3_1_8b_instruct", .id = "meta-llama-3.1-8b-instruct", .type = .chat, .cost_per_million_tokens = 0.15, .max_token_length = 131072 },
        .{ .display_name = "Meta LLaMa 3.1 70B Instruct", .name = "meta_llama_3_1_70b_instruct", .id = "meta-llama-3.1-70b-instruct", .type = .chat, .cost_per_million_tokens = 0.90, .max_token_length = 131072 },
        .{ .display_name = "Meta LLaMa 3.1 405B Instruct", .name = "meta_llama_3_1_405b_instruct", .id = "meta-llama-3.1-405b-instruct", .type = .chat, .cost_per_million_tokens = 3.00, .max_token_length = 131072 },
    };
}

pub fn getOpenAIModels() []const ModelInfo {
    return &[_]ModelInfo{
        .{
            .display_name = "GPT-4o",
            .name = "gpt_4o",
            .id = "gpt-4o",
            .type = .chat,
            .cost_per_million_tokens = 5.00,
            .max_token_length = 128000,
        },
        .{
            .display_name = "GPT-4o Mini",
            .name = "gpt_4o_mini",
            .id = "gpt-4o-mini",
            .type = .chat,
            .cost_per_million_tokens = 0.15,
            .max_token_length = 128000,
        },
        .{
            .display_name = "GPT-4",
            .name = "gpt_4",
            .id = "gpt-4",
            .type = .chat,
            .cost_per_million_tokens = 30.00,
            .max_token_length = 8192,
        },
        .{
            .display_name = "GPT-4 Turbo",
            .name = "gpt_4_turbo",
            .id = "gpt-4-turbo",
            .type = .chat,
            .cost_per_million_tokens = 10.00,
            .max_token_length = 128000,
        },
        .{
            .display_name = "GPT-3.5 Turbo",
            .name = "gpt_3_5_turbo",
            .id = "gpt-3.5-turbo",
            .type = .chat,
            .cost_per_million_tokens = 0.50,
            .max_token_length = 16385,
        },
        .{
            .display_name = "GPT-3.5 Turbo Instruct",
            .name = "gpt_3_5_turbo_instruct",
            .id = "gpt-3.5-turbo-instruct",
            .type = .completion,
            .cost_per_million_tokens = 1.50,
            .max_token_length = 4096,
        },
        .{
            .display_name = "Text Embedding 3 Large",
            .name = "text_embedding_3_large",
            .id = "text-embedding-3-large",
            .type = .embedding,
            .cost_per_million_tokens = 0.13,
            .max_token_length = 8191,
        },
        .{
            .display_name = "Text Embedding 3 Small",
            .name = "text_embedding_3_small",
            .id = "text-embedding-3-small",
            .type = .embedding,
            .cost_per_million_tokens = 0.02,
            .max_token_length = 8191,
        },
        .{
            .display_name = "Text Embedding Ada 002",
            .name = "text_embedding_ada_002",
            .id = "text-embedding-ada-002",
            .type = .embedding,
            .cost_per_million_tokens = 0.10,
            .max_token_length = 8191,
        },
    };
}
