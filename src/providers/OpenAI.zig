// This file is auto-generated. Do not edit manually.

const std = @import("std");
const providers = @import("../providers.zig");

pub const info = providers.ProviderInfo{
    .base_url = "https://api.openai.com/v1",
    .api_key_env_var = "OPENAI_API_KEY",
    .supported_model_types = &[_]providers.ModelType{ .chat, .completion, .embedding },
};

pub const Models = struct {
    pub fn gpt_4o() providers.ModelInfo {
        return .{
            .display_name = "GPT-4o",
            .name = "gpt_4o",
            .id = "gpt-4o",
            .type = .chat,
            .cost_per_million_tokens = 5,
            .max_token_length = 128000,
        };
    }
    pub fn gpt_4o_mini() providers.ModelInfo {
        return .{
            .display_name = "GPT-4o Mini",
            .name = "gpt_4o_mini",
            .id = "gpt-4o-mini",
            .type = .chat,
            .cost_per_million_tokens = 0.15,
            .max_token_length = 128000,
        };
    }
    pub fn gpt_4() providers.ModelInfo {
        return .{
            .display_name = "GPT-4",
            .name = "gpt_4",
            .id = "gpt-4",
            .type = .chat,
            .cost_per_million_tokens = 30,
            .max_token_length = 8192,
        };
    }
    pub fn gpt_4_turbo() providers.ModelInfo {
        return .{
            .display_name = "GPT-4 Turbo",
            .name = "gpt_4_turbo",
            .id = "gpt-4-turbo",
            .type = .chat,
            .cost_per_million_tokens = 10,
            .max_token_length = 128000,
        };
    }
    pub fn gpt_3_5_turbo() providers.ModelInfo {
        return .{
            .display_name = "GPT-3.5 Turbo",
            .name = "gpt_3_5_turbo",
            .id = "gpt-3.5-turbo",
            .type = .chat,
            .cost_per_million_tokens = 0.5,
            .max_token_length = 16385,
        };
    }
    pub fn gpt_3_5_turbo_instruct() providers.ModelInfo {
        return .{
            .display_name = "GPT-3.5 Turbo Instruct",
            .name = "gpt_3_5_turbo_instruct",
            .id = "gpt-3.5-turbo-instruct",
            .type = .completion,
            .cost_per_million_tokens = 1.5,
            .max_token_length = 4096,
        };
    }
    pub fn text_embedding_3_large() providers.ModelInfo {
        return .{
            .display_name = "Text Embedding 3 Large",
            .name = "text_embedding_3_large",
            .id = "text-embedding-3-large",
            .type = .embedding,
            .cost_per_million_tokens = 0.13,
            .max_token_length = 8191,
        };
    }
    pub fn text_embedding_3_small() providers.ModelInfo {
        return .{
            .display_name = "Text Embedding 3 Small",
            .name = "text_embedding_3_small",
            .id = "text-embedding-3-small",
            .type = .embedding,
            .cost_per_million_tokens = 0.02,
            .max_token_length = 8191,
        };
    }
    pub fn text_embedding_ada_002() providers.ModelInfo {
        return .{
            .display_name = "Text Embedding Ada 002",
            .name = "text_embedding_ada_002",
            .id = "text-embedding-ada-002",
            .type = .embedding,
            .cost_per_million_tokens = 0.1,
            .max_token_length = 8191,
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
