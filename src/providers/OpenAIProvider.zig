const std = @import("std");
const providers = @import("../providers.zig");
const Provider = providers.Provider;
const OpenAIConfig = providers.OpenAIConfig;
const ChatRequestOptions = providers.ChatRequestOptions;
const CompletionRequestOptions = providers.CompletionRequestOptions;
const EmbeddingRequestOptions = providers.EmbeddingRequestOptions;
const Message = providers.Message;
const ModelInfo = providers.ModelInfo;

allocator: std.mem.Allocator,
config: OpenAIConfig,
authorization_header: []const u8,
extra_headers: std.ArrayList(std.http.Header),

const Self = @This();

pub fn init(allocator: std.mem.Allocator, config: OpenAIConfig) !Provider {
    var self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.allocator = allocator;
    self.config = config;
    self.extra_headers = std.ArrayList(std.http.Header).init(allocator);

    try self.setAuthorizationHeader();
    try self.setExtraHeaders();

    return .{
        .ptr = self,
        .vtable = &.{
            .deinit = deinit,
            .completion = completion,
            .completionStream = completionStream,
            .chat = chat,
            .chatStream = chatStream,
            .createEmbedding = createEmbedding,
            .getModelInfo = getModelInfo,
            .getModels = getModels,
        },
    };
}

fn setAuthorizationHeader(self: *Self) !void {
    self.authorization_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.config.api_key});
}

fn setExtraHeaders(self: *Self) !void {
    try self.extra_headers.append(.{ .name = "User-Agent", .value = "openai-zig/0.1.0" });
    try self.extra_headers.append(.{ .name = "Content-Type", .value = "application/json" });
    if (self.config.organization) |org| {
        try self.extra_headers.append(.{ .name = "OpenAI-Organization", .value = org });
    }
}

fn deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.allocator.free(self.authorization_header);
    self.extra_headers.deinit();
    self.allocator.destroy(self);
}

fn completion(ctx: *anyopaque, options: CompletionRequestOptions) Provider.Error![]const u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = std.fmt.allocPrint(self.allocator, "{s}/completions", .{self.config.base_url}) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(uri_string);

    const uri = std.Uri.parse(uri_string) catch {
        return Provider.Error.InvalidRequest;
    };

    // Prepare the request payload
    const payload = .{
        .model = options.model,
        .prompt = options.prompt,
        .max_tokens = options.max_tokens,
        .temperature = options.temperature,
        .top_p = options.top_p,
        .n = options.n,
        .stream = false, // We're not handling streaming in this function
        .logprobs = options.logprobs,
        .echo = options.echo,
        .stop = options.stop,
        .presence_penalty = options.presence_penalty,
        .frequency_penalty = options.frequency_penalty,
        .best_of = options.best_of,
        .user = options.user,
    };

    const body = std.json.stringifyAlloc(self.allocator, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(body);

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
        .authorization = .{ .override = self.authorization_header },
    };

    var req = client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = headers,
        .extra_headers = self.extra_headers.items,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            error.ConnectionRefused, error.NetworkUnreachable, error.ConnectionTimedOut => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;

    req.send() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.writer().writeAll(body) catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.finish() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.wait() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };

    const status = req.response.status;
    if (status != .ok) {
        const error_response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
            return switch (err) {
                error.OutOfMemory => Provider.Error.OutOfMemory,
                else => Provider.Error.UnexpectedError,
            };
        };
        defer self.allocator.free(error_response);
        std.debug.print("Error response: {s}\n", .{error_response});
        return Provider.Error.ApiError;
    }

    const response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer self.allocator.free(response);

    // Parse the response
    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            else => Provider.Error.ParseError,
        };
    };
    defer parsed.deinit();

    // Extract the content from the response
    const choices = parsed.value.object.get("choices") orelse return Provider.Error.ApiError;
    if (choices.array.items.len == 0) return Provider.Error.ApiError;

    const text = choices.array.items[0].object.get("text").?.string;
    return self.allocator.dupe(u8, text) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
}

