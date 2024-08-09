const std = @import("std");

const ModelType = enum { chat, completion, embedding };

const ProviderInfo = struct {
    name: []const u8,
    base_url: []const u8,
    api_key_env_var: []const u8,
    models_endpoint: []const u8,
};

const ModelInfo = struct {
    display_name: []const u8,
    name: []const u8,
    id: []const u8,
    type: ModelType,
};

const Providers = enum {
    OpenAI,
    OctoAI,
    TogetherAI,
    OpenRouter,

    pub fn getInfo(self: Providers) ProviderInfo {
        return switch (self) {
            .OpenAI => .{
                .name = "OpenAI",
                .base_url = "https://api.openai.com/v1",
                .api_key_env_var = "OPENAI_API_KEY",
                .models_endpoint = "/models",
            },
            .OctoAI => .{
                .name = "OctoAI",
                .base_url = "https://text.octoai.run/v1",
                .api_key_env_var = "OCTO_API_KEY",
                .models_endpoint = "/models",
            },
            .TogetherAI => .{
                .name = "TogetherAI",
                .base_url = "https://api.together.xyz/v1",
                .api_key_env_var = "TOGETHER_API_KEY",
                .models_endpoint = "/models",
            },
            .OpenRouter => .{
                .name = "OpenRouter",
                .base_url = "https://openrouter.ai/api/v1",
                .api_key_env_var = "OPENROUTER_API_KEY",
                .models_endpoint = "/models",
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
    inline for (std.meta.fields(Providers)) |provider_field| {
        try generateProviderFile(allocator, @field(Providers, provider_field.name));
    }
}

fn generateMainFile(allocator: std.mem.Allocator) !void {
    _ = allocator;
    var file = try std.fs.cwd().createFile("src/providers.zig", .{});
    defer file.close();

    var writer = file.writer();

    // Write the initial part
    try writer.writeAll(
        \\// This file is auto-generated. Do not edit manually.
        \\
        \\const std = @import("std");
        \\
        \\pub const ProviderType = enum {
    );

    // Dynamically generate the ProviderType enum fields
    inline for (std.meta.fields(Providers)) |provider_field| {
        try writer.print("    {s},\n", .{provider_field.name});
    }

    // Close the enum and write the rest of the file
    try writer.writeAll(
        \\};
        \\
        \\pub const ModelType = enum { chat, completion, embedding };
        \\
        \\pub const ModelInfo = struct {
        \\    display_name: []const u8,
        \\    name: []const u8,
        \\    id: []const u8,
        \\    type: ModelType,
        \\};
        \\
        \\pub const ProviderInterface = struct {
        \\    base_url: []const u8,
        \\    api_key_env_var: []const u8,
        \\    models_endpoint: []const u8,
        \\    getModelInfo: *const fn ([]const u8) ?ModelInfo,
        \\    modelToString: *const fn (anytype) []const u8,
        \\    modelFromString: *const fn ([]const u8) ?type,
        \\    listModels: *const fn () []const ModelInfo,
        \\};
        \\
        \\pub const Provider = struct {
        \\    provider_type: ProviderType,
        \\    interface: ProviderInterface,
        \\
        \\    pub fn init(provider_type: ProviderType) Provider {
        \\        return switch (provider_type) {
    );

    // Dynamically generate the Provider.init function
    inline for (std.meta.fields(Providers)) |provider_field| {
        try writer.print("            .{s} => .{{ .provider_type = .{s}, .interface = @import(\"providers/{s}.zig\").getInterface() }},\n", .{ provider_field.name, provider_field.name, provider_field.name });
    }

    // Close the switch and write the rest of the file
    try writer.writeAll(
        \\        };
        \\    }
        \\
        \\    pub fn getBaseUrl(self: Provider) []const u8 {
        \\        return self.interface.base_url;
        \\    }
        \\
        \\    pub fn getApiKeyEnvVar(self: Provider) []const u8 {
        \\        return self.interface.api_key_env_var;
        \\    }
        \\
        \\    pub fn getModelsEndpoint(self: Provider) []const u8 {
        \\        return self.interface.models_endpoint;
        \\    }
        \\
        \\    pub fn getModelInfo(self: Provider, model_name: []const u8) ?ModelInfo {
        \\        return self.interface.getModelInfo(model_name);
        \\    }
        \\
        \\    pub fn modelToString(self: Provider, model: anytype) []const u8 {
        \\        return self.interface.modelToString(model);
        \\    }
        \\
        \\    pub fn modelFromString(self: Provider, model_name: []const u8) ?type {
        \\        return self.interface.modelFromString(model_name);
        \\    }
        \\
        \\    pub fn listModels(self: Provider) []const ModelInfo {
        \\        return self.interface.listModels();
        \\    }
        \\};
    );
}

fn generateProviderFile(allocator: std.mem.Allocator, provider: Providers) !void {
    const info = provider.getInfo();
    const models = getModelsForProvider(info.name);

    // Create the providers directory if it doesn't exist
    try std.fs.cwd().makePath("src/providers");

    const file_path = try std.fmt.allocPrint(allocator, "src/providers/{s}.zig", .{@tagName(provider)});
    defer allocator.free(file_path);

    var file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    var writer = file.writer();

    const formatted_models = try formatModels(allocator, models);
    defer allocator.free(formatted_models);

    const formatted_model_data = try formatModelData(allocator, models);
    defer allocator.free(formatted_model_data);

    try writer.print(
        \\// This file is auto-generated. Do not edit manually.
        \\
        \\const std = @import("std");
        \\const providers = @import("../providers.zig");
        \\
        \\pub const {0s} = struct {{
        \\    pub const Model = enum {{
        \\{1s}    }};
        \\
        \\    const ModelData = struct {{
        \\        display_name: []const u8,
        \\        id: []const u8,
        \\        type: providers.ModelType,
        \\    }};
        \\
        \\    const model_data = std.ComptimeStringMap(ModelData, .{{
        \\{2s}    }});
        \\
        \\    pub fn getInterface() providers.ProviderInterface {{
        \\        return .{{
        \\            .base_url = "{3s}",
        \\            .api_key_env_var = "{4s}",
        \\            .models_endpoint = "{5s}",
        \\            .getModelInfo = getModelInfo,
        \\            .modelToString = modelToString,
        \\            .modelFromString = modelFromString,
        \\            .listModels = listModels,
        \\        }};
        \\    }}
        \\
        \\    fn getModelInfo(model_name: []const u8) ?providers.ModelInfo {{
        \\        if (model_data.get(model_name)) |data| {{
        \\            return providers.ModelInfo{{
        \\                .display_name = data.display_name,
        \\                .name = model_name,
        \\                .id = data.id,
        \\                .type = data.type,
        \\            }};
        \\        }}
        \\        return null;
        \\    }}
        \\
        \\    fn modelToString(model: []const u8) []const u8 {{
        \\        return model;
        \\    }}
        \\
        \\    fn modelFromString(model_name: []const u8) ?[]const u8 {{
        \\        if (model_data.get(model_name)) |_| {{
        \\            return model_name;
        \\        }}
        \\        return null;
        \\    }}
        \\
        \\    fn listModels() []const providers.ModelInfo {{
        \\        comptime {{
        \\            var models: [model_data.map.len]providers.ModelInfo = undefined;
        \\            for (model_data.kvs, 0..) |kv, i| {{
        \\                models[i] = .{{
        \\                    .display_name = kv.value.display_name,
        \\                    .name = kv.key,
        \\                    .id = kv.value.id,
        \\                    .type = kv.value.type,
        \\                }};
        \\            }}
        \\            return &models;
        \\        }}
        \\    }}
        \\}};
    , .{
        @tagName(provider),
        formatted_models,
        formatted_model_data,
        info.base_url,
        info.api_key_env_var,
        info.models_endpoint,
    });
}

fn formatModels(allocator: std.mem.Allocator, models: []const ModelInfo) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (models) |model| {
        try result.writer().print("        {s},\n", .{model.name});
    }

    return result.toOwnedSlice();
}

fn formatModelData(allocator: std.mem.Allocator, models: []const ModelInfo) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (models) |model| {
        try result.writer().print("        .{{ .{s} = .{{ .display_name = \"{s}\", .id = \"{s}\", .type = .{s} }} }},\n", .{ model.name, model.display_name, model.id, @tagName(model.type) });
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
