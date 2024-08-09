// This file is auto-generated. Do not edit manually.

const std = @import("std");
const providers = @import("../providers.zig");

pub const info = providers.ProviderInfo{
    .base_url = "https://api.openai.com/v1",
    .api_key_env_var = "OPENAI_API_KEY",
    .supported_model_types = &[_]providers.ModelType{ .chat, .completion, .embedding },
};

pub const Models = struct {
    pub fn gpt_3_5_turbo() providers.ModelInfo {
        return .{
            .display_name = "GPT-3.5 Turbo",
            .name = "gpt_3_5_turbo",
            .id = "gpt-3.5-turbo",
            .type = .chat,
        };
    }
    pub fn gpt_4() providers.ModelInfo {
        return .{
            .display_name = "GPT-4",
            .name = "gpt_4",
            .id = "gpt-4",
            .type = .chat,
        };
    }
    pub fn text_embedding_ada_002() providers.ModelInfo {
        return .{
            .display_name = "Text Embedding Ada 002",
            .name = "text_embedding_ada_002",
            .id = "text-embedding-ada-002",
            .type = .embedding,
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
