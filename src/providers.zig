// This file is auto-generated. Do not edit manually.

const std = @import("std");

pub const Provider = enum {
    OpenAI,
    OctoAI,
    TogetherAI,
    OpenRouter,
};

pub const ModelType = enum { chat, completion, embedding };

pub const ProviderInfo = struct {
    base_url: []const u8,
    api_key_env_var: []const u8,
    supported_model_types: []const ModelType,
};

pub const ModelInfo = struct {
    display_name: []const u8,
    name: []const u8,
    id: []const u8,
    type: ModelType,
};

pub const OpenAI = @import("providers/OpenAI.zig");
pub const OctoAI = @import("providers/OctoAI.zig");
pub const TogetherAI = @import("providers/TogetherAI.zig");
pub const OpenRouter = @import("providers/OpenRouter.zig");

pub fn getProviderInfo(provider: Provider) ProviderInfo {
    return switch (provider) {
        .OpenAI => OpenAI.info,
        .OctoAI => OctoAI.info,
        .TogetherAI => TogetherAI.info,
        .OpenRouter => OpenRouter.info,
    };
}

pub fn getModels(provider: Provider) []const ModelInfo {
    return switch (provider) {
        .OpenAI => OpenAI.getAllModels(),
        .OctoAI => OctoAI.getAllModels(),
        .TogetherAI => TogetherAI.getAllModels(),
        .OpenRouter => OpenRouter.getAllModels(),
    };
}