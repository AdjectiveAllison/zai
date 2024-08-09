const std = @import("std");

const ModelType = enum { chat, completion, embedding };

const ProviderInfo = struct {
    name: []const u8,
    base_url: []const u8,
    api_key_env_var: []const u8,
    models_endpoint: []const u8,
    supported_model_types: []const ModelType,
};

const ModelInfo = struct {
    display_name: []const u8,
    name: []const u8,
    id: []const u8,
    type: ModelType,
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
                .models_endpoint = "/models",
                .supported_model_types = &[_]ModelType{ .chat, .completion, .embedding },
            },
            .OctoAI => .{
                .name = "OctoAI",
                .base_url = "https://text.octoai.run/v1",
                .api_key_env_var = "OCTO_API_KEY",
                .models_endpoint = "/models",
                .supported_model_types = &[_]ModelType{ .chat, .completion },
            },
            .TogetherAI => .{
                .name = "TogetherAI",
                .base_url = "https://api.together.xyz/v1",
                .api_key_env_var = "TOGETHER_API_KEY",
                .models_endpoint = "/models",
                .supported_model_types = &[_]ModelType{ .chat, .completion },
            },
            .OpenRouter => .{
                .name = "OpenRouter",
                .base_url = "https://openrouter.ai/api/v1",
                .api_key_env_var = "OPENROUTER_API_KEY",
                .models_endpoint = "/models",
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
        \\    models_endpoint: []const u8,
        \\    supported_model_types: []const ModelType,
        \\};
        \\
        \\pub const ModelInfo = struct {
        \\    display_name: []const u8,
        \\    name: []const u8,
        \\    id: []const u8,
        \\    type: ModelType,
        \\};
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
    );

    inline for (std.meta.fields(Provider)) |provider_field| {
        try writer.print("        .{s} => {s}.info,\n", .{ provider_field.name, provider_field.name });
    }

    try writer.writeAll(
        \\    };
        \\}
        \\
        \\pub fn getModels(provider: Provider) type {
        \\    return switch (provider) {
    );

    inline for (std.meta.fields(Provider)) |provider_field| {
        try writer.print("        .{s} => {s}.Models,\n", .{ provider_field.name, provider_field.name });
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
    );

    const model_types = try formatModelTypes(allocator, info.supported_model_types);
    defer allocator.free(model_types);

    try writer.print(
        \\    .base_url = "{s}",
        \\    .api_key_env_var = "{s}",
        \\    .models_endpoint = "{s}",
        \\    .supported_model_types = &[_]providers.ModelType{{ {s} }},
        \\}};
        \\
        \\pub const Models = struct {{
        \\
    , .{
        info.base_url,
        info.api_key_env_var,
        info.models_endpoint,
        model_types,
    });

    for (models) |model| {
        try generateModelMethod(writer, model);
    }

    try writer.writeAll(
        \\};
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
        \\        }};
        \\    }}
        \\
    , .{ model.name, model.display_name, model.name, model.id, @tagName(model.type) });
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
        return &[_]ModelInfo{
            .{ .display_name = "GPT-3.5 Turbo", .name = "gpt_3_5_turbo", .id = "gpt-3.5-turbo", .type = .chat },
            .{ .display_name = "GPT-4", .name = "gpt_4", .id = "gpt-4", .type = .chat },
            .{ .display_name = "Text Embedding Ada 002", .name = "text_embedding_ada_002", .id = "text-embedding-ada-002", .type = .embedding },
        };
    } else if (std.mem.eql(u8, provider_name, "OctoAI")) {
        return &[_]ModelInfo{
            .{ .display_name = "Meta LLaMa 3.1 8B Instruct", .name = "meta_llama_3_1_8b_instruct", .id = "meta-llama-3.1-8b-instruct", .type = .chat },
            .{ .display_name = "Mixtral 8x7B Instruct", .name = "mixtral_8x7b_instruct", .id = "mixtral-8x7b-instruct", .type = .chat },
        };
    } else if (std.mem.eql(u8, provider_name, "TogetherAI")) {
        return &[_]ModelInfo{
            .{ .display_name = "Databricks DBRX Instruct", .name = "databricks_dbrx_instruct", .id = "databricks/dbrx-instruct", .type = .chat },
            .{ .display_name = "Meta LLaMa 3 8B HF", .name = "meta_llama_Llama_3_8b_hf", .id = "meta-llama/Llama-3-8b-hf", .type = .completion },
        };
    } else if (std.mem.eql(u8, provider_name, "OpenRouter")) {
        return &[_]ModelInfo{
            .{ .display_name = "Anthropic Claude 3.5 Sonnet", .name = "anthropic_claude_3_5_sonnet", .id = "anthropic/claude-3.5-sonnet", .type = .chat },
            .{ .display_name = "Meta LLaMa 3.1 405B", .name = "meta_llama_llama_3_1_405b", .id = "meta-llama/llama-3.1-405b", .type = .completion },
        };
    } else {
        @panic("Unknown provider");
    }
}
