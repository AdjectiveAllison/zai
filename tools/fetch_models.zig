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

    var file = try std.fs.cwd().createFile("src/providers.zig", .{});
    defer file.close();

    var writer = file.writer();

    try writer.writeAll("// This file is auto-generated. Do not edit manually.\n\n");
    try writer.writeAll("const std = @import(\"std\");\n\n");
    try writer.writeAll("pub const ModelType = enum { chat, completion, embedding };\n\n");

    try writer.writeAll("pub const Providers = struct {\n");

    inline for (std.meta.fields(Providers)) |provider_field| {
        const provider = @field(Providers, provider_field.name);
        const info = provider.getInfo();

        try writer.print("    pub const {s} = struct {{\n", .{provider_field.name});
        try writer.print("        pub const name = \"{s}\";\n", .{info.name});
        try writer.print("        pub const base_url = \"{s}\";\n", .{info.base_url});
        try writer.print("        pub const api_key_env_var = \"{s}\";\n", .{info.api_key_env_var});
        try writer.print("        pub const models_endpoint = \"{s}\";\n\n", .{info.models_endpoint});

        try writer.writeAll("        pub const Model = enum {\n");
        const models = getModelsForProvider(info.name);
        for (models) |model| {
            const sanitized_model = try sanitizeModelName(allocator, model.id);
            defer allocator.free(sanitized_model);
            try writer.print("            {s},\n", .{sanitized_model});
        }
        try writer.writeAll("\n");

        try writer.writeAll("            pub fn toId(self: Model) []const u8 {\n");
        try writer.writeAll("                return switch (self) {\n");
        for (models) |model| {
            const sanitized_model = try sanitizeModelName(allocator, model.id);
            defer allocator.free(sanitized_model);
            try writer.print("                    .{s} => \"{s}\",\n", .{ sanitized_model, model.id });
        }
        try writer.writeAll("                };\n");
        try writer.writeAll("            }\n\n");

        try writer.writeAll("            pub fn getType(self: Model) ModelType {\n");
        try writer.writeAll("                return switch (self) {\n");
        for (models) |model| {
            const sanitized_model = try sanitizeModelName(allocator, model.id);
            defer allocator.free(sanitized_model);
            try writer.print("                    .{s} => .{s},\n", .{ sanitized_model, @tagName(model.type) });
        }
        try writer.writeAll("                };\n");
        try writer.writeAll("            }\n");
        try writer.writeAll("        };\n\n");

        try writer.writeAll("        pub fn modelFromString(model_name: []const u8) ?Model {\n");
        try writer.writeAll("            return std.meta.stringToEnum(Model, model_name);\n");
        try writer.writeAll("        }\n");

        try writer.writeAll("    };\n\n");
    }

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
