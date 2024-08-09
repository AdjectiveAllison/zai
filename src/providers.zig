// This file is auto-generated. Do not edit manually.

const std = @import("std");

pub const ModelType = enum { chat, completion, embedding };

pub const ProviderType = enum {
    OpenAI,
    OctoAI,
    TogetherAI,
    OpenRouter,
};

pub const Provider = struct {
    provider_type: ProviderType,
    name: []const u8,
    base_url: []const u8,
    api_key_env_var: []const u8,
    models_endpoint: []const u8,

    pub fn init(comptime provider_type: ProviderType) Provider {
        const info = switch (provider_type) {
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
        return .{
            .provider_type = provider_type,
            .name = info.name,
            .base_url = info.base_url,
            .api_key_env_var = info.api_key_env_var,
            .models_endpoint = info.models_endpoint,
        };
    }

    pub fn models(self: Provider) switch (self.provider_type) {
        .OpenAI => *const OpenAIModel,
        .OctoAI => *const OctoAIModel,
        .TogetherAI => *const TogetherAIModel,
        .OpenRouter => *const OpenRouterModel,
    } {
        return switch (self.provider_type) {
            .OpenAI => &open_ai_models,
            .OctoAI => &octo_ai_models,
            .TogetherAI => &together_ai_models,
            .OpenRouter => &open_router_models,
        };
    }

    pub const OpenAIModel = enum {
        gpt_3_5_turbo,
        gpt_4,
        text_embedding_ada_002,
    };

    pub const OctoAIModel = enum {
        meta_llama_3_1_8b_instruct,
        mixtral_8x7b_instruct,
    };

    pub const TogetherAIModel = enum {
        databricks_dbrx_instruct,
        meta_llama_Llama_3_8b_hf,
    };

    pub const OpenRouterModel = enum {
        anthropic_claude_3_5_sonnet,
        meta_llama_llama_3_1_405b,
    };

    const open_ai_models = OpenAIModel{};
    const octo_ai_models = OctoAIModel{};
    const together_ai_models = TogetherAIModel{};
    const open_router_models = OpenRouterModel{};

    pub fn modelFromString(self: Provider, model_name: []const u8) ?self.models() {
        return std.meta.stringToEnum(self.models(), model_name);
    }

    pub fn modelToId(self: Provider, model: self.models()) []const u8 {
        return switch (self.provider_type) {
            .OpenAI => switch (model) {
                .gpt_3_5_turbo => "gpt-3.5-turbo",
                .gpt_4 => "gpt-4",
                .text_embedding_ada_002 => "text-embedding-ada-002",
            },
            .OctoAI => switch (model) {
                .meta_llama_3_1_8b_instruct => "meta-llama-3.1-8b-instruct",
                .mixtral_8x7b_instruct => "mixtral-8x7b-instruct",
            },
            .TogetherAI => switch (model) {
                .databricks_dbrx_instruct => "databricks/dbrx-instruct",
                .meta_llama_Llama_3_8b_hf => "meta-llama/Llama-3-8b-hf",
            },
            .OpenRouter => switch (model) {
                .anthropic_claude_3_5_sonnet => "anthropic/claude-3.5-sonnet",
                .meta_llama_llama_3_1_405b => "meta-llama/llama-3.1-405b",
            },
        };
    }

    pub fn modelGetType(self: Provider, model: self.models()) ModelType {
        return switch (self.provider_type) {
            .OpenAI => switch (model) {
                .gpt_3_5_turbo => .chat,
                .gpt_4 => .chat,
                .text_embedding_ada_002 => .embedding,
            },
            .OctoAI => switch (model) {
                .meta_llama_3_1_8b_instruct => .chat,
                .mixtral_8x7b_instruct => .chat,
            },
            .TogetherAI => switch (model) {
                .databricks_dbrx_instruct => .chat,
                .meta_llama_Llama_3_8b_hf => .completion,
            },
            .OpenRouter => switch (model) {
                .anthropic_claude_3_5_sonnet => .chat,
                .meta_llama_llama_3_1_405b => .completion,
            },
        };
    }
};

pub const Providers = struct {
    pub const OpenAI = Provider.init(.OpenAI);
    pub const OctoAI = Provider.init(.OctoAI);
    pub const TogetherAI = Provider.init(.TogetherAI);
    pub const OpenRouter = Provider.init(.OpenRouter);
};
