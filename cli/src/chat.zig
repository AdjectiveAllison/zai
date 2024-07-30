const std = @import("std");
const zai = @import("zai");

pub fn run(gpa: std.mem.Allocator, args: []const []const u8) !void {
    const cmd = Command.parse(args);

    if (cmd.mode == .stdin) @panic("stdin mode for chat messages not supported yet!");

    var ai: zai.AI = undefined;
    try ai.init(gpa, cmd.provider);
    defer ai.deinit();

    var messages = [_]zai.Message{
        zai.Message{
            .role = "system",
            .content = "You are a helpful AI!",
        },
        zai.Message{
            .role = "user",
            .content = cmd.message orelse @panic("No message provided"),
        },
    };

    const payload = zai.CompletionPayload{
        .model = cmd.model,
        .messages = messages[0..],
        .temperature = 0.1,
        .stream = cmd.stream,
    };

    var chat_completion: zai.ChatCompletion = undefined;
    chat_completion.init(gpa);
    defer chat_completion.deinit();

    if (payload.stream) {
        try chat_completion.streamAndPrint(&ai, payload);
    } else {
        try chat_completion.request(&ai, payload);
        std.debug.print("{s}\n", .{chat_completion.content.items});
    }
}

pub const Command = struct {
    message: ?[]const u8 = null,
    stream: bool = false,
    provider: zai.Provider = zai.Provider.OctoAI,
    model: []const u8 = "mixtral-8x7b-instruct-fp16",
    mode: enum { stdin, command_line } = .command_line,

    fn parse(args: []const []const u8) Command {
        var cmd: Command = .{};
        var idx: usize = 0;
        if (args.len == 0) fatalHelp();
        while (idx < args.len) : (idx += 1) {
            const arg = args[idx];
            if (std.mem.eql(u8, arg, "--help") or
                std.mem.eql(u8, arg, "-h"))
            {
                fatalHelp();
            }

            if (std.mem.eql(u8, arg, "-s") or
                std.mem.eql(u8, arg, "--stream"))
            {
                cmd.stream = true;
                continue;
            }
            if (std.mem.eql(u8, arg, "--stdin") or
                std.mem.eql(u8, arg, "-"))
            {
                cmd.mode = .stdin;
                continue;
            }
            if (std.mem.eql(u8, arg, "--model")) {
                cmd.model = args[idx + 1];
                idx += 1;
                continue;
            }
            if (std.mem.eql(u8, arg, "--provider")) {
                cmd.provider = std.meta.stringToEnum(zai.Provider, args[idx + 1]) orelse {
                    std.debug.print("Unrecognized provider given: {s}\n please see \"zai.Provider\" for available options.", .{args[idx + 1]});
                    fatalHelp();
                };
                idx += 1;
                continue;
            }
            if (idx != (args.len - 1)) {
                fatalHelp();
            } else {
                cmd.mode = .command_line;
                cmd.message = arg;
            }
        }
        return cmd;
    }
    fn fatalHelp() noreturn {
        std.debug.print(
            \\Usage: zai chat [OPTIONS] MESSAGE
            \\
            \\   chats
            \\
            \\Options:
            \\
            \\--help, -h       Prints this help and extits
            \\--stdin, -       Format bytes from stdin; ouptut to stdout
        , .{});

        std.process.exit(1);
    }
};
