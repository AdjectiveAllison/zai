const std = @import("std");

const ModelType = enum { chat, completion, embedding };

const ProviderInfo = struct {
    name: []const u8,
    base_url: []const u8,
    api_key_env_var: []const u8,
    models_endpoint: []const u8,
};

const ModelInfo = struct {
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

    try writer.writeAll("pub const Provider = union(ProviderType) {\n");
    inline for (std.meta.fields(Providers)) |provider_field| {
        try writer.print("    {s}: @import(\"providers/{s}.zig\").{s},\n", .{ provider_field.name, provider_field.name, provider_field.name });
    }
    try writer.writeAll("\n");

    try writer.writeAll("    pub fn init(provider_type: ProviderType) Provider {\n");
    try writer.writeAll("        return switch (provider_type) {\n");
    inline for (std.meta.fields(Providers)) |provider_field| {
        try writer.print("            .{s} => .{{ .{s} = @import(\"providers/{s}.zig\").init() }},\n", .{ provider_field.name, provider_field.name, provider_field.name });
    }
    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn getBaseUrl(self: Provider) []const u8 {\n");
    try writer.writeAll("        return switch (self) {\n");
    inline for (std.meta.fields(Providers)) |provider_field| {
        try writer.print("            .{s} => |p| p.base_url,\n", .{provider_field.name});
    }
    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn getApiKeyEnvVar(self: Provider) []const u8 {\n");
    try writer.writeAll("        return switch (self) {\n");
    inline for (std.meta.fields(Providers)) |provider_field| {
        try writer.print("            .{s} => |p| p.api_key_env_var,\n", .{provider_field.name});
    }
    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn getModelsEndpoint(self: Provider) []const u8 {\n");
    try writer.writeAll("        return switch (self) {\n");
    inline for (std.meta.fields(Providers)) |provider_field| {
        try writer.print("            .{s} => |p| p.models_endpoint,\n", .{provider_field.name});
    }
    try writer.writeAll("        };\n");
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
    try writer.print("    base_url: []const u8 = \"{s}\",\n", .{info.base_url});
    try writer.print("    api_key_env_var: []const u8 = \"{s}\",\n", .{info.api_key_env_var});
    try writer.print("    models_endpoint: []const u8 = \"{s}\",\n\n", .{info.models_endpoint});

    try writer.writeAll("    pub const Model = enum {\n");
    for (models) |model| {
        const sanitized_model = try sanitizeModelName(allocator, model.id);
        defer allocator.free(sanitized_model);
        try writer.print("        {s},\n", .{sanitized_model});
    }
    try writer.writeAll("    };\n\n");

    try writer.writeAll("    pub fn init() @This() {\n");
    try writer.writeAll("        return .{};\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn modelToString(model: Model) []const u8 {\n");
    try writer.writeAll("        return switch (model) {\n");
    for (models) |model| {
        const sanitized_model = try sanitizeModelName(allocator, model.id);
        defer allocator.free(sanitized_model);
        try writer.print("            .{s} => \"{s}\",\n", .{ sanitized_model, model.id });
    }
    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn modelFromString(model_name: []const u8) ?Model {\n");
    try writer.writeAll("        inline for (@typeInfo(Model).Enum.fields) |field| {\n");
    try writer.writeAll("            if (std.mem.eql(u8, modelToString(@field(Model, field.name)), model_name)) {\n");
    try writer.writeAll("                return @field(Model, field.name);\n");
    try writer.writeAll("            }\n");
    try writer.writeAll("        }\n");
    try writer.writeAll("        return null;\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn modelGetType(model: Model) providers.ModelType {\n");
    try writer.writeAll("        return switch (model) {\n");
    for (models) |model| {
        const sanitized_model = try sanitizeModelName(allocator, model.id);
        defer allocator.free(sanitized_model);
        try writer.print("            .{s} => .{s},\n", .{ sanitized_model, @tagName(model.type) });
    }
    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n");

    try writer.writeAll("};\n");
}

fn sanitizeModelName(allocator: std.mem.Allocator, model: []const u8) ![]u8 {
    var sanitized = std.ArrayList(u8).init(allocator);
    defer sanitized.deinit();

    for (model) |char| {
        switch (char) {
            'a'...'z', 'A'...'Z', '0'...'9', '_' => try sanitized.append(char),
            '-', '.', '/' => try sanitized.append('_'),
            else => {},
        }
    }

    return sanitized.toOwnedSlice();
}

fn getModelsForProvider(provider_name: []const u8) []const ModelInfo {
    if (std.mem.eql(u8, provider_name, "OpenAI")) {
        return &[_]ModelInfo{
            .{ .id = "gpt-3.5-turbo", .type = .chat },
            .{ .id = "gpt-4", .type = .chat },
            .{ .id = "text-embedding-ada-002", .type = .embedding },
        };
    } else if (std.mem.eql(u8, provider_name, "OctoAI")) {
        return &[_]ModelInfo{
            .{ .id = "meta-llama-3.1-8b-instruct", .type = .chat },
            .{ .id = "mixtral-8x7b-instruct", .type = .chat },
        };
    } else if (std.mem.eql(u8, provider_name, "TogetherAI")) {
        return &[_]ModelInfo{
            .{ .id = "databricks/dbrx-instruct", .type = .chat },
            .{ .id = "meta-llama/Llama-3-8b-hf", .type = .completion },
        };
    } else if (std.mem.eql(u8, provider_name, "OpenRouter")) {
        return &[_]ModelInfo{
            .{ .id = "anthropic/claude-3.5-sonnet", .type = .chat },
            .{ .id = "meta-llama/llama-3.1-405b", .type = .completion },
        };
    } else {
        @panic("Unknown provider");
    }
}