fn completionStream(ctx: *anyopaque, options: CompletionRequestOptions, writer: std.io.AnyWriter) Provider.Error!void {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = std.fmt.allocPrint(self.allocator, "{s}/completions", .{self.config.base_url}) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(uri_string);

    const uri = std.Uri.parse(uri_string) catch {
        return Provider.Error.InvalidRequest;
    };

    // Prepare the request payload
    const payload = .{
        .model = options.model,
        .prompt = options.prompt,
        .max_tokens = options.max_tokens,
        .temperature = options.temperature,
        .top_p = options.top_p,
        .n = options.n,
        .stream = true, // Enable streaming
        .logprobs = options.logprobs,
        .echo = options.echo,
        .stop = options.stop,
        .presence_penalty = options.presence_penalty,
        .frequency_penalty = options.frequency_penalty,
        .best_of = options.best_of,
        .user = options.user,
    };

    const body = std.json.stringifyAlloc(self.allocator, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(body);

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
        .authorization = .{ .override = self.authorization_header },
    };

    var req = client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = headers,
        .extra_headers = self.extra_headers.items,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            error.ConnectionRefused, error.NetworkUnreachable, error.ConnectionTimedOut => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;

    req.send() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.writer().writeAll(body) catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.finish() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.wait() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };

    const status = req.response.status;
    if (status != .ok) {
        const error_response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
            return switch (err) {
                error.OutOfMemory => Provider.Error.OutOfMemory,
                else => Provider.Error.UnexpectedError,
            };
        };
        defer self.allocator.free(error_response);
        std.debug.print("Error response: {s}\n", .{error_response});
        return Provider.Error.ApiError;
    }

    var scanner = std.json.Scanner.initStreaming(self.allocator);
    defer scanner.deinit();

    var buffer: [4096]u8 = undefined;
    var stream_buffer = std.ArrayList(u8).init(self.allocator);
    defer stream_buffer.deinit();

    while (true) {
        const bytes_read = req.reader().read(&buffer) catch |err| {
            return switch (err) {
                error.ConnectionTimedOut, error.ConnectionResetByPeer => Provider.Error.NetworkError,
                error.TlsFailure, error.TlsAlert => Provider.Error.NetworkError,
                error.UnexpectedReadFailure => Provider.Error.UnexpectedError,
                error.EndOfStream => break, // End of stream, exit the loop
                error.HttpChunkInvalid, error.HttpHeadersOversize, error.DecompressionFailure, error.InvalidTrailers => Provider.Error.ApiError,
            };
        };
        if (bytes_read == 0) break; // End of stream

        try stream_buffer.appendSlice(buffer[0..bytes_read]);

        while (true) {
            const newline_index = std.mem.indexOfScalar(u8, stream_buffer.items, '\n') orelse break;
            const line = stream_buffer.items[0..newline_index];

            if (line.len > 0 and !std.mem.startsWith(u8, line, "data: ")) {
                // Skip non-data lines
                stream_buffer.replaceRange(0, newline_index + 1, &[_]u8{}) catch |err| {
                    return switch (err) {
                        error.OutOfMemory => Provider.Error.OutOfMemory,
                    };
                };
                continue;
            }

            if (std.mem.startsWith(u8, line, "data: ")) {
                const json_data = line["data: ".len..];
                if (std.mem.eql(u8, json_data, "[DONE]")) {
                    return; // End of stream
                }

                const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{}) catch |err| {
                    stream_buffer.replaceRange(0, newline_index + 1, &[_]u8{}) catch |replace_err| {
                        return switch (replace_err) {
                            error.OutOfMemory => Provider.Error.OutOfMemory,
                        };
                    };
                    if (err == error.InvalidCharacter) {
                        // Skip invalid JSON and continue
                        continue;
                    }
                    return Provider.Error.ParseError;
                };
                defer parsed.deinit();

                if (parsed.value.object.get("choices")) |choices| {
                    if (choices.array.items.len > 0) {
                        if (choices.array.items[0].object.get("text")) |text| {
                            writer.writeAll(text.string) catch |err| {
                                return switch (err) {
                                    error.OutOfMemory => Provider.Error.OutOfMemory,
                                    else => Provider.Error.UnexpectedError,
                                };
                            };
                        }
                    }
                }
            }

            stream_buffer.replaceRange(0, newline_index + 1, &[_]u8{}) catch |err| {
                return switch (err) {
                    error.OutOfMemory => Provider.Error.OutOfMemory,
                };
            };
        }
    }
}

