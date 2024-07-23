const std = @import("std");
const zai = @import("zai");
const chat_exe = @import("chat.zig");

// TODO: use ziggy for default configuration storage. e.g. system messages and such should never have to be passed on the command line.

pub const Command = enum { chat, embeddings, help };

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer std.debug.assert(gpa_state.deinit() == .ok);
    const gpa = gpa_state.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 2) fatalHelp();

    const cmd = std.meta.stringToEnum(Command, args[1]) orelse {
        std.debug.print("unrecognized subcommand: '{s}'\n\n", .{args[1]});
        fatalHelp();
    };

    _ = switch (cmd) {
        .chat => chat_exe.run(gpa, args[2..]),
        .help => fatalHelp(),
        else => @panic("TODO"),
    } catch |err| fatal("{s}\n", .{@errorName(err)});
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

fn fatalHelp() noreturn {
    fatal(
        \\Usage: zai COMMAND [OPTIONS]
        \\
        \\Commands: 
        \\  chat         Initiate a chat completion 
        \\  help         Show this menu and exit
        \\
        \\General Options:
        \\  --help, -h   Print command specific usage
        \\
        \\
    , .{});
}
