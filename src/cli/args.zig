const std = @import("std");

pub const Command = enum {
    chat,
    completion,
    embedding,
    provider,

    pub fn fromString(str: []const u8) !Command {
        if (std.mem.eql(u8, str, "chat")) return .chat;
        if (std.mem.eql(u8, str, "completion")) return .completion;
        if (std.mem.eql(u8, str, "embedding")) return .embedding;
        if (std.mem.eql(u8, str, "provider")) return .provider;
        std.debug.print("Invalid command: {s}\n", .{str});
        return error.InvalidCommand;
    }

    pub fn requiresPrompt(self: Command) bool {
        return switch (self) {
            .chat, .completion => true,
            .embedding, .provider => false,
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
        std.debug.print("Missing command argument\n", .{});
        return error.MissingArgument;
    }

    const command = try Command.fromString(args[1]);

    var options = ChatOptions{
        .prompt = "",
        .command = command,
    };

    var i: usize = 2;
    var found_prompt = false;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--")) {
            // Handle options
            if (i + 1 >= args.len) {
                std.debug.print("Missing value for option: {s}\n", .{arg});
                return error.MissingArgument;
            }
            i += 1;
            if (std.mem.eql(u8, arg, "--provider")) {
                options.provider = try allocator.dupe(u8, args[i]);
            } else if (std.mem.eql(u8, arg, "--system-message")) {
                options.system_message = try allocator.dupe(u8, args[i]);
            } else if (std.mem.eql(u8, arg, "--stream")) {
                options.stream = std.mem.eql(u8, args[i], "true");
            } else if (std.mem.eql(u8, arg, "--model")) {
                options.model = try allocator.dupe(u8, args[i]);
            } else {
                std.debug.print("Invalid option: {s}\n", .{arg});
                return error.InvalidOption;
            }
        } else {
            // This must be the prompt
            options.prompt = try allocator.dupe(u8, arg);
            found_prompt = true;
        }
    }

    if (!found_prompt and command.requiresPrompt()) {
        std.debug.print("Missing prompt argument\n", .{});
        return error.MissingPrompt;
    }

    return options;
}