fn chat(ctx: *anyopaque, options: ChatRequestOptions) Provider.Error![]const u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = std.fmt.allocPrint(self.allocator, "{s}/chat/completions", .{self.config.base_url}) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(uri_string);

    const uri = std.Uri.parse(uri_string) catch {
        return Provider.Error.InvalidRequest;
    };

    // Prepare the request payload
    const payload = .{
        .model = options.model,
        .messages = options.messages,
        .max_tokens = options.max_tokens,
        .temperature = options.temperature,
        .top_p = options.top_p,
        .n = options.n,
        .stream = false,
        .stop = options.stop,
        .presence_penalty = options.presence_penalty,
        .frequency_penalty = options.frequency_penalty,
        .user = options.user,
    };

    const body = std.json.stringifyAlloc(self.allocator, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(body);

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
        .authorization = .{ .override = self.authorization_header },
    };

    var req = client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = headers,
        .extra_headers = self.extra_headers.items,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            error.ConnectionRefused, error.NetworkUnreachable, error.ConnectionTimedOut => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;

    req.send() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.writer().writeAll(body) catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.finish() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.wait() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };

    const status = req.response.status;
    if (status != .ok) {
        const error_response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
            return switch (err) {
                error.OutOfMemory => Provider.Error.OutOfMemory,
                else => Provider.Error.UnexpectedError,
            };
        };
        defer self.allocator.free(error_response);
        std.debug.print("Error response: {s}\n", .{error_response});
        return Provider.Error.ApiError;
    }

    const response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer self.allocator.free(response);

    // Parse the response
    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            else => Provider.Error.ParseError,
        };
    };
    defer parsed.deinit();

    // Extract the content from the response
    const choices = parsed.value.object.get("choices") orelse return Provider.Error.ApiError;
    if (choices.array.items.len == 0) return Provider.Error.ApiError;

    const content = choices.array.items[0].object.get("message").?.object.get("content").?.string;
    return self.allocator.dupe(u8, content) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
}

fn chatStream(ctx: *anyopaque, options: ChatRequestOptions, writer: std.io.AnyWriter) Provider.Error!void {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = std.fmt.allocPrint(self.allocator, "{s}/chat/completions", .{self.config.base_url}) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(uri_string);

    const uri = std.Uri.parse(uri_string) catch {
        return Provider.Error.InvalidRequest;
    };

    // Prepare the request payload
    const payload = .{
        .model = options.model,
        .messages = options.messages,
        .max_tokens = options.max_tokens,
        .temperature = options.temperature,
        .top_p = options.top_p,
        .n = options.n,
        .stream = true, // Enable streaming
        .stop = options.stop,
        .presence_penalty = options.presence_penalty,
        .frequency_penalty = options.frequency_penalty,
        .user = options.user,
    };

    const body = std.json.stringifyAlloc(self.allocator, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(body);

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
        .authorization = .{ .override = self.authorization_header },
    };

    var req = client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = headers,
        .extra_headers = self.extra_headers.items,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            error.ConnectionRefused, error.NetworkUnreachable, error.ConnectionTimedOut => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;

    req.send() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.writer().writeAll(body) catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.finish() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.wait() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };

    const status = req.response.status;
    if (status != .ok) {
        const error_response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
            return switch (err) {
                error.OutOfMemory => Provider.Error.OutOfMemory,
                else => Provider.Error.UnexpectedError,
            };
        };
        defer self.allocator.free(error_response);
        std.debug.print("Error response: {s}\n", .{error_response});
        return Provider.Error.ApiError;
    }

    var scanner = std.json.Scanner.initStreaming(self.allocator);
    defer scanner.deinit();

    var buffer: [4096]u8 = undefined;
    var stream_buffer = std.ArrayList(u8).init(self.allocator);
    defer stream_buffer.deinit();

    while (true) {
        const bytes_read = req.reader().read(&buffer) catch |err| {
            return switch (err) {
                error.ConnectionTimedOut, error.ConnectionResetByPeer => Provider.Error.NetworkError,
                error.TlsFailure, error.TlsAlert => Provider.Error.NetworkError,
                error.UnexpectedReadFailure => Provider.Error.UnexpectedError,
                error.EndOfStream => break, // End of stream, exit the loop
                error.HttpChunkInvalid, error.HttpHeadersOversize, error.DecompressionFailure, error.InvalidTrailers => Provider.Error.ApiError,
            };
        };
        if (bytes_read == 0) break; // End of stream

        try stream_buffer.appendSlice(buffer[0..bytes_read]);

        while (true) {
            const newline_index = std.mem.indexOfScalar(u8, stream_buffer.items, '\n') orelse break;
            const line = stream_buffer.items[0..newline_index];

            if (line.len > 0 and !std.mem.startsWith(u8, line, "data: ")) {
                // Skip non-data lines
                stream_buffer.replaceRange(0, newline_index + 1, &[_]u8{}) catch |err| {
                    return switch (err) {
                        error.OutOfMemory => Provider.Error.OutOfMemory,
                    };
                };
                continue;
            }

            if (std.mem.startsWith(u8, line, "data: ")) {
                const json_data = line["data: ".len..];
                if (std.mem.eql(u8, json_data, "[DONE]")) {
                    return; // End of stream
                }

                const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{}) catch |err| {
                    stream_buffer.replaceRange(0, newline_index + 1, &[_]u8{}) catch |replace_err| {
                        return switch (replace_err) {
                            error.OutOfMemory => Provider.Error.OutOfMemory,
                        };
                    };
                    if (err == error.InvalidCharacter) {
                        // Skip invalid JSON and continue
                        continue;
                    }
                    return Provider.Error.ParseError;
                };
                defer parsed.deinit();

                if (parsed.value.object.get("choices")) |choices| {
                    if (choices.array.items.len > 0) {
                        if (choices.array.items[0].object.get("delta")) |delta| {
                            if (delta.object.get("content")) |content| {
                                switch (content) {
                                    .string => |str| {
                                        writer.writeAll(str) catch |err| {
                                            return switch (err) {
                                                error.OutOfMemory => Provider.Error.OutOfMemory,
                                                else => Provider.Error.UnexpectedError,
                                            };
                                        };
                                    },
                                    else => {}, // Ignore non-string content
                                }
                            }
                        }
                    }
                }
            }

            stream_buffer.replaceRange(0, newline_index + 1, &[_]u8{}) catch |err| {
                return switch (err) {
                    error.OutOfMemory => Provider.Error.OutOfMemory,
                };
            };
        }
    }
}

