// This file is auto-generated. Do not edit manually.

const std = @import("std");
const providers = @import("../providers.zig");

pub const info = providers.ProviderInfo{
    .base_url = "https://text.octoai.run/v1",
    .api_key_env_var = "OCTOAI_TOKEN",
    .supported_model_types = &[_]providers.ModelType{ .chat, .embedding },
};

pub const Models = struct {
    pub fn gte_large() providers.ModelInfo {
        return .{
            .display_name = "GTE Large",
            .name = "gte_large",
            .id = "thenlper/gte-large",
            .type = .embedding,
            .cost_per_million_tokens = 0.05,
            .max_token_length = 8192,
        };
    }
    pub fn mistral_7b_instruct() providers.ModelInfo {
        return .{
            .display_name = "Mistral 7B Instruct",
            .name = "mistral_7b_instruct",
            .id = "mistral-7b-instruct",
            .type = .chat,
            .cost_per_million_tokens = 0.15,
            .max_token_length = 32768,
        };
    }
    pub fn wizardlm_2_8x22b() providers.ModelInfo {
        return .{
            .display_name = "WizardLM 2 8x22B",
            .name = "wizardlm_2_8x22b",
            .id = "wizardlm-2-8x22b",
            .type = .chat,
            .cost_per_million_tokens = 1.2,
            .max_token_length = 65536,
        };
    }
    pub fn mixtral_8x7b_instruct() providers.ModelInfo {
        return .{
            .display_name = "Mixtral 8x7B Instruct",
            .name = "mixtral_8x7b_instruct",
            .id = "mixtral-8x7b-instruct",
            .type = .chat,
            .cost_per_million_tokens = 0.45,
            .max_token_length = 32768,
        };
    }
    pub fn mixtral_8x22b_instruct() providers.ModelInfo {
        return .{
            .display_name = "Mixtral 8x22B Instruct",
            .name = "mixtral_8x22b_instruct",
            .id = "mixtral-8x22b-instruct",
            .type = .chat,
            .cost_per_million_tokens = 1.2,
            .max_token_length = 65536,
        };
    }
    pub fn meta_llama_3_1_8b_instruct() providers.ModelInfo {
        return .{
            .display_name = "Meta LLaMa 3.1 8B Instruct",
            .name = "meta_llama_3_1_8b_instruct",
            .id = "meta-llama-3.1-8b-instruct",
            .type = .chat,
            .cost_per_million_tokens = 0.15,
            .max_token_length = 131072,
        };
    }
    pub fn meta_llama_3_1_70b_instruct() providers.ModelInfo {
        return .{
            .display_name = "Meta LLaMa 3.1 70B Instruct",
            .name = "meta_llama_3_1_70b_instruct",
            .id = "meta-llama-3.1-70b-instruct",
            .type = .chat,
            .cost_per_million_tokens = 0.9,
            .max_token_length = 131072,
        };
    }
    pub fn meta_llama_3_1_405b_instruct() providers.ModelInfo {
        return .{
            .display_name = "Meta LLaMa 3.1 405B Instruct",
            .name = "meta_llama_3_1_405b_instruct",
            .id = "meta-llama-3.1-405b-instruct",
            .type = .chat,
            .cost_per_million_tokens = 3,
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
