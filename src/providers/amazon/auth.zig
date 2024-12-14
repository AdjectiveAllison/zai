const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const crypto = std.crypto;

// Constants for AWS Signature Version 4
const AWS4_HMAC_SHA256 = "AWS4-HMAC-SHA256";
const AWS4_REQUEST = "aws4_request";
const BEDROCK_SERVICE = "bedrock";

pub const SignatureError = error{
    InvalidDate,
    InvalidRegion,
    InvalidCredentials,
    HashingError,
} || std.fmt.AllocPrintError || Allocator.Error;

// Main structure to hold signature computation data
pub const SignatureInput = struct {
    method: []const u8,
    uri_path: []const u8,
    region: []const u8,
    access_key: []const u8,
    secret_key: []const u8,
    payload: []const u8,
    headers: std.ArrayList(std.http.Header),
    timestamp: []const u8,
};

// Headers required (Need to be alphabetically sorted for SignedHeaders):
// "host" with value bedrock-runtime.{region}.amazonaws.com
// can use `self.config.region` inside of `AmazonBedrockProvider`.
// "x-amz-date" with getTimeStamp()
// "content-type" with "application/json"

pub fn createSignature(allocator: Allocator, input: SignatureInput) ![]const u8 {
    // 1. Create canonical request
    const canonical_request = try createCanonicalRequest(allocator, input);
    defer allocator.free(canonical_request);

    // 2. Create string to sign
    const credential_scope = try createCredentialScope(allocator, input);
    defer allocator.free(credential_scope);

    const string_to_sign = try createStringToSign(
        allocator,
        canonical_request,
        credential_scope,
        input.timestamp,
    );
    defer allocator.free(string_to_sign);

    // 3. Calculate signing key
    var signing_key: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    try calculateSigningKey(
        input.secret_key,
        input.timestamp[0..8], // Date portion of timestamp
        input.region,
        &signing_key,
    );

    // 4. Calculate final signature
    var signature: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    crypto.auth.hmac.sha2.HmacSha256.create(&signature, string_to_sign, &signing_key);

    // 5. Create authorization header
    const signed_headers = try createSignedHeadersList(allocator, input.headers);
    defer allocator.free(signed_headers);

    return try fmt.allocPrint(
        allocator,
        AWS4_HMAC_SHA256 ++ " Credential={s}/{s}/{s}/" ++ BEDROCK_SERVICE ++ "/" ++ AWS4_REQUEST ++
            ", SignedHeaders={s}, Signature={x}",
        .{
            input.access_key,
            input.timestamp[0..8],
            input.region,
            signed_headers,
            fmt.fmtSliceHexLower(&signature),
        },
    );
}

fn createCanonicalRequest(allocator: Allocator, input: SignatureInput) ![]const u8 {
    // 1. URI encode the path
    const encoded_path = try uriEncodeGreedy(allocator, input.uri_path);
    defer allocator.free(encoded_path);

    // 2. Create canonical headers string
    const canonical_headers = try createCanonicalHeaders(allocator, input.headers);
    defer allocator.free(canonical_headers);

    // 3. Create signed headers list
    const signed_headers = try createSignedHeadersList(allocator, input.headers);
    defer allocator.free(signed_headers);

    // 4. Calculate payload hash
    const payload_hash = try hashPayload(allocator, input.payload);
    defer allocator.free(payload_hash);

    // 5. Combine all parts
    return fmt.allocPrint(allocator, "{s}\n{s}\n\n{s}\n{s}\n{s}", .{
        input.method,
        encoded_path,
        canonical_headers,
        signed_headers,
        payload_hash,
    });
}

