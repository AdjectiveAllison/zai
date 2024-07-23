const std = @import("std");
pub const AI = @import("AI.zig");
pub const ChatCompletion = @import("ChatCompletion.zig");
pub const Embeddings = @import("Embeddings.zig");
pub const StreamHandler = @import("shared.zig").StreamHandler;
pub const Provider = @import("shared.zig").Provider;
pub const Message = @import("shared.zig").Message;
pub const CompletionPayload = @import("shared.zig").CompletionPayload;
pub const ChatCompletionModel = @import("providers/OctoAI.zig").ChatCompletionModel;
// std.meta.stringToEnum could be very useful for model strings -> enum conversion. null is returned if enum isn't found, thus we could early-exit out of clients if they pass in an incorrect one.

//TODO: Handle organization in relevant cases(OpenAI)
// If ogranization is passed, it's simply a header to openAI:
//"OpenAI-Organization: YOUR_ORG_ID"

// TODO: Move this leftover embeddings stuff
// pub const AI = struct {
//     pub fn embeddings(
//         self: *AI,
//         payload: EmbeddingsPayload,
//         arena: std.mem.Allocator,
//     ) !Embeddings {
//         var client = std.http.Client{
//             .allocator = self.gpa,
//         };
//         defer client.deinit();

//         const uri_string = try std.fmt.allocPrint(self.gpa, "{s}/embeddings", .{self.base_url});
//         defer self.gpa.free(uri_string);
//         const uri = std.Uri.parse(uri_string) catch unreachable;

//         const body = try std.json.stringifyAlloc(self.gpa, payload, .{
//             .whitespace = .minified,
//             .emit_null_optional_fields = false,
//         });

//         defer self.gpa.free(body);

//         var req = try client.open(.POST, uri, self.headers, .{});
//         defer req.deinit();

//         req.transfer_encoding = .chunked;

//         try req.send(.{});
//         try req.writer().writeAll(body);
//         try req.finish();
//         try req.wait();

//         const status = req.response.status;
//         if (status != .ok) {
//             //TODO: Do this better.
//             std.debug.print("STATUS NOT OKAY\n{s}\nWE GOT AN ERROR\n", .{status.phrase().?});
//         }

//         const response = req.reader().readAllAlloc(self.gpa, 3276800) catch unreachable;
//         //TODO: add in verbosity check to print responses.
//         defer self.gpa.free(response);

//         // std.debug.print("full response:\n{s}\n", .{response});
//         const parsed_embeddings = try std.json.parseFromSliceLeaky(
//             Embeddings,
//             arena,
//             response,
//             .{ .ignore_unknown_fields = true },
//         );

//         return parsed_embeddings;
//     }
// };

// pub const EmbeddingsPayload = struct {
//     input: []const u8,
//     model: []const u8,
// };

// pub const Embeddings = struct {
//     id: []const u8,
//     data: []EmbeddingsData,
//     // model: []const u8,
//     // usage: struct {
//     //     total_tokens: u64,
//     //     prompt_tokens: u64,
//     // },
// };

// pub const EmbeddingsData = struct {
//     index: u32,
//     object: []const u8,
//     // TODO: Explore @Vector() and if it can be used in zig.
//     embedding: []f32,
// };

//TODO: enums for models available on multiple providers.

//TODO: Figure out if there is a smoothe way to handle the responses and give back only relevant data to the caller(e.g. return whole api response object or just message data, maybe make it a choice for the caller what they receive, with a default to just the message to make the api smoothe as silk).
// things that will be different between providers that I can handle and seperate:
// 1. Model list(for enums or selection)
// 2. no tool calls on messages on some providers(yet, and potentially lagging function_call parameter names)
// 3. Together may use repetition_penalty instead of frequency_penalty(need to confirm)
// 4. Organization for OpenAI(Potentially other headers later on)
