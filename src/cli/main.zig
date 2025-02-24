const std = @import("std");
const zai = @import("zai");
const args = @import("args.zig");
const config_path = @import("config_path.zig");

fn printUsage() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll(
        \\Usage: zai <command> [options] [prompt]
        \\
        \\Commands:
        \\  chat         Start a chat with the AI
        \\  completion   Get a completion from the AI
        \\  embedding    Get embeddings for text
        \\  provider     Manage AI providers
        \\  models       Manage provider models
        \\
        \\Run 'zai <command> --help' for more information on a command.
        \\
    );
}

fn printChatHelp() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll(
        \\Usage: zai chat [options] <prompt>
        \\
        \\Start an interactive chat with the AI.
        \\
        \\Options:
        \\  --provider <name>         Select AI provider (default: first configured provider)
        \\  --system-message <msg>    Set system message for chat
        \\  --model <name>           Select specific model
        \\  --stream <bool>          Enable/disable streaming (default: true)
        \\
        \\Examples:
        \\  zai chat "What is the meaning of life?"
        \\  zai chat --provider openai "Tell me a joke"
        \\  zai chat --system-message "You are a helpful assistant" "Help me"
        \\  zai chat --model gpt-4 --stream false "What's the weather?"
        \\
    );
}

fn printCompletionHelp() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll(
        \\Usage: zai completion [options] <prompt>
        \\
        \\Get a completion from the AI.
        \\
        \\Options:
        \\  --provider <name>         Select AI provider (default: first configured provider)
        \\  --model <name>           Select specific model
        \\  --stream <bool>          Enable/disable streaming (default: true)
        \\
        \\Examples:
        \\  zai completion "The quick brown fox"
        \\  zai completion --provider openai "Once upon a time"
        \\  zai completion --model gpt-4 --stream false "Write a story about"
        \\
    );
}

fn printEmbeddingHelp() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll(
        \\Usage: zai embedding [options] <text>
        \\
        \\Generate embeddings for text.
        \\
        \\Options:
        \\  --provider <name>         Select AI provider (default: first configured provider)
        \\  --model <name>           Select specific model
        \\
        \\Examples:
        \\  zai embedding "The quick brown fox"
        \\  zai embedding --provider openai "Generate an embedding for this text"
        \\
    );
}

fn printProviderHelp() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll(
        \\Usage: zai provider <subcommand>
        \\
        \\Manage AI providers.
        \\
        \\Subcommands:
        \\  list                     List all configured providers
        \\  add                      Add a new provider
        \\  remove                   Remove a provider
        \\  set-default             Set the default provider
        \\
        \\Examples:
        \\  zai provider list
        \\  zai provider add openai
        \\  zai provider remove openai
        \\  zai provider set-default openai
        \\
    );
}

fn printModelsHelp() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll(
        \\Usage: zai models <subcommand>
        \\
        \\Manage provider models.
        \\
        \\Subcommands:
        \\  list                     List all models from all providers
        \\  add <provider> <name>    Add a model to a provider
        \\
        \\Options for add:
        \\  --id <id>               Model ID (required)
        \\  --chat                  Enable chat capability
        \\  --completion            Enable completion capability
        \\  --embedding             Enable embedding capability
        \\
        \\Examples:
        \\  zai models list
        \\  zai models add aws claude-3-opus --id anthropic.claude-3-opus-20240229 --chat
        \\  zai models add openai gpt-4 --id gpt-4 --chat --completion
        \\
    );
}

fn handleChat(allocator: std.mem.Allocator, provider: *zai.Provider, provider_name: []const u8, registry: *zai.Registry, options: args.ChatOptions) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Get model - either from options or try to find a default model with chat capability
    const model_id = if (options.model) |m| m else blk: {
        const provider_spec = registry.getProvider(provider_name) orelse {
            try stderr.writeAll("Provider specification not found.\n");
            return error.ProviderSpecNotFound;
        };

        // Find first model with chat capability
        for (provider_spec.models) |model| {
            if (model.capabilities.contains(.chat)) {
                break :blk model.id;
            }
        }

        try stderr.writeAll("No chat-capable models found for this provider.\n");
        try stderr.print("Please specify a model with --model or add a model with chat capability:\n  zai models add {s} <model_name> --id <model_id> --chat\n", .{provider_name});
        return error.NoChatModelsAvailable;
    };

    // Construct messages array
    var messages = std.ArrayList(zai.Message).init(allocator);
    defer messages.deinit();

    // Add system message if provided
    if (options.system_message) |system_msg| {
        try messages.append(.{
            .role = "system",
            .content = system_msg,
        });
    }

    // Add user message
    try messages.append(.{
        .role = "user",
        .content = options.prompt,
    });

    // Create chat options
    const chat_options = zai.ChatRequestOptions{
        .model = model_id,
        .messages = messages.items,
        .temperature = 0.7,
        .stream = options.stream,
    };

    if (options.stream) {
        try provider.chatStream(chat_options, stdout);
        try stdout.writeByte('\n');
    } else {
        const response = try provider.chat(chat_options);
        defer allocator.free(response);
        try stdout.print("{s}\n", .{response});
    }
}

