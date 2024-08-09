// This file is auto-generated. Do not edit manually.

const std = @import("std");
const providers = @import("../providers.zig");

pub const info = providers.ProviderInfo{
    .base_url = "https://openrouter.ai/api/v1",
    .api_key_env_var = "OPENROUTER_API_KEY",
    .supported_model_types = &[_]providers.ModelType{ .chat, .completion },
};

pub const Models = struct {
    pub fn anthropic_claude_3_5_sonnet() providers.ModelInfo {
        return .{
            .display_name = "Anthropic Claude 3.5 Sonnet",
            .name = "anthropic_claude_3_5_sonnet",
            .id = "anthropic/claude-3.5-sonnet",
            .type = .chat,
            .cost_per_million_tokens = 3,
            .max_token_length = 200000,
        };
    }
    pub fn meta_llama_llama_3_1_405b() providers.ModelInfo {
        return .{
            .display_name = "Meta LLaMa 3.1 405B base",
            .name = "meta_llama_llama_3_1_405b",
            .id = "meta-llama/llama-3.1-405b",
            .type = .completion,
            .cost_per_million_tokens = 2,
            .max_token_length = 131072,
        };
    }
};

pub fn getAllModels() []const providers.ModelInfo {
    const declarations = @typeInfo(Models).Struct.decls;

    var models: [declarations.len]providers.ModelInfo = undefined;
    comptime var i = 0;
    inline for (declarations) |declaration| {
        if (@TypeOf(@field(Models, declaration.name)) == fn () providers.ModelInfo) {
            models[i] = @field(Models, declaration.name)();
            i += 1;
        }
    }
    return models[0..i];
}