fn createStringToSign(
    allocator: Allocator,
    canonical_request: []const u8,
    credential_scope: []const u8,
    timestamp: []const u8,
) ![]const u8 {
    var hash: [crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(canonical_request, &hash, .{});

    return fmt.allocPrint(
        allocator,
        AWS4_HMAC_SHA256 ++ "\n{s}\n{s}\n{x}",
        .{
            timestamp,
            credential_scope,
            fmt.fmtSliceHexLower(&hash),
        },
    );
}

fn createCredentialScope(allocator: Allocator, input: SignatureInput) ![]const u8 {
    return fmt.allocPrint(
        allocator,
        "{s}/{s}/" ++ BEDROCK_SERVICE ++ "/" ++ AWS4_REQUEST,
        .{
            input.timestamp[0..8],
            input.region,
        },
    );
}

fn calculateSigningKey(
    secret_key: []const u8,
    date: []const u8,
    region: []const u8,
    out: *[crypto.auth.hmac.sha2.HmacSha256.mac_length]u8,
) !void {
    var date_key: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    var date_region_key: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    var date_region_service_key: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;

    // Prepare AWS4 + secret key
    var secret = std.ArrayList(u8).init(std.heap.page_allocator);
    defer secret.deinit();
    try secret.appendSlice("AWS4");
    try secret.appendSlice(secret_key);

    // kDate = HMAC("AWS4" + secretKey, date)
    crypto.auth.hmac.sha2.HmacSha256.create(&date_key, date, secret.items);

    // kRegion = HMAC(kDate, region)
    crypto.auth.hmac.sha2.HmacSha256.create(&date_region_key, region, &date_key);

    // kService = HMAC(kRegion, service)
    crypto.auth.hmac.sha2.HmacSha256.create(&date_region_service_key, BEDROCK_SERVICE, &date_region_key);

    // kSigning = HMAC(kService, "aws4_request")
    crypto.auth.hmac.sha2.HmacSha256.create(out, AWS4_REQUEST, &date_region_service_key);
}

fn createCanonicalHeaders(allocator: Allocator, headers: std.ArrayList(std.http.Header)) ![]const u8 {
    var canonical = std.ArrayList(u8).init(allocator);
    defer canonical.deinit();

    // Sort headers by name
    std.mem.sort(std.http.Header, headers.items, {}, sortHeaderName);

    // Build canonical headers string
    for (headers.items) |header| {
        const lower_name = try std.ascii.allocLowerString(allocator, header.name);
        defer allocator.free(lower_name);

        const trimmed_value = std.mem.trim(u8, header.value, &std.ascii.whitespace);
        try canonical.writer().print("{s}:{s}\n", .{ lower_name, trimmed_value });
    }

    return canonical.toOwnedSlice();
}

fn createSignedHeadersList(allocator: Allocator, headers: std.ArrayList(std.http.Header)) ![]const u8 {
    var signed_headers = std.ArrayList(u8).init(allocator);
    defer signed_headers.deinit();

    // Sort headers by name
    std.mem.sort(std.http.Header, headers.items, {}, sortHeaderName);

    // Build semicolon-separated list of header names
    for (headers.items, 0..) |header, i| {
        const lower_name = try std.ascii.allocLowerString(allocator, header.name);
        defer allocator.free(lower_name);

        try signed_headers.appendSlice(lower_name);
        if (i < headers.items.len - 1) {
            try signed_headers.append(';');
        }
    }

    return signed_headers.toOwnedSlice();
}

fn hashPayload(allocator: Allocator, payload: []const u8) ![]const u8 {
    var hash: [crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(payload, &hash, .{});

    // Convert to hex string
    var hex_output: [crypto.hash.sha2.Sha256.digest_length * 2]u8 = undefined;
    _ = try std.fmt.bufPrint(&hex_output, "{x}", .{fmt.fmtSliceHexLower(&hash)});

    return allocator.dupe(u8, &hex_output);
}

pub fn getTimeStamp(allocator: Allocator) ![]const u8 {
    const epoch_sec = std.time.epoch.EpochSeconds{ .secs = @intCast(std.time.timestamp()) };
    const year_day = epoch_sec.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = epoch_sec.getDaySeconds();

    return std.fmt.allocPrint(allocator, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    });
}

// mem.sort(std.http.Header, list of std.http.Header, {}, sortHeaderName);
fn sortHeaderName(_: void, lhs: std.http.Header, rhs: std.http.Header) bool {
    return std.ascii.lessThanIgnoreCase(lhs.name, rhs.name);
}

pub fn uriEncode(allocator: Allocator, value: []const u8) ![]const u8 {
    const encoder = UriEncoder(false){ .raw = value };
    return fmt.allocPrint(allocator, "{}", .{encoder});
}

pub fn uriEncodeGreedy(allocator: Allocator, value: []const u8) ![]const u8 {
    const encoder = UriEncoder(true){ .raw = value };
    return fmt.allocPrint(allocator, "{}", .{encoder});
}

//nabbed from here: https://github.com/by-nir/aws-sdk-zig/blob/main/smithy/runtime/operation/serial.zig
pub fn UriEncoder(comptime greedy: bool) type {
    return struct {
        raw: []const u8,

        pub fn format(self: @This(), comptime _: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
            var start: usize = 0;
            for (self.raw, 0..) |char, index| {
                if (isValidUrlChar(char)) continue;
                try writer.print("{s}%{X:0>2}", .{ self.raw[start..index], char });
                start = index + 1;
            }
            try writer.writeAll(self.raw[start..]);
        }

        fn isValidUrlChar(char: u8) bool {
            return switch (char) {
                '/' => greedy,
                // zig fmt: off
                ' ', ':', ',', '?', '#', '[', ']', '{', '}', '|', '@', '!', '$', '&',
                '\'', '(', ')', '*', '+', ';', '=', '%', '<', '>', '"', '^', '`', '\\' => false,
                // zig fmt: on
                else => !std.ascii.isControl(char),
            };
        }
    };
}
