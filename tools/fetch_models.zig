const std = @import("std");

const ModelType = enum { chat, completion, embedding };

const ProviderInfo = struct {
    name: []const u8,
    base_url: []const u8,
    api_key_env_var: []const u8,
    models_endpoint: []const u8,
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

    // Add this new section to write out the ProviderInfo struct
    try writer.writeAll("pub const ProviderInfo = struct {\n");
    try writer.writeAll("    name: []const u8,\n");
    try writer.writeAll("    base_url: []const u8,\n");
    try writer.writeAll("    api_key_env_var: []const u8,\n");
    try writer.writeAll("    models_endpoint: []const u8,\n");
    try writer.writeAll("};\n\n");

    try writer.writeAll("pub const Provider = struct {\n");
    try writer.writeAll("    name: []const u8,\n");
    try writer.writeAll("    base_url: []const u8,\n");
    try writer.writeAll("    api_key_env_var: []const u8,\n");
    try writer.writeAll("    models_endpoint: []const u8,\n");
    try writer.writeAll("    models: type,\n\n");

    try writer.writeAll("    pub fn init(comptime info: ProviderInfo, comptime model_enum: type) Provider {\n");
    try writer.writeAll("        return .{\n");
    try writer.writeAll("            .name = info.name,\n");
    try writer.writeAll("            .base_url = info.base_url,\n");
    try writer.writeAll("            .api_key_env_var = info.api_key_env_var,\n");
    try writer.writeAll("            .models_endpoint = info.models_endpoint,\n");
    try writer.writeAll("            .models = model_enum,\n");
    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n");
    try writer.writeAll("};\n\n");

    try writer.writeAll("pub const Providers = struct {\n");

    inline for (std.meta.fields(Providers)) |provider_field| {
        const provider = @field(Providers, provider_field.name);
        const info = provider.getInfo();

        // Write the models enum
        try writer.print("    pub const {s}Models = enum {{\n", .{provider_field.name});
        const models = getModelsForProvider(info.name);
        for (models) |model| {
            const sanitized_model = try sanitizeModelName(allocator, model);
            defer allocator.free(sanitized_model);
            try writer.print("        {s},\n", .{sanitized_model});
        }
        try writer.writeAll("    };\n\n");

        // Write the provider initialization
        try writer.print("    pub const {s} = Provider.init(.{{\n", .{provider_field.name});
        try writer.print("        .name = \"{s}\",\n", .{info.name});
        try writer.print("        .base_url = \"{s}\",\n", .{info.base_url});
        try writer.print("        .api_key_env_var = \"{s}\",\n", .{info.api_key_env_var});
        try writer.print("        .models_endpoint = \"{s}\",\n", .{info.models_endpoint});
        try writer.print("    }}, {s}Models);\n\n", .{provider_field.name});
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

fn getModelsForProvider(provider_name: []const u8) []const []const u8 {
    if (std.mem.eql(u8, provider_name, "OpenAI")) {
        return &[_][]const u8{ "gpt-3.5-turbo", "gpt-4", "text-embedding-ada-002" };
    } else if (std.mem.eql(u8, provider_name, "OctoAI")) {
        return &[_][]const u8{ "llama-7b-chat", "mistral-7b-instruct" };
    } else if (std.mem.eql(u8, provider_name, "TogetherAI")) {
        return &[_][]const u8{ "togethercomputer/llama-2-70b-chat", "togethercomputer/falcon-40b-instruct" };
    } else if (std.mem.eql(u8, provider_name, "OpenRouter")) {
        return &[_][]const u8{ "openai/gpt-3.5-turbo", "anthropic/claude-2" };
    } else {
        @panic("Unknown provider");
    }
}
