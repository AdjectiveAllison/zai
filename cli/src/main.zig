const std = @import("std");
const zai = @import("zai");
const cova = @import("cova");
pub const CommandT = cova.Command.Base();

// TODO: use ziggy for default configuration storage. e.g. system messages and such should never have to be passed on the command line.
const CompletionPayloadSimple = struct {
    model: []const u8,
    max_tokens: ?u64 = null,
    temperature: ?f16 = null,
    top_p: ?f16 = null,
    frequency_penalty: ?f16 = null,
    presence_penalty: ?f16 = null,
    stream: bool = false,
    message: []const u8,
};

pub const setup_cmd: CommandT = .{
    .name = "zai",
    .description = "a zig cli tool for interacting with ai!",
    .sub_cmds = &.{
        CommandT.from(
            CompletionPayloadSimple,
            .{
                .attempt_short_opts = false,
                .cmd_name = "chat",
                .cmd_description = "Chat with an llm.",
            },
        ),
    },
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Initializing the `setup_cmd` with an allocator will make it available for Runtime use.
    const main_cmd = try setup_cmd.init(alloc, .{});
    defer main_cmd.deinit();

    // Parsing
    var args_iter = try cova.ArgIteratorGeneric.init(alloc);
    defer args_iter.deinit();
    const stdout = std.io.getStdOut().writer();

    cova.parseArgs(&args_iter, CommandT, &main_cmd, stdout, .{}) catch |err| switch (err) {
        error.UsageHelpCalled, error.TooManyValues, error.UnrecognizedArgument, error.UnexpectedArgument, error.CouldNotParseOption => {},
        else => return err,
    };

    // ZAI
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_state.deinit() == .ok);
    const gpa = gpa_state.allocator();

    var ai: zai.AI = undefined;

    try ai.init(gpa, zai.Provider.TogetherAI);
    defer ai.deinit();

    // ZAI END
    if (main_cmd.matchSubCmd("chat")) |chat_cmd| {
        const payload_simple = try chat_cmd.to(CompletionPayloadSimple, .{});
        var messages = [_]zai.Message{
            zai.Message{
                .role = "system",
                .content = "You are a helpful AI!",
            },
            zai.Message{
                .role = "user",
                .content = payload_simple.message,
            },
        };
        const payload = zai.CompletionPayload{
            .messages = messages[0..],
            .model = payload_simple.model,
            .stream = payload_simple.stream,
        };

        std.debug.print("hooray ! {s}\n ", .{payload.model});

        var chat_completion: zai.ChatCompletion = undefined;
        chat_completion.init(gpa);
        defer chat_completion.deinit();
        try chat_completion.request(&ai, payload);
    }
    // Analysis (Using the data.)
    // if (builtin.mode == .Debug) try cova.utils.displayCmdInfo(CommandT, &main_cmd, alloc, &stdout);

    // Glossing over some project variables here.

    // // Convert a Command back into a Struct.
    // if (main_cmd.matchSubCmd("new")) |new_cmd| {
    //     var new_user = try new_cmd.to(User, .{});
    //     new_user._id = getNextID();
    //     try users.append(new_user);
    //     try users_mal.append(alloc, new_user);
    //     var user_buf: [512]u8 = .{0} ** 512;
    //     try user_file.writer().print("{s}\n", .{try new_user.to(user_buf[0..])});
    //     try stdout.print("Added:\n{s}\n", .{new_user});
    // }
    // // Convert a Command back into a Function and call it.
    // if (main_cmd.matchSubCmd("open")) |open_cmd| {
    //     user_file = try open_cmd.callAs(open, null, std.fs.File);
    // }
    // // Get the provided sub Command and check an Option from that sub Command.
    // if (main_cmd.matchSubCmd("clean")) |clean_cmd| cleanCmd: {
    //     if ((try clean_cmd.getOpts(.{})).get("clean_file")) |clean_opt| {
    //         if (clean_opt.val.isSet()) {
    //             const filename = try clean_opt.val.getAs([]const u8);
    //             try delete(filename);
    //             break :cleanCmd;
    //         }
    //     }
    //     try delete("users.csv");
    //     try delete(".ba_persist");
    // }
}
