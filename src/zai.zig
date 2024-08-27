const std = @import("std");
pub const AI = @import("AI.zig");
pub const ChatCompletion = @import("ChatCompletion.zig");
pub const Embeddings = @import("Embeddings.zig");
pub const StreamHandler = @import("shared.zig").StreamHandler;
pub const providers = @import("providers.zig");
pub const Provider = providers.Provider;
pub const Message = @import("shared.zig").Message;
pub const CompletionPayload = @import("shared.zig").CompletionPayload;
//TODO: Handle organization in relevant cases(OpenAI)
// If ogranization is passed, it's simply a header to openAI:
//"OpenAI-Organization: YOUR_ORG_ID"

//TODO: Figure out if there is a smoothe way to handle the responses and give back only relevant data to the caller(e.g. return whole api response object or just message data, maybe make it a choice for the caller what they receive, with a default to just the message to make the api smoothe as silk).
// things that will be different between providers that I can handle and seperate:
// 1. Model list(for enums or selection)
// 2. no tool calls on messages on some providers(yet, and potentially lagging function_call parameter names)
// 3. Together may use repetition_penalty instead of frequency_penalty(need to confirm)
// 4. Organization for OpenAI(Potentially other headers later on)
