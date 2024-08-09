// This file is auto-generated. Do not edit manually.

const std = @import("std");
const providers = @import("../providers.zig");

pub const info = providers.ProviderInfo{
    .base_url = "https://api.together.xyz/v1",
    .api_key_env_var = "TOGETHER_API_KEY",
    .supported_model_types = &[_]providers.ModelType{ .chat, .completion, .embedding },
};

pub const Models = struct {
    pub fn databricks_dbrx_instruct() providers.ModelInfo {
        return .{
            .display_name = "Databricks DBRX Instruct",
            .name = "databricks_dbrx_instruct",
            .id = "databricks/dbrx-instruct",
            .type = .chat,
        };
    }
    pub fn meta_llama_Llama_3_8b_hf() providers.ModelInfo {
        return .{
            .display_name = "Meta LLaMa 3 8B HF",
            .name = "meta_llama_Llama_3_8b_hf",
            .id = "meta-llama/Llama-3-8b-hf",
            .type = .completion,
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
