const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("core.zig");
const config = @import("config.zig");
const Provider = @import("providers.zig").Provider;
const ProviderConfig = config.ProviderConfig;

pub const RegistryError = error{
    ProviderNotFound,
    ModelNotFound,
    PromptNotFound,
    ProviderAlreadyExists,
    ModelAlreadyExists,
    PromptAlreadyExists,
    ProviderNotInitialized,
    InvalidConfiguration,
    OutOfMemory,
} || Provider.Error;

pub const SerializationError = error{
    InvalidJson,
    MissingRequiredField,
    InvalidProviderType,
    InvalidCapability,
    InvalidPromptType,
    FileError,
    ProviderAlreadyExists,
    PromptAlreadyExists,
} || std.json.ParseFromValueError || Allocator.Error;

pub const Capability = enum {
    chat,
    completion,
    embedding,

    pub fn jsonStringify(self: @This(), serializer: anytype) !void {
        try serializer.write(@tagName(self));
    }
};

pub const PromptType = enum {
    system,
    user,
    
    pub fn jsonStringify(self: @This(), serializer: anytype) !void {
        try serializer.write(@tagName(self));
    }
};

pub const Prompt = struct {
    name: []const u8,
    type: PromptType,
    content: []const u8,
    
    pub fn jsonStringify(self: @This(), serializer: anytype) !void {
        try serializer.beginObject();
        try serializer.objectField("name");
        try serializer.write(self.name);
        try serializer.objectField("type");
        try serializer.write(@tagName(self.type));
        try serializer.objectField("content");
        try serializer.write(self.content);
        try serializer.endObject();
    }
};

pub const ModelSpec = struct {
    name: []const u8,
    id: []const u8,
    capabilities: std.EnumSet(Capability),
    default_prompt_name: ?[]const u8 = null,

    pub fn jsonStringify(self: @This(), serializer: anytype) !void {
        try serializer.beginObject();
        try serializer.objectField("name");
        try serializer.write(self.name);
        try serializer.objectField("id");
        try serializer.write(self.id);
        try serializer.objectField("capabilities");
        try serializer.beginArray();
        var first = true;
        inline for (std.meta.fields(Capability)) |field| {
            if (self.capabilities.contains(@field(Capability, field.name))) {
                if (!first) try serializer.write(",");
                try serializer.write(field.name);
                first = false;
            }
        }
        try serializer.endArray();
        
        if (self.default_prompt_name) |prompt_name| {
            try serializer.objectField("default_prompt_name");
            try serializer.write(prompt_name);
        }
        
        try serializer.endObject();
    }
};

pub const ProviderSpec = struct {
    name: []const u8,
    config: ProviderConfig,
    instance: ?*Provider,
    models: []ModelSpec,

    pub fn findModel(self: ProviderSpec, name: []const u8) ?ModelSpec {
        for (self.models) |model| {
            if (std.mem.eql(u8, model.name, name)) {
                return model;
            }
        }
        return null;
    }

    pub fn jsonStringify(self: @This(), serializer: anytype) !void {
        try serializer.beginObject();
        try serializer.objectField("name");
        try serializer.write(self.name);
        try serializer.objectField("config");
        try self.config.jsonStringify(serializer);
        try serializer.objectField("models");
        try serializer.write(self.models);
        try serializer.endObject();
    }
};

