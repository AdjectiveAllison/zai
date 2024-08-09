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

    try writer.writeAll("// This file is auto-generated. Do not edit manually.\n\n");
    try writer.writeAll("const std = @import(\"std\");\n\n");

    try writer.writeAll("pub const ProviderType = enum {\n");
    inline for (std.meta.fields(Providers)) |provider_field| {
        try writer.print("    {s},\n", .{provider_field.name});
    }
    try writer.writeAll("};\n\n");

    try writer.writeAll("pub const ModelType = enum { chat, completion, embedding };\n\n");

    try writer.writeAll("pub const ModelInfo = struct {\n");
    try writer.writeAll("    display_name: []const u8,\n");
    try writer.writeAll("    name: []const u8,\n");
    try writer.writeAll("    id: []const u8,\n");
    try writer.writeAll("    type: ModelType,\n");
    try writer.writeAll("};\n\n");

    try writer.writeAll("pub const ProviderInterface = struct {\n");
    try writer.writeAll("    base_url: []const u8,\n");
    try writer.writeAll("    api_key_env_var: []const u8,\n");
    try writer.writeAll("    models_endpoint: []const u8,\n");
    try writer.writeAll("    getModelInfo: *const fn ([]const u8) ?ModelInfo,\n");
    try writer.writeAll("    modelToString: *const fn (anytype) []const u8,\n");
    try writer.writeAll("    modelFromString: *const fn ([]const u8) ?anytype,\n");
    try writer.writeAll("    listModels: *const fn () []const ModelInfo,\n");
    try writer.writeAll("};\n\n");

    try writer.writeAll("pub const Provider = struct {\n");
    try writer.writeAll("    provider_type: ProviderType,\n");
    try writer.writeAll("    interface: ProviderInterface,\n\n");

    try writer.writeAll("    pub fn init(provider_type: ProviderType) Provider {\n");
    try writer.writeAll("        return switch (provider_type) {\n");
    inline for (std.meta.fields(Providers)) |provider_field| {
        try writer.print("            .{s} => .{{ .provider_type = .{s}, .interface = @import(\"providers/{s}.zig\").getInterface() }},\n", .{ provider_field.name, provider_field.name, provider_field.name });
    }
    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn getBaseUrl(self: Provider) []const u8 {\n");
    try writer.writeAll("        return self.interface.base_url;\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn getApiKeyEnvVar(self: Provider) []const u8 {\n");
    try writer.writeAll("        return self.interface.api_key_env_var;\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn getModelsEndpoint(self: Provider) []const u8 {\n");
    try writer.writeAll("        return self.interface.models_endpoint;\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn getModelInfo(self: Provider, model_name: []const u8) ?ModelInfo {\n");
    try writer.writeAll("        return self.interface.getModelInfo(model_name);\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn modelToString(self: Provider, model: anytype) []const u8 {\n");
    try writer.writeAll("        return self.interface.modelToString(model);\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn modelFromString(self: Provider, model_name: []const u8) ?anytype {\n");
    try writer.writeAll("        return self.interface.modelFromString(model_name);\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn listModels(self: Provider) []const ModelInfo {\n");
    try writer.writeAll("        return self.interface.listModels();\n");
    try writer.writeAll("    }\n");

    try writer.writeAll("};\n");
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

    try writer.writeAll("// This file is auto-generated. Do not edit manually.\n\n");
    try writer.writeAll("const std = @import(\"std\");\n");
    try writer.writeAll("const providers = @import(\"../providers.zig\");\n\n");

    try writer.print("pub const {s} = struct {{\n", .{@tagName(provider)});
    try writer.writeAll("    pub const Model = enum {\n");
    for (models) |model| {
        try writer.print("        {s},\n", .{model.name});
    }
    try writer.writeAll("    };\n\n");

    try writer.writeAll("    const ModelData = struct {\n");
    try writer.writeAll("        display_name: []const u8,\n");
    try writer.writeAll("        id: []const u8,\n");
    try writer.writeAll("        type: providers.ModelType,\n");
    try writer.writeAll("    };\n\n");

    try writer.writeAll("    const model_data = std.ComptimeStringMap(ModelData, .{\n");
    for (models) |model| {
        try writer.print("        .{{ .{s} = .{{ .display_name = \"{s}\", .id = \"{s}\", .type = .{s} }} }},\n", .{ model.name, model.display_name, model.id, @tagName(model.type) });
    }
    try writer.writeAll("    });\n\n");

    try writer.writeAll("    pub fn getInterface() providers.ProviderInterface {\n");
    try writer.print("        return .{{\n", .{});
    try writer.print("            .base_url = \"{s}\",\n", .{info.base_url});
    try writer.print("            .api_key_env_var = \"{s}\",\n", .{info.api_key_env_var});
    try writer.print("            .models_endpoint = \"{s}\",\n", .{info.models_endpoint});
    try writer.writeAll("            .getModelInfo = getModelInfo,\n");
    try writer.writeAll("            .modelToString = modelToString,\n");
    try writer.writeAll("            .modelFromString = modelFromString,\n");
    try writer.writeAll("            .listModels = listModels,\n");
    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    fn getModelInfo(model_name: []const u8) ?providers.ModelInfo {\n");
    try writer.writeAll("        if (modelFromString(model_name)) |model| {\n");
    try writer.writeAll("            const data = model_data.get(@tagName(model)).?;\n");
    try writer.writeAll("            return providers.ModelInfo{\n");
    try writer.writeAll("                .display_name = data.display_name,\n");
    try writer.writeAll("                .name = @tagName(model),\n");
    try writer.writeAll("                .id = data.id,\n");
    try writer.writeAll("                .type = data.type,\n");
    try writer.writeAll("            };\n");
    try writer.writeAll("        }\n");
    try writer.writeAll("        return null;\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    fn modelToString(model: Model) []const u8 {\n");
    try writer.writeAll("        return @tagName(model);\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    fn modelFromString(model_name: []const u8) ?Model {\n");
    try writer.writeAll("        return std.meta.stringToEnum(Model, model_name);\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    fn listModels() []const providers.ModelInfo {\n");
    try writer.writeAll("        comptime {\n");
    try writer.writeAll("            var models: [model_data.count]providers.ModelInfo = undefined;\n");
    try writer.writeAll("            var i: usize = 0;\n");
    try writer.writeAll("            for (std.enums.values(Model)) |model| {\n");
    try writer.writeAll("                const data = model_data.get(@tagName(model)).?;\n");
    try writer.writeAll("                models[i] = .{\n");
    try writer.writeAll("                    .display_name = data.display_name,\n");
    try writer.writeAll("                    .name = @tagName(model),\n");
    try writer.writeAll("                    .id = data.id,\n");
    try writer.writeAll("                    .type = data.type,\n");
    try writer.writeAll("                };\n");
    try writer.writeAll("                i += 1;\n");
    try writer.writeAll("            }\n");
    try writer.writeAll("            return &models;\n");
    try writer.writeAll("        }\n");
    try writer.writeAll("    }\n");

    try writer.writeAll("};\n");
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
