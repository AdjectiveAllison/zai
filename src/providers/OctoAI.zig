// This file is auto-generated. Do not edit manually.

const std = @import("std");
const providers = @import("../providers.zig");

pub const info = providers.ProviderInfo{
    .base_url = "https://text.octoai.run/v1",
    .api_key_env_var = "OCTO_API_KEY",
    .supported_model_types = &[_]providers.ModelType{ .chat, .embedding },
};

pub const Models = struct {
    pub fn meta_llama_3_1_8b_instruct() providers.ModelInfo {
        return .{
            .display_name = "Meta LLaMa 3.1 8B Instruct",
            .name = "meta_llama_3_1_8b_instruct",
            .id = "meta-llama-3.1-8b-instruct",
            .type = .chat,
        };
    }
    pub fn mixtral_8x7b_instruct() providers.ModelInfo {
        return .{
            .display_name = "Mixtral 8x7B Instruct",
            .name = "mixtral_8x7b_instruct",
            .id = "mixtral-8x7b-instruct",
            .type = .chat,
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