pub const Registry = struct {
    allocator: Allocator,
    providers: std.ArrayList(ProviderSpec),
    prompts: std.ArrayList(Prompt),

    pub fn init(allocator: Allocator) Registry {
        return .{
            .allocator = allocator,
            .providers = std.ArrayList(ProviderSpec).init(allocator),
            .prompts = std.ArrayList(Prompt).init(allocator),
        };
    }

    pub fn deinit(self: *Registry) void {
        // Clean up providers
        for (self.providers.items) |*provider| {
            if (provider.instance) |instance| {
                instance.deinit();
                self.allocator.destroy(instance);
            }
            self.allocator.free(provider.name);

            // Free provider config fields based on type
            switch (provider.config) {
                .OpenAI => |*openai_config| {
                    self.allocator.free(openai_config.api_key);
                    self.allocator.free(openai_config.base_url);
                    if (openai_config.organization) |org| {
                        self.allocator.free(org);
                    }
                },
                .AmazonBedrock => |*amazon_config| {
                    self.allocator.free(amazon_config.access_key_id);
                    self.allocator.free(amazon_config.secret_access_key);
                    self.allocator.free(amazon_config.region);
                },
                .Anthropic => |*anthropic_config| {
                    self.allocator.free(anthropic_config.api_key);
                },
                .GoogleVertex => |*google_config| {
                    self.allocator.free(google_config.api_key);
                    self.allocator.free(google_config.project_id);
                    self.allocator.free(google_config.location);
                },
                .Local => |*local_config| {
                    self.allocator.free(local_config.runtime);
                },
            }

            // Free all model fields
            for (provider.models) |*model| {
                self.allocator.free(model.name);
                self.allocator.free(model.id);
                if (model.default_prompt_name) |prompt_name| {
                    self.allocator.free(prompt_name);
                }
            }
            self.allocator.free(provider.models);
        }
        self.providers.deinit();
        
        // Clean up prompts
        for (self.prompts.items) |*prompt| {
            self.allocator.free(prompt.name);
            self.allocator.free(prompt.content);
        }
        self.prompts.deinit();
    }

    fn parseModelSpec(allocator: Allocator, json: std.json.Value) !ModelSpec {
        const obj = json.object;
        const name = obj.get("name") orelse return error.MissingRequiredField;
        const id = obj.get("id") orelse return error.MissingRequiredField;
        const capabilities_array = obj.get("capabilities") orelse return error.MissingRequiredField;

        // Allocate name first
        const name_dup = try allocator.dupe(u8, name.string);
        errdefer allocator.free(name_dup);

        // Allocate id next
        const id_dup = try allocator.dupe(u8, id.string);
        errdefer allocator.free(id_dup);
        
        // Check for optional default_prompt_name
        var default_prompt_name_dup: ?[]const u8 = null;
        errdefer if (default_prompt_name_dup) |p| allocator.free(p);
        
        if (obj.get("default_prompt_name")) |prompt_name| {
            default_prompt_name_dup = try allocator.dupe(u8, prompt_name.string);
        }

        var cap_set = std.EnumSet(Capability){};
        for (capabilities_array.array.items) |cap_value| {
            if (std.meta.stringToEnum(Capability, cap_value.string)) |cap| {
                cap_set.insert(cap);
            } else {
                return error.InvalidCapability;
            }
        }

        return ModelSpec{
            .name = name_dup,
            .id = id_dup,
            .capabilities = cap_set,
            .default_prompt_name = default_prompt_name_dup,
        };
    }

    fn parsePrompt(allocator: Allocator, json: std.json.Value) !Prompt {
        const obj = json.object;
        const name = obj.get("name") orelse return error.MissingRequiredField;
        const type_str = obj.get("type") orelse return error.MissingRequiredField;
        const content = obj.get("content") orelse return error.MissingRequiredField;
        
        // Allocate name first
        const name_dup = try allocator.dupe(u8, name.string);
        errdefer allocator.free(name_dup);
        
        // Check prompt type
        const prompt_type = std.meta.stringToEnum(PromptType, type_str.string) orelse 
            return error.InvalidPromptType;
        
        // Allocate content
        const content_dup = try allocator.dupe(u8, content.string);
        errdefer allocator.free(content_dup);
        
        return Prompt{
            .name = name_dup,
            .type = prompt_type,
            .content = content_dup,
        };
    }
    
    fn parseProviderConfig(allocator: Allocator, config_type: []const u8, json_obj: std.json.ObjectMap) SerializationError!ProviderConfig {
        if (std.mem.eql(u8, config_type, "openai")) {
            const api_key = json_obj.get("api_key") orelse return error.MissingRequiredField;
            const base_url = json_obj.get("base_url") orelse return error.MissingRequiredField;

            var api_key_dup: ?[]const u8 = null;
            var base_url_dup: ?[]const u8 = null;
            var organization_dup: ?[]const u8 = null;
            errdefer {
                if (api_key_dup) |key| allocator.free(key);
                if (base_url_dup) |url| allocator.free(url);
                if (organization_dup) |org| allocator.free(org);
            }

            api_key_dup = try allocator.dupe(u8, api_key.string);
            errdefer allocator.free(api_key_dup.?);

            base_url_dup = try allocator.dupe(u8, base_url.string);
            errdefer allocator.free(base_url_dup.?);

            organization_dup = if (json_obj.get("organization")) |org|
                try allocator.dupe(u8, org.string)
            else
                null;

            return ProviderConfig{ .OpenAI = .{
                .api_key = api_key_dup.?,
                .base_url = base_url_dup.?,
                .organization = organization_dup,
            } };
        } else if (std.mem.eql(u8, config_type, "amazon_bedrock")) {
            const access_key_id = json_obj.get("access_key_id") orelse return error.MissingRequiredField;
            const secret_access_key = json_obj.get("secret_access_key") orelse return error.MissingRequiredField;
            const region = json_obj.get("region") orelse return error.MissingRequiredField;

            var access_key_id_dup: ?[]const u8 = null;
            var secret_access_key_dup: ?[]const u8 = null;
            var region_dup: ?[]const u8 = null;
            errdefer {
                if (access_key_id_dup) |key| allocator.free(key);
                if (secret_access_key_dup) |key| allocator.free(key);
                if (region_dup) |r| allocator.free(r);
            }

            access_key_id_dup = try allocator.dupe(u8, access_key_id.string);
            errdefer allocator.free(access_key_id_dup.?);

            secret_access_key_dup = try allocator.dupe(u8, secret_access_key.string);
            errdefer allocator.free(secret_access_key_dup.?);

            region_dup = try allocator.dupe(u8, region.string);
            errdefer allocator.free(region_dup.?);

            return ProviderConfig{ .AmazonBedrock = .{
                .access_key_id = access_key_id_dup.?,
                .secret_access_key = secret_access_key_dup.?,
                .region = region_dup.?,
            } };
        } else if (std.mem.eql(u8, config_type, "anthropic")) {
            const api_key = json_obj.get("api_key") orelse return error.MissingRequiredField;
            const default_max_tokens_json = json_obj.get("default_max_tokens") orelse return error.MissingRequiredField;
            
            // Check that default_max_tokens is a number
            const default_max_tokens = switch (default_max_tokens_json) {
                .integer => @as(u32, @intCast(default_max_tokens_json.integer)),
                else => return error.MissingRequiredField, 
            };

            var api_key_dup: ?[]const u8 = null;
            errdefer {
                if (api_key_dup) |key| allocator.free(key);
            }

            api_key_dup = try allocator.dupe(u8, api_key.string);
            errdefer allocator.free(api_key_dup.?);

            return ProviderConfig{ .Anthropic = .{
                .api_key = api_key_dup.?,
                .default_max_tokens = default_max_tokens,
            } };
        } else if (std.mem.eql(u8, config_type, "google_vertex")) {
            const api_key = json_obj.get("api_key") orelse return error.MissingRequiredField;
            const project_id = json_obj.get("project_id") orelse return error.MissingRequiredField;
            const location = json_obj.get("location") orelse return error.MissingRequiredField;

            var api_key_dup: ?[]const u8 = null;
            var project_id_dup: ?[]const u8 = null;
            var location_dup: ?[]const u8 = null;
            errdefer {
                if (api_key_dup) |key| allocator.free(key);
                if (project_id_dup) |id| allocator.free(id);
                if (location_dup) |loc| allocator.free(loc);
            }

            api_key_dup = try allocator.dupe(u8, api_key.string);
            errdefer allocator.free(api_key_dup.?);

            project_id_dup = try allocator.dupe(u8, project_id.string);
            errdefer allocator.free(project_id_dup.?);

            location_dup = try allocator.dupe(u8, location.string);
            errdefer allocator.free(location_dup.?);

            return ProviderConfig{ .GoogleVertex = .{
                .api_key = api_key_dup.?,
                .project_id = project_id_dup.?,
                .location = location_dup.?,
            } };
        } else if (std.mem.eql(u8, config_type, "local")) {
            const runtime = json_obj.get("runtime") orelse return error.MissingRequiredField;

            var runtime_dup: ?[]const u8 = null;
            errdefer if (runtime_dup) |r| allocator.free(r);

            runtime_dup = try allocator.dupe(u8, runtime.string);
            errdefer allocator.free(runtime_dup.?);

            return ProviderConfig{ .Local = .{
                .runtime = runtime_dup.?,
            } };
        }

        return error.InvalidProviderType;
    }

    pub fn saveToFile(self: *Registry, path: []const u8) SerializationError!void {
        var file = std.fs.cwd().createFile(path, .{}) catch |err| switch (err) {
            error.AccessDenied => return SerializationError.FileError,
            error.PathAlreadyExists => return SerializationError.FileError,
            error.NoSpaceLeft => return SerializationError.FileError,
            else => return SerializationError.FileError,
        };
        defer file.close();

        const wrapper = struct {
            providers: []const ProviderSpec,
            prompts: []const Prompt,

            pub fn jsonStringify(data: @This(), serializer: anytype) !void {
                try serializer.beginObject();
                try serializer.objectField("providers");
                try serializer.write(data.providers);
                try serializer.objectField("prompts");
                try serializer.write(data.prompts);
                try serializer.endObject();
            }
        }{ 
            .providers = self.providers.items,
            .prompts = self.prompts.items,
        };

        std.json.stringify(wrapper, .{ .whitespace = .indent_2 }, file.writer()) catch |err| switch (err) {
            else => return SerializationError.FileError,
        };
    }

    pub fn loadFromFile(allocator: Allocator, path: []const u8) SerializationError!Registry {
        const file_content = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return SerializationError.FileError,
            error.IsDir => return SerializationError.FileError,
            error.AccessDenied => return SerializationError.FileError,
            error.SystemResources => return SerializationError.FileError,
            else => return SerializationError.FileError,
        };
        defer allocator.free(file_content);

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, file_content, .{}) catch |err| switch (err) {
            else => return SerializationError.InvalidJson,
        };
        defer parsed.deinit();

        var registry = Registry.init(allocator);
        errdefer registry.deinit();

        // Load prompts if they exist
        if (parsed.value.object.get("prompts")) |prompts_array| {
            for (prompts_array.array.items) |prompt_value| {
                const prompt = try parsePrompt(allocator, prompt_value);
                try registry.prompts.append(prompt);
            }
        }

        // Load providers
        const providers_array = parsed.value.object.get("providers") orelse
            return error.MissingRequiredField;

        for (providers_array.array.items) |provider_value| {
            const provider = provider_value.object;
            const name = provider.get("name") orelse return error.MissingRequiredField;
            const config_obj = provider.get("config") orelse return error.MissingRequiredField;
            const type_value = config_obj.object.get("type") orelse return error.MissingRequiredField;

            var provider_config = try parseProviderConfig(allocator, type_value.string, config_obj.object);
            defer {
                switch (provider_config) {
                    .OpenAI => |*openai_config| {
                        allocator.free(openai_config.api_key);
                        allocator.free(openai_config.base_url);
                        if (openai_config.organization) |org| allocator.free(org);
                    },
                    .AmazonBedrock => |*amazon_config| {
                        allocator.free(amazon_config.access_key_id);
                        allocator.free(amazon_config.secret_access_key);
                        allocator.free(amazon_config.region);
                    },
                    .Anthropic => |*anthropic_config| {
                        allocator.free(anthropic_config.api_key);
                    },
                    .GoogleVertex => |*google_config| {
                        allocator.free(google_config.api_key);
                        allocator.free(google_config.project_id);
                        allocator.free(google_config.location);
                    },
                    .Local => |*local_config| {
                        allocator.free(local_config.runtime);
                    },
                }
            }

            const models_array = provider.get("models") orelse return error.MissingRequiredField;
            var models = try allocator.alloc(ModelSpec, models_array.array.items.len);
            errdefer allocator.free(models);

            // Track successful model parses for cleanup
            var successful_models: usize = 0;
            errdefer {
                for (models[0..successful_models]) |*model| {
                    allocator.free(model.name);
                    allocator.free(model.id);
                    if (model.default_prompt_name) |p| allocator.free(p);
                }
            }

            for (models_array.array.items, 0..) |model_value, i| {
                models[i] = try parseModelSpec(allocator, model_value);
                successful_models += 1;
            }

            // Create the provider - this will duplicate the models array
            try registry.createProvider(name.string, provider_config, models);

            // Free the original models array and its contents since createProvider made copies
            for (models) |*model| {
                allocator.free(model.name);
                allocator.free(model.id);
                if (model.default_prompt_name) |p| allocator.free(p);
            }
            allocator.free(models);
        }

        return registry;
    }

    pub fn getProvider(self: *Registry, name: []const u8) ?*ProviderSpec {
        for (self.providers.items) |*provider| {
            if (std.mem.eql(u8, provider.name, name)) {
                return provider;
            }
        }
        return null;
    }

    pub fn getModel(self: *Registry, provider_name: []const u8, model_name: []const u8) ?ModelSpec {
        if (self.getProvider(provider_name)) |provider| {
            return provider.findModel(model_name);
        }
        return null;
    }
    
    pub fn getPrompt(self: *Registry, name: []const u8) ?*Prompt {
        for (self.prompts.items) |*prompt| {
            if (std.mem.eql(u8, prompt.name, name)) {
                return prompt;
            }
        }
        return null;
    }
    
    pub fn createPrompt(
        self: *Registry,
        name: []const u8,
        prompt_type: PromptType,
        content: []const u8,
    ) !void {
        // Check for existing prompt first
        if (self.getPrompt(name) != null) {
            return error.PromptAlreadyExists;
        }
        
        // Duplicate name
        const name_dup = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_dup);
        
        // Duplicate content
        const content_dup = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(content_dup);
        
        try self.prompts.append(.{
            .name = name_dup,
            .type = prompt_type,
            .content = content_dup,
        });
    }
    
    pub fn updatePrompt(
        self: *Registry,
        name: []const u8,
        prompt_type: PromptType,
        content: []const u8,
    ) !void {
        const prompt = self.getPrompt(name) orelse return error.PromptNotFound;
        
        // Create duplicate of new content first
        const content_dup = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(content_dup);
        
        // Free the old content
        self.allocator.free(prompt.content);
        
        // Update the prompt
        prompt.type = prompt_type;
        prompt.content = content_dup;
    }
    
    pub fn deletePrompt(self: *Registry, name: []const u8) !void {
        var found_index: ?usize = null;
        
        for (self.prompts.items, 0..) |prompt, i| {
            if (std.mem.eql(u8, prompt.name, name)) {
                found_index = i;
                break;
            }
        }
        
        const index = found_index orelse return error.PromptNotFound;
        
        // Free the prompt resources
        const prompt = self.prompts.items[index];
        self.allocator.free(prompt.name);
        self.allocator.free(prompt.content);
        
        // Remove from the list
        _ = self.prompts.orderedRemove(index);
    }

    pub fn createProvider(
        self: *Registry,
        name: []const u8,
        provider_config: ProviderConfig,
        models: []const ModelSpec,
    ) !void {
        // Check for existing provider first to avoid unnecessary allocations
        if (self.getProvider(name) != null) {
            return error.ProviderAlreadyExists;
        }

        // Create a new array for the models
        var models_dup = try self.allocator.alloc(ModelSpec, models.len);
        errdefer self.allocator.free(models_dup);

        // Track successful duplications for cleanup
        var successful_dups: usize = 0;
        errdefer {
            for (models_dup[0..successful_dups]) |*model| {
                self.allocator.free(model.name);
                self.allocator.free(model.id);
                if (model.default_prompt_name) |p| self.allocator.free(p);
            }
        }

        // Copy each model
        for (models, 0..) |model, i| {
            const model_name = try self.allocator.dupe(u8, model.name);
            errdefer self.allocator.free(model_name);

            const model_id = try self.allocator.dupe(u8, model.id);
            errdefer self.allocator.free(model_id);
            
            var default_prompt_name_dup: ?[]const u8 = null;
            if (model.default_prompt_name) |prompt_name| {
                default_prompt_name_dup = try self.allocator.dupe(u8, prompt_name);
                errdefer if (default_prompt_name_dup) |p| self.allocator.free(p);
            }

            models_dup[i] = .{
                .name = model_name,
                .id = model_id,
                .capabilities = model.capabilities,
                .default_prompt_name = default_prompt_name_dup,
            };
            successful_dups += 1;
        }

        // Duplicate provider config
        const config_dup = switch (provider_config) {
            .OpenAI => |openai_config| blk: {
                const api_key = try self.allocator.dupe(u8, openai_config.api_key);
                errdefer self.allocator.free(api_key);

                const base_url = try self.allocator.dupe(u8, openai_config.base_url);
                errdefer self.allocator.free(base_url);

                const organization = if (openai_config.organization) |org|
                    try self.allocator.dupe(u8, org)
                else
                    null;
                errdefer if (organization) |org| self.allocator.free(org);

                break :blk ProviderConfig{ .OpenAI = .{
                    .api_key = api_key,
                    .base_url = base_url,
                    .organization = organization,
                } };
            },
            .AmazonBedrock => |amazon_config| blk: {
                const access_key_id = try self.allocator.dupe(u8, amazon_config.access_key_id);
                errdefer self.allocator.free(access_key_id);

                const secret_access_key = try self.allocator.dupe(u8, amazon_config.secret_access_key);
                errdefer self.allocator.free(secret_access_key);

                const region = try self.allocator.dupe(u8, amazon_config.region);
                errdefer self.allocator.free(region);

                break :blk ProviderConfig{ .AmazonBedrock = .{
                    .access_key_id = access_key_id,
                    .secret_access_key = secret_access_key,
                    .region = region,
                } };
            },
            .Anthropic => |anthropic_config| blk: {
                const api_key = try self.allocator.dupe(u8, anthropic_config.api_key);
                errdefer self.allocator.free(api_key);

                break :blk ProviderConfig{ .Anthropic = .{
                    .api_key = api_key,
                    .default_max_tokens = anthropic_config.default_max_tokens,
                } };
            },
            .GoogleVertex => |google_config| blk: {
                const api_key = try self.allocator.dupe(u8, google_config.api_key);
                errdefer self.allocator.free(api_key);

                const project_id = try self.allocator.dupe(u8, google_config.project_id);
                errdefer self.allocator.free(project_id);

                const location = try self.allocator.dupe(u8, google_config.location);
                errdefer self.allocator.free(location);

                break :blk ProviderConfig{ .GoogleVertex = .{
                    .api_key = api_key,
                    .project_id = project_id,
                    .location = location,
                } };
            },
            .Local => |local_config| blk: {
                const runtime = try self.allocator.dupe(u8, local_config.runtime);
                errdefer self.allocator.free(runtime);

                break :blk ProviderConfig{ .Local = .{
                    .runtime = runtime,
                } };
            },
        };
        errdefer switch (config_dup) {
            .OpenAI => |*openai_config| {
                self.allocator.free(openai_config.api_key);
                self.allocator.free(openai_config.base_url);
                if (openai_config.organization) |org| self.allocator.free(org);
            },
            .AmazonBedrock => |*amazon_config| {
                self.allocator.free(amazon_config.access_key_id);
                self.allocator.free(amazon_config.secret_access_key);
                self.allocator.free(amazon_config.region);
            },
            .Anthropic => |*anthropic_config| {
                self.allocator.free(anthropic_config.api_key);
            },
            .GoogleVertex => |*google_config| {
                self.allocator.free(google_config.api_key);
                self.allocator.free(google_config.project_id);
                self.allocator.free(google_config.location);
            },
            .Local => |*local_config| {
                self.allocator.free(local_config.runtime);
            },
        };

        // Duplicate the name last, after all other allocations succeed
        const name_dup = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_dup);

        try self.providers.append(.{
            .name = name_dup,
            .config = config_dup,
            .instance = null,
            .models = models_dup,
        });
    }

    pub fn initProvider(self: *Registry, name: []const u8) !void {
        const provider = self.getProvider(name) orelse return error.ProviderNotFound;
        if (provider.instance == null) {
            const instance_ptr = try self.allocator.create(Provider);
            errdefer self.allocator.destroy(instance_ptr);
            instance_ptr.* = try Provider.init(self.allocator, provider.config);
            provider.instance = instance_ptr;
        }
    }

    pub fn deinitProvider(self: *Registry, name: []const u8) !void {
        const provider = self.getProvider(name) orelse return error.ProviderNotFound;
        if (provider.instance) |instance| {
            instance.deinit();
            self.allocator.destroy(instance);
            provider.instance = null;
        }
    }
    
    pub fn setModelDefaultPrompt(
        self: *Registry,
        provider_name: []const u8,
        model_name: []const u8,
        prompt_name: ?[]const u8,
    ) !void {
        // Find the provider
        const provider = self.getProvider(provider_name) orelse return error.ProviderNotFound;
        
        // Find the model
        var model: ?*ModelSpec = null;
        for (provider.models) |*m| {
            if (std.mem.eql(u8, m.name, model_name)) {
                model = m;
                break;
            }
        }
        
        if (model == null) return error.ModelNotFound;
        
        // If we're setting to null, just clear the current value
        if (prompt_name == null) {
            if (model.?.default_prompt_name) |current_name| {
                self.allocator.free(current_name);
                model.?.default_prompt_name = null;
            }
            return;
        }
        
        // Check that the prompt exists
        if (self.getPrompt(prompt_name.?) == null) return error.PromptNotFound;
        
        // If there's already a prompt name, free it
        if (model.?.default_prompt_name) |current_name| {
            self.allocator.free(current_name);
        }
        
        // Set the new prompt name
        model.?.default_prompt_name = try self.allocator.dupe(u8, prompt_name.?);
    }
    
    pub fn getModelDefaultPrompt(
        self: *Registry,
        provider_name: []const u8,
        model_name: []const u8,
    ) !?*Prompt {
        if (self.getModel(provider_name, model_name)) |model| {
            if (model.default_prompt_name) |prompt_name| {
                return self.getPrompt(prompt_name) orelse return error.PromptNotFound;
            }
            return null;
        }
        return error.ModelNotFound;
    }
};
