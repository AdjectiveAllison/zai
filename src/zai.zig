const std = @import("std");

// std.meta.stringToEnum could be very useful for model strings -> enum conversion. null is returned if enum isn't found, thus we could early-exit out of clients if they pass in an incorrect one.

//TODO: Handle organization in relevant cases(OpenAI)
// If ogranization is passed, it's simply a header to openAI:
//"OpenAI-Organization: YOUR_ORG_ID"

// TODO: create AI struct object that can take the below as parameters and handle each different provider for both chat completion and embeddings.
// was using zig-llm and bork/src/Network.zig for inspiration on the initilaization of this struct.
pub const AI = struct {
    base_url: []const u8,
    api_key: []const u8,
    organization: ?[]const u8 = null,
    gpa: std.mem.Allocator,
    headers: std.http.Headers,

    //api_key: []const u8, organization_id: ?[]const u8\
    pub fn init(self: *AI, gpa: std.mem.Allocator, provider: Provider) !void {
        self.gpa = gpa;
        self.base_url = provider.get_base_url();

        try self.set_api_key(provider);
        try self.set_headers();
    }

    pub fn deinit(self: *AI) void {
        self.headers.deinit();
        self.gpa.free(self.api_key);
    }

    //TODO: Headers currently believes api_key is always set, confirm that's okay and remove this todo.
    // I used content-length in completion in my other implementation, do I need that?
    fn set_headers(self: *AI) !void {
        self.headers = std.http.Headers{ .allocator = self.gpa };
        const authorization_header = std.fmt.allocPrint(self.gpa, "Bearer {s}", .{self.api_key}) catch unreachable;
        defer self.gpa.free(authorization_header);

        self.headers.append("Content-Type", "application/json") catch unreachable;
        self.headers.append("Authorization", authorization_header) catch unreachable;
        self.headers.append("accept", "*/*") catch unreachable;
    }

    fn set_api_key(self: *AI, provider: Provider) !void {
        const env_var = provider.get_key_var();

        // this should bubble up an error if the Enviornment variable doesn't exist.
        self.api_key = try std.process.getEnvVarOwned(self.gpa, env_var);
    }

    pub fn embeddings(
        self: *AI,
        payload: EmbeddingsPayload,
        arena: std.mem.Allocator,
    ) !Embeddings {
        var client = std.http.Client{
            .allocator = self.gpa,
        };
        defer client.deinit();

        const uri_string = try std.fmt.allocPrint(self.gpa, "{s}/embeddings", .{self.base_url});
        defer self.gpa.free(uri_string);
        const uri = std.Uri.parse(uri_string) catch unreachable;

        const body = try std.json.stringifyAlloc(self.gpa, payload, .{
            .whitespace = .minified,
            .emit_null_optional_fields = false,
        });

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
        //TODO: add in verbosity check to print responses.
        defer self.gpa.free(response);

        // std.debug.print("full response:\n{s}\n", .{response});
        const parsed_embeddings = try std.json.parseFromSliceLeaky(
            Embeddings,
            arena,
            response,
            .{ .ignore_unknown_fields = true },
        );

        return parsed_embeddings;
    }

    pub fn chat_completion(
        self: *AI,
        payload: CompletionPayload,
        completion: *Message,
    ) !void {
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

        const response = req.reader().readAllAlloc(self.gpa, 3276800) catch unreachable;
        //TODO: add in verbosity check to print responses.
        defer self.gpa.free(response);

        const parsed_completion = try std.json.parseFromSlice(
            ChatCompletionResponse,
            self.gpa,
            response,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed_completion.deinit();

        completion.content = try self.gpa.dupe(u8, parsed_completion.value.choices[0].message.content);

        return;
    }
    fn process_chat_completion_stream(
        self: *AI,
        arena: std.mem.Allocator,
        http_request: *std.http.Client.Request,
        partial_response: *ChatCompletionStreamPartialReturn,
    ) !void {
        var response_asigned = false;
        var content_list = std.ArrayList(u8).init(arena);
        // defer content_list.deinit();

        // TODO: Decide how stream handlers can be passed in.
        var debug_handler = DebugHandler{};
        const stream_handler = debug_handler.streamHandler();

        while (true) {
            const chunk_reader = try http_request.reader().readUntilDelimiterOrEofAlloc(self.gpa, '\n', 1638400);
            if (chunk_reader == null) break;

            const chunk = chunk_reader.?;
            defer self.gpa.free(chunk);

            if (std.mem.eql(u8, chunk, "data: [DONE]")) break;

            if (!std.mem.startsWith(u8, chunk, "data: ")) continue;

            // std.debug.print("Here is the chunk: {any}\n", .{chunk[6..]});

            const parsed_chunk = try std.json.parseFromSliceLeaky(
                ChatCompletionStream,
                arena,
                chunk[6..],
                .{ .ignore_unknown_fields = true },
            );

            if (!response_asigned) {
                partial_response.id = parsed_chunk.id;
                partial_response.created = parsed_chunk.created;
                response_asigned = true;
            }

            try stream_handler.processChunk(parsed_chunk);

            if (parsed_chunk.choices[0].delta.content == null) continue;

            try content_list.appendSlice(parsed_chunk.choices[0].delta.content.?);
        }

        partial_response.content = try content_list.toOwnedSlice();
    }
};

pub const ChatCompletion = struct {
    gpa: std.mem.Allocator,
    id: []const u8,
    content: []const u8,
    pub fn deinit(self: *ChatCompletion) void {
        self.gpa.free(self.id);
        self.gpa.free(self.content);
    }

    // Can I use ai.gpa here?
    pub fn request(self: *ChatCompletion, gpa: std.mem.Allocator, ai: *AI, payload: CompletionPayload) !void {
        self.gpa = gpa;

        var client = std.http.Client{
            .allocator = self.gpa,
        };
        defer client.deinit();

        // TODO: store api endpoints in a structure somehow and generate them at the point of initialization.
        const uri_string = try std.fmt.allocPrint(self.gpa, "{s}/chat/completions", .{ai.base_url});
        defer self.gpa.free(uri_string);
        const uri = std.Uri.parse(uri_string) catch unreachable;

        const body = try std.json.stringifyAlloc(self.gpa, payload, .{
            .whitespace = .minified,
            .emit_null_optional_fields = false,
        });

        // consider verbose printing the body if debugging.
        //std.debug.print("BODY:\n{s}\n\n", .{body});
        defer self.gpa.free(body);

        var req = try client.open(.POST, uri, ai.headers, .{});
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
        //TODO: add in verbosity check to print responses.
        defer self.gpa.free(response);

        const parsed_completion = try std.json.parseFromSlice(
            ChatCompletionResponse,
            self.gpa,
            response,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed_completion.deinit();

        self.content = try self.gpa.dupe(u8, parsed_completion.value.choices[0].message.content);
        self.id = try self.gpa.dupe(u8, parsed_completion.value.id);
        return;
    }
};

pub const EmbeddingsPayload = struct {
    input: []const u8,
    model: []const u8,
};

pub const Embeddings = struct {
    id: []const u8,
    data: []EmbeddingsData,
    // model: []const u8,
    // usage: struct {
    //     total_tokens: u64,
    //     prompt_tokens: u64,
    // },
};

pub const EmbeddingsData = struct {
    index: u32,
    object: []const u8,
    // TODO: Explore @Vector() and if it can be used in zig.
    embedding: []f32,
};

pub const Role = enum {
    system,
    assistant,
    user,
};

const Usage = struct {
    prompt_tokens: u64,
    completion_tokens: ?u64,
    total_tokens: u64,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

const Choice = struct { index: usize, finish_reason: ?[]const u8, message: Message };

const ChatCompletionResponse = struct {
    id: []const u8,
    object: []const u8,
    created: u64,
    model: []const u8,
    choices: []Choice,
    // Usage is not returned by the Completion endpoint when streamed.
    usage: ?Usage = null,
};

// TODO: Each provider slightly differs in stream response, would be really good to make this a per-provider type that adapts based on how the AI struct is initialized.
const ChatCompletionStream = struct {
    id: []const u8,
    created: u64,
    choices: []struct {
        index: u32,
        delta: struct {
            content: ?[]const u8,
        },
    },
};

const ChatCompletionStreamPartialReturn = struct {
    id: []const u8,
    created: u64,
    content: []const u8,
};

pub const DebugHandler = struct {
    fn processChunk(ptr: *anyopaque, completion_stream: ChatCompletionStream) !void {
        const self: *DebugHandler = @ptrCast(@alignCast(ptr));
        _ = self;
        if (completion_stream.choices[0].delta.content == null) return;
        std.debug.print("{s}", .{completion_stream.choices[0].delta.content.?});
    }
    pub fn streamHandler(self: *DebugHandler) StreamHandler {
        return .{
            .ptr = self,
            .processChunkFn = processChunk,
        };
    }
};
pub const StreamHandler = struct {
    ptr: *anyopaque,
    processChunkFn: *const fn (ptr: *anyopaque, completion_stream: ChatCompletionStream) anyerror!void,

    fn processChunk(self: StreamHandler, completion_stream: ChatCompletionStream) !void {
        return self.processChunkFn(self.ptr, completion_stream);
    }
};
pub const CompletionPayload = struct {
    model: []const u8,
    max_tokens: ?u64 = null,
    messages: []Message,
    temperature: ?f16 = null,
    top_p: ?f16 = null,
    //TODO: Check to see if this needs to be an array or something. slice of slice is hard to do in zig.
    stop: ?[][]const u8 = null,
    frequency_penalty: ?f16 = null,
    presence_penalty: ?f16 = null,
    stream: bool = false,
};

//TODO: enums for models available on multiple providers.
// const ChatCompletionModel =
pub const OctoAIModel = enum {
    mistral_7b_instruct_fp16,
    mixtral_8x7b_instruct_fp16,
    llama_2_13b_chat_fp16,
    llama_2_70b_chat_fp16,
    codellama_7b_instruct_fp16,
    codellama_13b_instruct_fp16,
    codellama_34b_instruct_fp16,
    codellama_70b_instruct_fp16,
};

pub const OpenAIModel = enum {
    gpt_35_turbo_0125,
    gpt_35_turbo_1106,
};
// embeddings as well

// base url options:
// openAI: https://api.openai.com/v1
// Together: https://api.together.xyz/v1
// Octo: https://text.octoai.run/v1
pub const Provider = enum {
    OpenAI,
    TogetherAI,
    OctoAI,

    pub fn get_base_url(self: Provider) []const u8 {
        return switch (self) {
            .OpenAI => "https://api.openai.com/v1",
            .TogetherAI => "https://api.together.xyz/v1",
            .OctoAI => "https://text.octoai.run/v1",
        };
    }

    pub fn get_key_var(self: Provider) []const u8 {
        return switch (self) {
            .OpenAI => "OPENAI_API_KEY",
            .TogetherAI => "TOGETHER_API_KEY",
            .OctoAI => "OCTO_API_KEY",
        };
    }
};

//TODO: Figure out if there is a smoothe way to handle the responses and give back only relevant data to the caller(e.g. return whole api response object or just message data, maybe make it a choice for the caller what they receive, with a default to just the message to make the api smoothe as silk).
// things that will be different between providers that I can handle and seperate:
// 1. Model list(for enums or selection)
// 2. no tool calls on messages on some providers(yet, and potentially lagging function_call parameter names)
// 3. Together may use repetition_penalty instead of frequency_penalty(need to confirm)
// 4. Organization for OpenAI(Potentially other headers later on)
