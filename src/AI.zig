const std = @import("std");
const Provider = @import("shared.zig").Provider;
const Message = @import("shared.zig").Message;
const CompletionPayload = @import("shared.zig").CompletionPayload;
const StreamHandler = @import("shared.zig").StreamHandler;

pub const AI = @This();

base_url: []const u8,
authorization_header_value: []const u8,
organization: ?[]const u8 = null,
gpa: std.mem.Allocator,
extra_headers: std.ArrayList(std.http.Header),

pub fn init(self: *AI, gpa: std.mem.Allocator, provider: Provider) !void {
    self.gpa = gpa;
    self.base_url = provider.getBaseUrl();
    self.extra_headers = std.ArrayList(std.http.Header).init(gpa);

    try self.setAuthorizationHeader(provider);
    try self.setExtraHeaders();
}

pub fn deinit(self: *AI) void {
    self.gpa.free(self.authorization_header_value);
    self.extra_headers.deinit();
}

// returns owned object with an arena packaged with it to deinit on response.
pub fn chatCompletionParsed(
    self: *AI,
    payload: CompletionPayload,
) !std.json.Parsed(ChatCompletionResponse) {
    const response = try self.chatCompletionRaw(payload);
    defer self.gpa.free(response);

    const parsed_completion = try std.json.parseFromSlice(
        ChatCompletionResponse,
        self.gpa,
        response,
        .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        },
    );
    return parsed_completion;
}

// deinit of arena passed in should prevent leaks.
pub fn chatCompletionLeaky(
    self: *AI,
    arena: std.mem.Allocator,
    payload: CompletionPayload,
) !ChatCompletionResponse {
    const response = try self.chatCompletionRaw(payload);
    defer self.gpa.free(response);

    const parsed_completion = try std.json.parseFromSliceLeaky(
        ChatCompletionResponse,
        arena,
        response,
        .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        },
    );
    return parsed_completion;
}

// CALLER OWNS THE FREEING RESPONSIBILITIES
pub fn chatCompletionRaw(
    self: *AI,
    payload: CompletionPayload,
) ![]const u8 {
    var client = std.http.Client{
        .allocator = self.gpa,
    };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = try std.fmt.allocPrint(self.gpa, "{s}/chat/completions", .{self.base_url});
    defer self.gpa.free(uri_string);
    const uri = try std.Uri.parse(uri_string);

    const body = try std.json.stringifyAlloc(self.gpa, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    });
    defer self.gpa.free(body);

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
        .authorization = .{ .override = self.authorization_header_value },
    };

    var req = try client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = headers,
        .extra_headers = self.extra_headers.items,
    });
    defer req.deinit();

    req.transfer_encoding = .chunked;

    try req.send();
    try req.writer().writeAll(body);
    try req.finish();
    try req.wait();

    const status = req.response.status;
    if (status != .ok) {
        //TODO: Do this better.
        std.debug.print("STATUS NOT OKAY\n{s}\nWE GOT AN ERROR\n", .{status.phrase().?});
    }

    const response = try req.reader().readAllAlloc(self.gpa, 3276800);
    return response;
}

// pub fn chatCompletionStreamParsed(
//     self: *AI,
//     payload: CompletionPayload,
//     writer: anytype,
// ) !void {
//
// }

pub fn chatCompletionStreamRaw(
    self: *AI,
    payload: CompletionPayload,
    writer: anytype,
) !void {
    var client = std.http.Client{ .allocator = self.gpa };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = try std.fmt.allocPrint(self.gpa, "{s}/chat/completions", .{self.base_url});
    defer self.gpa.free(uri_string);
    const uri = try std.Uri.parse(uri_string);

    const body = try std.json.stringifyAlloc(self.gpa, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    });
    defer self.gpa.free(body);

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
        .authorization = .{ .override = self.authorization_header_value },
    };

    var req = try client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = headers,
        .extra_headers = self.extra_headers.items,
    });
    defer req.deinit();

    req.transfer_encoding = .chunked;

    try req.send();
    try req.writer().writeAll(body);
    try req.finish();
    try req.wait();

    const status = req.response.status;
    if (status != .ok) {
        std.debug.print("STATUS NOT OKAY\n{s}\nWE GOT AN ERROR\n", .{status.phrase().?});
    }

    var content_received = false;
    while (true) {
        const chunk = try req.reader().readUntilDelimiterOrEofAlloc(self.gpa, '\n', 1638400) orelse break;
        defer self.gpa.free(chunk);

        if (std.mem.eql(u8, chunk, "data: [DONE]")) {
            break;
        }

        if (!std.mem.startsWith(u8, chunk, "data: ")) continue;

        const write_result = try writer.write(chunk[6..]);
        if (write_result > 0) {
            content_received = true;
        }
    }
}

fn setAuthorizationHeader(self: *AI, provider: Provider) !void {
    const env_var = provider.getKeyVar();
    const api_key = try std.process.getEnvVarOwned(self.gpa, env_var);
    defer self.gpa.free(api_key);

    self.authorization_header_value = try std.fmt.allocPrint(self.gpa, "Bearer {s}", .{api_key});
}

fn setExtraHeaders(self: *AI) !void {
    try self.extra_headers.append(.{ .name = "User-Agent", .value = "zai/0.1.0" });
    try self.extra_headers.append(.{ .name = "Accept", .value = "*/*" });
}

// TODO: Do something with role later on potentially.
const Role = union(enum) {
    system: "system",
    assistant: "assistant",
    user: "user",
};

const Usage = struct {
    prompt_tokens: u64,
    completion_tokens: ?u64,
    total_tokens: u64,
};

const Choice = struct { index: usize, finish_reason: ?[]const u8, message: Message };

// TODO: If I return direct response without explicitly passing in an arena then go ahead and create a deinit method inside of this that cleans it all up.
const ChatCompletionResponse = struct {
    id: []const u8,
    object: []const u8,
    created: u64,
    model: []const u8,
    choices: []Choice,
    // Usage is not returned by the Completion endpoint when streamed.
    usage: ?Usage = null,
};