fn createEmbedding(ctx: *anyopaque, options: EmbeddingRequestOptions) Provider.Error![]f32 {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    var response_header_buffer: [2048]u8 = undefined;

    const uri_string = std.fmt.allocPrint(self.allocator, "{s}/embeddings", .{self.config.base_url}) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(uri_string);

    const uri = std.Uri.parse(uri_string) catch {
        return Provider.Error.InvalidRequest;
    };

    // Prepare the request payload
    const payload = .{
        .input = options.input,
        .model = options.model,
        .user = options.user,
        .encoding_format = options.encoding_format,
    };

    const body = std.json.stringifyAlloc(self.allocator, payload, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
        };
    };
    defer self.allocator.free(body);

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
        .authorization = .{ .override = self.authorization_header },
    };

    var req = client.open(.POST, uri, .{
        .server_header_buffer = &response_header_buffer,
        .headers = headers,
        .extra_headers = self.extra_headers.items,
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            error.ConnectionRefused, error.NetworkUnreachable, error.ConnectionTimedOut => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;

    req.send() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.writer().writeAll(body) catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.finish() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };
    req.wait() catch |err| {
        return switch (err) {
            error.ConnectionResetByPeer => Provider.Error.NetworkError,
            else => Provider.Error.UnexpectedError,
        };
    };

    const status = req.response.status;
    if (status != .ok) {
        const error_response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
            return switch (err) {
                error.OutOfMemory => Provider.Error.OutOfMemory,
                else => Provider.Error.UnexpectedError,
            };
        };
        defer self.allocator.free(error_response);
        std.debug.print("Error response: {s}\n", .{error_response});
        return Provider.Error.ApiError;
    }

    const response = req.reader().readAllAlloc(self.allocator, 3276800) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            else => Provider.Error.UnexpectedError,
        };
    };
    defer self.allocator.free(response);

    // Parse the response
    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch |err| {
        return switch (err) {
            error.OutOfMemory => Provider.Error.OutOfMemory,
            else => Provider.Error.ParseError,
        };
    };
    defer parsed.deinit();

    // Extract the embedding from the response
    const data = parsed.value.object.get("data") orelse return Provider.Error.ApiError;
    if (data.array.items.len == 0) return Provider.Error.ApiError;

    const embedding = data.array.items[0].object.get("embedding") orelse return Provider.Error.ApiError;
    var result = try self.allocator.alloc(f32, embedding.array.items.len);
    for (embedding.array.items, 0..) |item, i| {
        // TODO: Why do we need to do casting here? Why does the json think we are having f64 returned? Do we need to do this better to avoid precision loss?
        result[i] = @floatCast(item.float);
    }

    return result;
}
fn getModelInfo(ctx: *anyopaque, model_name: []const u8) Provider.Error!ModelInfo {
    _ = ctx;
    _ = model_name;
    @panic("Not implemented"); // Stub
}

fn getModels(ctx: *anyopaque) Provider.Error![]const ModelInfo {
    _ = ctx;
    @panic("Not implemented"); // Stub
}
