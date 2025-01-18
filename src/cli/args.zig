const std = @import("std");

pub const Command = enum {
    chat,
    completion,
    embedding,
    provider,
    models,

    pub fn fromString(str: []const u8) !Command {
        if (std.mem.eql(u8, str, "chat")) return .chat;
        if (std.mem.eql(u8, str, "completion")) return .completion;
        if (std.mem.eql(u8, str, "embedding")) return .embedding;
        if (std.mem.eql(u8, str, "provider")) return .provider;
        if (std.mem.eql(u8, str, "models")) return .models;
        return error.InvalidCommand;
    }

    pub fn requiresPrompt(self: Command) bool {
        return switch (self) {
            .chat, .completion => true,
            .embedding, .provider, .models => false,
        };
    }
};

pub const ChatOptions = struct {
    provider: ?[]const u8 = null,
    system_message: ?[]const u8 = null,
    stream: bool = true,
    model: ?[]const u8 = null,
    prompt: []const u8,
    command: Command,
};

pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !ChatOptions {
    if (args.len < 2) {
        return error.MissingCommand;
    }

    const command = try Command.fromString(args[1]);
    var options = ChatOptions{
        .command = command,
        .provider = null,
        .system_message = null,
        .model = null,
        .stream = true,
        .prompt = "",
    };

    if (command == .provider or command == .models) {
        options.prompt = try allocator.dupe(u8, "");
        return options;
    }

    var i: usize = 2;
    var prompt_found = false;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--")) {
            if (i + 1 >= args.len) {
                return error.MissingOptionValue;
            }
            const value = args[i + 1];
            i += 1;

            if (std.mem.eql(u8, arg, "--provider")) {
                options.provider = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, arg, "--system-message")) {
                options.system_message = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, arg, "--model")) {
                options.model = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, arg, "--stream")) {
                options.stream = std.mem.eql(u8, value, "true");
            } else {
                return error.InvalidOption;
            }
        } else {
            prompt_found = true;
            options.prompt = try allocator.dupe(u8, arg);
        }
    }

    if (!prompt_found and command.requiresPrompt()) {
        return error.MissingPrompt;
    }

    if (!prompt_found) {
        options.prompt = try allocator.dupe(u8, "");
    }

    return options;
}
