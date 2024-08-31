const std = @import("std");

pub const ZaiError = error{
    OutOfMemory,
    ApiError,
    InvalidRequest,
    NetworkError,
    ParseError,
    UnexpectedError,
    UnsupportedRole,
    UnknownRole,
    // Add more error types as needed
};

pub const ProviderType = enum {
    OpenAI,
    Anthropic,
    GoogleVertex,
    AmazonBedrock,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const StreamHandler = struct {
    context: ?*anyopaque = null,
    writeFn: *const fn (context: ?*anyopaque, content: []const u8) ZaiError!void,

    pub fn write(self: StreamHandler, content: []const u8) ZaiError!void {
        return self.writeFn(self.context, content);
    }
};