fn handleProvider(allocator: std.mem.Allocator, cli_args: []const []const u8) !void {
    if (cli_args.len < 3) {
        try printProviderHelp();
        return;
    }

    const subcommand = cli_args[2];
    if (std.mem.eql(u8, subcommand, "list")) {
        const config_file = try config_path.getConfigPath(allocator);
        defer allocator.free(config_file);

        var registry = try zai.Registry.loadFromFile(allocator, config_file);
        defer registry.deinit();

        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll("Configured providers:\n");

        for (registry.providers.items) |provider| {
            try stdout.print("\n{s}:\n", .{provider.name});
            try stdout.writeAll("  Models:\n");
            for (provider.models) |model| {
                try stdout.print("    - {s} ({s})\n", .{ model.name, model.id });
                try stdout.writeAll("      Capabilities: ");
                var first = true;
                inline for (std.meta.fields(zai.registry.Capability)) |field| {
                    if (model.capabilities.contains(@field(zai.registry.Capability, field.name))) {
                        if (!first) try stdout.writeAll(", ");
                        try stdout.writeAll(field.name);
                        first = false;
                    }
                }
                try stdout.writeByte('\n');
            }
        }
    } else if (std.mem.eql(u8, subcommand, "add")) {
        if (cli_args.len < 4) {
            const stderr = std.io.getStdErr().writer();
            try stderr.writeAll("Missing provider type\n");
            try stderr.writeAll("Usage: zai provider add <type> [options]\n");
            try stderr.writeAll("\nSupported types:\n");
            try stderr.writeAll("  openai            OpenAI API provider\n");
            try stderr.writeAll("  amazon_bedrock    Amazon Bedrock provider\n");
            try stderr.writeAll("  anthropic         Anthropic provider\n");
            try stderr.writeAll("  google_vertex     Google Vertex AI provider\n");
            try stderr.writeAll("  local             Local provider\n");
            return;
        }

        const provider_type = cli_args[3];
        var config = try zai.ProviderConfig.parseFromOptions(allocator, provider_type, cli_args[4..]);
        defer config.deinit(allocator);

        // Load existing registry
        const config_file = try config_path.getConfigPath(allocator);
        defer allocator.free(config_file);

        var registry = try zai.Registry.loadFromFile(allocator, config_file);
        defer registry.deinit();

        // Add the provider with no models
        if (registry.createProvider(provider_type, config, &[_]zai.ModelSpec{})) |_| {
            try registry.saveToFile(config_file);
            const stdout = std.io.getStdOut().writer();
            try stdout.print("Added provider '{s}'. Use 'zai models add {s} <model>' to add models.\n", .{ provider_type, provider_type });
        } else |err| {
            const stderr = std.io.getStdErr().writer();
            switch (err) {
                error.ProviderAlreadyExists => {
                    try stderr.print("Provider '{s}' already exists\n", .{provider_type});
                    return err;
                },
                else => return err,
            }
        }
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        if (cli_args.len < 4) {
            const stderr = std.io.getStdErr().writer();
            try stderr.writeAll("Missing provider name\n");
            try stderr.writeAll("Usage: zai provider remove <name>\n");
            return;
        }

        const provider_name = cli_args[3];
        const config_file = try config_path.getConfigPath(allocator);
        defer allocator.free(config_file);

        var registry = try zai.Registry.loadFromFile(allocator, config_file);
        defer registry.deinit();

        // Find and remove the provider
        var found = false;
        var new_providers = std.ArrayList(zai.ProviderSpec).init(allocator);
        defer new_providers.deinit();

        for (registry.providers.items) |provider| {
            if (!std.mem.eql(u8, provider.name, provider_name)) {
                try new_providers.append(provider);
            } else {
                found = true;
                // Free the provider's memory
                allocator.free(provider.name);
                for (provider.models) |*model| {
                    allocator.free(model.name);
                    allocator.free(model.id);
                }
                allocator.free(provider.models);
                switch (provider.config) {
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
        }

        if (!found) {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("Provider '{s}' not found\n", .{provider_name});
            return;
        }

        registry.providers.clearAndFree();
        try registry.providers.appendSlice(new_providers.items);
        try registry.saveToFile(config_file);

        const stdout = std.io.getStdOut().writer();
        try stdout.print("Removed provider '{s}'\n", .{provider_name});
    } else if (std.mem.eql(u8, subcommand, "set-default")) {
        if (cli_args.len < 4) {
            const stderr = std.io.getStdErr().writer();
            try stderr.writeAll("Missing provider name\n");
            try stderr.writeAll("Usage: zai provider set-default <name>\n");
            return;
        }

        const provider_name = cli_args[3];
        const config_file = try config_path.getConfigPath(allocator);
        defer allocator.free(config_file);

        var registry = try zai.Registry.loadFromFile(allocator, config_file);
        defer registry.deinit();

        // Find the provider
        const provider = registry.getProvider(provider_name) orelse {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("Provider '{s}' not found\n", .{provider_name});
            return;
        };

        // Move the provider to the front
        var new_providers = std.ArrayList(zai.ProviderSpec).init(allocator);
        defer new_providers.deinit();

        try new_providers.append(provider.*);
        for (registry.providers.items) |other_provider| {
            if (!std.mem.eql(u8, other_provider.name, provider_name)) {
                try new_providers.append(other_provider);
            }
        }

        registry.providers.clearAndFree();
        try registry.providers.appendSlice(new_providers.items);
        try registry.saveToFile(config_file);

        const stdout = std.io.getStdOut().writer();
        try stdout.print("Set '{s}' as the default provider\n", .{provider_name});
    } else {
        try printProviderHelp();
    }
}

fn handleModels(allocator: std.mem.Allocator, cli_args: []const []const u8) !void {
    if (cli_args.len < 3) {
        try printModelsHelp();
        return;
    }

    const subcommand = cli_args[2];
    if (std.mem.eql(u8, subcommand, "list")) {
        const config_file = try config_path.getConfigPath(allocator);
        defer allocator.free(config_file);

        var registry = try zai.Registry.loadFromFile(allocator, config_file);
        defer registry.deinit();

        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll("Available models:\n");

        for (registry.providers.items) |provider| {
            try stdout.print("\n{s}:\n", .{provider.name});
            for (provider.models) |model| {
                try stdout.print("  - {s} ({s})\n", .{ model.name, model.id });
                try stdout.writeAll("    Capabilities: ");
                var first = true;
                inline for (std.meta.fields(zai.registry.Capability)) |field| {
                    if (model.capabilities.contains(@field(zai.registry.Capability, field.name))) {
                        if (!first) try stdout.writeAll(", ");
                        try stdout.writeAll(field.name);
                        first = false;
                    }
                }
                try stdout.writeByte('\n');
            }
        }
    } else if (std.mem.eql(u8, subcommand, "add")) {
        if (cli_args.len < 5) {
            const stderr = std.io.getStdErr().writer();
            try stderr.writeAll("Missing provider name or model name\n");
            try stderr.writeAll("Usage: zai models add <provider> <name> [options]\n");
            return;
        }

        const provider_name = cli_args[3];
        const model_name = cli_args[4];

        // Parse model options
        var model_id: ?[]const u8 = null;
        var capabilities = std.EnumSet(zai.registry.Capability).init(.{});

        var i: usize = 5;
        while (i < cli_args.len) : (i += 1) {
            const arg = cli_args[i];
            if (std.mem.eql(u8, arg, "--id")) {
                if (i + 1 >= cli_args.len) {
                    const stderr = std.io.getStdErr().writer();
                    try stderr.writeAll("Missing value for --id\n");
                    return error.MissingOptionValue;
                }
                model_id = try allocator.dupe(u8, cli_args[i + 1]);
                i += 1;
            } else if (std.mem.eql(u8, arg, "--chat")) {
                capabilities.insert(.chat);
            } else if (std.mem.eql(u8, arg, "--completion")) {
                capabilities.insert(.completion);
            } else if (std.mem.eql(u8, arg, "--embedding")) {
                capabilities.insert(.embedding);
            } else {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("Invalid option: {s}\n", .{arg});
                return error.InvalidOption;
            }
        }

        if (model_id == null) {
            const stderr = std.io.getStdErr().writer();
            try stderr.writeAll("Missing required --id option\n");
            return error.MissingRequiredField;
        }
        defer if (model_id) |id| allocator.free(id);

        // Load registry
        const config_file = try config_path.getConfigPath(allocator);
        defer allocator.free(config_file);

        var registry = try zai.Registry.loadFromFile(allocator, config_file);
        defer registry.deinit();

        // Find provider
        const provider = registry.getProvider(provider_name) orelse {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("Provider '{s}' not found\n", .{provider_name});
            return error.ProviderNotFound;
        };

        // Check if model already exists
        for (provider.models) |model| {
            if (std.mem.eql(u8, model.name, model_name)) {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("Model '{s}' already exists for provider '{s}'\n", .{ model_name, provider_name });
                return error.ModelAlreadyExists;
            }
        }

        // Create new models array with added model
        var new_models = try allocator.alloc(zai.ModelSpec, provider.models.len + 1);
        defer allocator.free(new_models);

        // Copy existing models
        for (provider.models, 0..) |model, idx| {
            new_models[idx] = .{
                .name = try allocator.dupe(u8, model.name),
                .id = try allocator.dupe(u8, model.id),
                .capabilities = model.capabilities,
            };
        }

        // Add new model
        new_models[provider.models.len] = .{
            .name = try allocator.dupe(u8, model_name),
            .id = try allocator.dupe(u8, model_id.?),
            .capabilities = capabilities,
        };

        // Update provider's models
        for (provider.models) |model| {
            allocator.free(model.name);
            allocator.free(model.id);
        }
        allocator.free(provider.models);
        provider.models = new_models;

        // Save registry
        try registry.saveToFile(config_file);

        const stdout = std.io.getStdOut().writer();
        try stdout.print("Added model '{s}' to provider '{s}'\n", .{ model_name, provider_name });
    } else {
        try printModelsHelp();
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cli_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, cli_args);

    if (cli_args.len < 2) {
        try printUsage();
        return;
    }

    // Check for help flag
    if (cli_args.len == 2 and std.mem.eql(u8, cli_args[1], "--help")) {
        try printUsage();
        return;
    }

    if (cli_args.len >= 3 and std.mem.eql(u8, cli_args[2], "--help")) {
        const command = args.Command.fromString(cli_args[1]) catch {
            try printUsage();
            return;
        };
        switch (command) {
            .chat => try printChatHelp(),
            .completion => try printCompletionHelp(),
            .embedding => try printEmbeddingHelp(),
            .provider => try printProviderHelp(),
            .models => try printModelsHelp(),
        }
        return;
    }

    // Ensure config directory exists
    try config_path.ensureConfigDirExists();

    // Load the registry once at startup
    const config_file = try config_path.getConfigPath(allocator);
    defer allocator.free(config_file);

    var registry = try zai.Registry.loadFromFile(allocator, config_file);
    defer registry.deinit();

    const options = args.parseArgs(allocator, cli_args) catch |err| {
        const stderr = std.io.getStdErr().writer();
        switch (err) {
            error.MissingCommand => try printUsage(),
            error.InvalidCommand => {
                try stderr.print("Invalid command: {s}\n\n", .{cli_args[1]});
                try printUsage();
            },
            error.MissingPrompt => {
                const command = args.Command.fromString(cli_args[1]) catch {
                    try printUsage();
                    return;
                };
                switch (command) {
                    .chat => try printChatHelp(),
                    .completion => try printCompletionHelp(),
                    .embedding => try printEmbeddingHelp(),
                    .provider => try printProviderHelp(),
                    .models => try printModelsHelp(),
                }
            },
            error.MissingOptionValue => {
                try stderr.writeAll("Missing value for option\n");
                return err;
            },
            error.InvalidOption => {
                try stderr.writeAll("Invalid option\n");
                return err;
            },
            else => return err,
        }
        return;
    };
    defer {
        if (options.provider) |p| allocator.free(p);
        if (options.system_message) |s| allocator.free(s);
        if (options.model) |m| allocator.free(m);
        allocator.free(options.prompt);
    }

    const stderr = std.io.getStdErr().writer();
    switch (options.command) {
        .chat => {
            // Get provider - either specified or default (first)
            const provider_name = if (options.provider) |p| p else blk: {
                if (registry.providers.items.len == 0) {
                    try stderr.writeAll("No providers configured. Please configure a provider first.\n");
                    return error.NoProvidersConfigured;
                }
                break :blk registry.providers.items[0].name;
            };

            // Initialize the provider
            try registry.initProvider(provider_name);

            const provider = registry.getProvider(provider_name) orelse {
                try stderr.print("Provider not found: {s}\n", .{provider_name});
                return error.ProviderNotFound;
            };

            if (provider.instance) |instance| {
                try handleChat(allocator, instance, provider_name, &registry, options);
            } else {
                return error.ProviderNotInitialized;
            }
        },
        .completion, .embedding => {
            try stderr.print("Command not implemented yet: {s}\n", .{@tagName(options.command)});
            return error.NotImplemented;
        },
        .provider => try handleProvider(allocator, cli_args),
        .models => try handleModels(allocator, cli_args),
    }
}
