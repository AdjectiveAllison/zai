const AI = @This();

const std = @import("std");

base_url: []const u8,
api_key: []const u8,
organization: ?[]const u8 = null,
gpa: std.mem.Allocator,
headers: std.http.Headers,

//api_key: []const u8, organization_id: ?[]const u8\
pub fn init(self: *AI, gpa: std.mem.Allocator, provider: Provider) !void {
    self.gpa = gpa;
    self.base_url = provider.getBaseUrl();

    try self.setApiKey(provider);
    try self.setHeaders();
}

pub fn deinit(self: *AI) void {
    self.headers.deinit();
    self.gpa.free(self.api_key);
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
        .{ .ignore_unknown_fields = true },
    );

    return parsed_completion;
    // if (payload.stream) {
    //     var partial_response: ChatCompletionStreamPartialReturn = undefined;
    //     try self.process_chat_completion_stream(arena, &req, &partial_response);

    //     // TODO: Figure out a standard return object option for both stream and non stream.
    //     var choices = [_]Choice{Choice{
    //         .index = 0,
    //         .finish_reason = "stop",
    //         .message = Message{
    //             .role = "assistant",
    //             .content = partial_response.content,
    //         },
    //     }};
    //     _ = ChatCompletion{
    //         .id = partial_response.id,
    //         .object = "chat.completion",
    //         .created = partial_response.created,
    //         .model = payload.model,
    //         .choices = choices[0..],
    //     };
    //     // const chat_completion_empty =
    //     // return chat_completion_empty;
    //     return;
    // }

    // defer parsed_completion.deinit();

    // completion.content = try self.gpa.dupe(u8, parsed_completion.value.choices[0].message.content);

    // return;
}

// This isn't responsible
pub fn chatCompletionResponsible(self: *AI, payload: CompletionPayload) !ChatCompletionResponse {
    const response = try self.chatCompletionRaw(payload);
    defer self.gpa.free(response);

    const parsed_completion = try std.json.parseFromSlice(
        ChatCompletionResponse,
        self.gpa,
        response,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed_completion.deinit();

    return parsed_completion.value;
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
        .{ .ignore_unknown_fields = true },
    );

    return parsed_completion;
}

// CALLER OWNS THE FREEING RESPOSNSIBILITIES
fn chatCompletionRaw(
    self: *AI,
    payload: CompletionPayload,
) ![]const u8 {
    var client = std.http.Client{
        .allocator = self.gpa,
    };
    defer client.deinit();

    // TODO: store api endpoints in a structure somehow and generate them at the point of initialization.
    const uri_string = try std.fmt.allocPrint(self.gpa, "{s}/chat/completions", .{self.base_url});
    defer self.gpa.free(uri_string);
    const uri = std.Uri.parse(uri_string) catch unreachable;

    const body = try std.json.stringifyAlloc(self.gpa, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    });

    // consider verbose printing the body if debugging.
    //std.debug.print("BODY:\n{s}\n\n", .{body});
    defer self.gpa.free(body);

    var req = try client.open(.POST, uri, self.headers, .{});
    defer req.deinit();

    req.transfer_encoding = .chunked;

    try req.send(.{});
    try req.writer().writeAll(body);
    try req.finish();
    try req.wait();

    const status = req.response.status;
    if (status != .ok) {
        //TODO: Do this better.
        std.debug.print("STATUS NOT OKAY\n{s}\nWE GOT AN ERROR\n", .{status.phrase().?});
    }

    const response = req.reader().readAllAlloc(self.gpa, 3276800) catch unreachable;

    return response;
}
//TODO: Headers currently believes api_key is always set, confirm that's okay and remove this todo.
// I used content-length in completion in my other implementation, do I need that?
fn setHeaders(self: *AI) !void {
    self.headers = std.http.Headers{ .allocator = self.gpa };
    const authorization_header = std.fmt.allocPrint(self.gpa, "Bearer {s}", .{self.api_key}) catch unreachable;
    defer self.gpa.free(authorization_header);

    self.headers.append("Content-Type", "application/json") catch unreachable;
    self.headers.append("Authorization", authorization_header) catch unreachable;
    self.headers.append("accept", "*/*") catch unreachable;
}

fn setApiKey(self: *AI, provider: Provider) !void {
    const env_var = provider.getKeyVar();

    // this should bubble up an error if the Enviornment variable doesn't exist.
    self.api_key = try std.process.getEnvVarOwned(self.gpa, env_var);
}

// TODO: Move providers into some root level thing so we don't need to to zai.AI.Provider to access.
// base url options:
// openAI: https://api.openai.com/v1
// Together: https://api.together.xyz/v1
// Octo: https://text.octoai.run/v1
// TODO: Change to tagged union with individual provider types?
pub const Provider = enum {
    OpenAI,
    TogetherAI,
    OctoAI,

    pub fn getBaseUrl(self: Provider) []const u8 {
        return switch (self) {
            .OpenAI => "https://api.openai.com/v1",
            .TogetherAI => "https://api.together.xyz/v1",
            .OctoAI => "https://text.octoai.run/v1",
        };
    }

    pub fn getKeyVar(self: Provider) []const u8 {
        return switch (self) {
            .OpenAI => "OPENAI_API_KEY",
            .TogetherAI => "TOGETHER_API_KEY",
            .OctoAI => "OCTO_API_KEY",
        };
    }
};

pub const CompletionPayload = struct {
    model: []const u8,
    max_tokens: ?u64 = null,
    messages: []Message,
    temperature: ?f16 = null,
    top_p: ?f16 = null,
    // TODO: Check to see if this needs to be an array or something. slice of slice is hard to do in zig.
    stop: ?[][]const u8 = null,
    frequency_penalty: ?f16 = null,
    presence_penalty: ?f16 = null,
    stream: bool = false,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const Role = union(enum) {
    system: "system",
    assistant: "assistant",
    user: "user",
};

pub const Usage = struct {
    prompt_tokens: u64,
    completion_tokens: ?u64,
    total_tokens: u64,
};

pub const Choice = struct { index: usize, finish_reason: ?[]const u8, message: Message };

// TODO: If I return direct response without explicitly passing in an arena then go ahead and create a deinit method inside of this that cleans it all up.
pub const ChatCompletionResponse = struct {
    id: []const u8,
    object: []const u8,
    created: u64,
    model: []const u8,
    choices: []Choice,
    // Usage is not returned by the Completion endpoint when streamed.
    usage: ?Usage = null,
};
