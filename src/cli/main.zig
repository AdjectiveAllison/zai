const std = @import("std");
const zai = @import("zai");
const args = @import("args.zig");
const registry_helper = @import("registry_helper.zig");
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

fn handleChat(allocator: std.mem.Allocator, provider: *zai.Provider, provider_name: []const u8, options: args.ChatOptions) !void {
    const stdout = std.io.getStdOut().writer();

    // Load registry for model validation
    const config_file = try config_path.getConfigPath(allocator);
    defer allocator.free(config_file);

    var registry = try zai.Registry.loadFromFile(allocator, config_file);
    defer registry.deinit();

    // Validate model if specified
    try registry_helper.validateModel(provider_name, options.model, &registry);

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
        .model = if (options.model) |m| m else "anthropic.claude-3-5-sonnet-20241022-v2:0",
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
    _ = allocator;
    if (cli_args.len < 3) {
        try printProviderHelp();
        return;
    }

    const subcommand = cli_args[2];
    if (std.mem.eql(u8, subcommand, "list")) {
        std.debug.print("Provider management is not implemented yet\n", .{});
    } else if (std.mem.eql(u8, subcommand, "add")) {
        std.debug.print("Provider management is not implemented yet\n", .{});
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        std.debug.print("Provider management is not implemented yet\n", .{});
    } else if (std.mem.eql(u8, subcommand, "set-default")) {
        std.debug.print("Provider management is not implemented yet\n", .{});
    } else {
        try printProviderHelp();
    }
}

pub fn main() anyerror!void {
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
        }
        return;
    }

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
            var provider = if (options.provider) |p|
                registry_helper.getProviderByName(allocator, p) catch |err| {
                    switch (err) {
                        error.ProviderNotFound => {
                            try stderr.print("Provider not found: {s}\n", .{p});
                            return err;
                        },
                        else => return err,
                    }
                }
            else
                registry_helper.getDefaultProvider(allocator) catch |err| {
                    switch (err) {
                        error.NoProvidersConfigured => {
                            try stderr.writeAll("No providers configured. Please configure a provider first.\n");
                            return err;
                        },
                        else => return err,
                    }
                };
            defer provider.deinit();

            const provider_name = options.provider orelse "default";

            // Validate model if specified
            if (options.model) |model| {
                const config_file = try config_path.getConfigPath(allocator);
                defer allocator.free(config_file);

                var registry = try zai.Registry.loadFromFile(allocator, config_file);
                defer registry.deinit();

                registry_helper.validateModel(provider_name, model, &registry) catch |err| {
                    switch (err) {
                        error.InvalidModel => {
                            try stderr.print("Invalid model '{s}' for provider '{s}'\n", .{ model, provider_name });
                            return err;
                        },
                        error.ProviderNotFound => {
                            try stderr.print("Provider not found: {s}\n", .{provider_name});
                            return err;
                        },
                        else => return err,
                    }
                };
            }

            try handleChat(allocator, provider, provider_name, options);
        },
        .completion, .embedding => {
            try stderr.print("Command not implemented yet: {s}\n", .{@tagName(options.command)});
            return error.NotImplemented;
        },
        .provider => {
            try stderr.writeAll("Provider management is not implemented yet\n");
            return error.NotImplemented;
        },
    }
}
