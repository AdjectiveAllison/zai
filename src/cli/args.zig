const std = @import("std");

pub const Command = enum {
    chat,
    completion,
    embedding,
    provider,
    models,
    prompt,
    completions,

    pub fn fromString(str: []const u8) !Command {
        if (std.mem.eql(u8, str, "chat")) return .chat;
        if (std.mem.eql(u8, str, "completion")) return .completion;
        if (std.mem.eql(u8, str, "embedding")) return .embedding;
        if (std.mem.eql(u8, str, "provider")) return .provider;
        if (std.mem.eql(u8, str, "models")) return .models;
        if (std.mem.eql(u8, str, "prompt")) return .prompt;
        if (std.mem.eql(u8, str, "completions")) return .completions;
        return error.InvalidCommand;
    }

    pub fn requiresPrompt(self: Command) bool {
        return switch (self) {
            .chat, .completion => true,
            .embedding, .provider, .models, .prompt, .completions => false,
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

    if (command == .provider or command == .models or command == .prompt or command == .completions) {
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

    // Handle stdin - check if there's piped content
    const stdin = std.io.getStdIn();
    var stdin_content: ?[]u8 = null;
    
    // Read from stdin if it's not a TTY (i.e., piped input)
    if (!stdin.isTty()) {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        try stdin.reader().readAllArrayList(&buffer, std.math.maxInt(usize));
        
        // Only use stdin if there's actual content
        if (buffer.items.len > 0) {
            // Trim trailing newlines
            var content = buffer.items;
            while (content.len > 0 and (content[content.len - 1] == '\n' or content[content.len - 1] == '\r')) {
                content.len -= 1;
            }
            stdin_content = try allocator.dupe(u8, content);
        }
    }

    // Handle different scenarios
    if (!prompt_found and command.requiresPrompt()) {
        // No prompt argument provided
        if (stdin_content) |content| {
            // Use stdin content as prompt if no explicit prompt was provided
            options.prompt = content;
        } else {
            return error.MissingPrompt;
        }
    } else if (prompt_found and stdin_content != null) {
        // Combine prompt and stdin content if both are provided
        var combined = std.ArrayList(u8).init(allocator);
        defer combined.deinit();
        
        try combined.appendSlice(options.prompt);
        try combined.appendSlice("\n\nContext:\n\n");
        try combined.appendSlice(stdin_content.?);
        
        // Free the original prompt and stdin content
        allocator.free(options.prompt);
        allocator.free(stdin_content.?);
        
        // Set the new combined prompt
        options.prompt = try combined.toOwnedSlice();
    } else if (!prompt_found) {
        // No prompt required (command doesn't need it) and no stdin
        options.prompt = try allocator.dupe(u8, "");
    }
    // If prompt was provided but no stdin, keep existing prompt (prompt_found is true)

    return options;
}
