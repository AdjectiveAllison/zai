const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

pub const Signer = struct {
    access_key_id: []const u8,
    secret_access_key: []const u8,
    region: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, access_key_id: []const u8, secret_access_key: []const u8, region: []const u8) Signer {
        return .{
            .allocator = allocator,
            .access_key_id = access_key_id,
            .secret_access_key = secret_access_key,
            .region = region,
        };
    }

    pub fn sign(self: *Signer, method: []const u8, url: []const u8, headers: *const std.StringHashMap([]const u8), payload: []const u8) ![]const u8 {
        const date = headers.get("X-Amz-Date") orelse return error.MissingDateHeader;
        const canonical_request = try self.createCanonicalRequest(method, url, headers, payload);
        defer self.allocator.free(canonical_request);

        const string_to_sign = try self.createStringToSign(date, canonical_request);
        defer self.allocator.free(string_to_sign);

        const signature = try self.calculateSignature(date[0..8], string_to_sign);
        defer self.allocator.free(signature);

        const date_slice: []const u8 = date[0..8];
        const auth_header = try self.createAuthorizationHeader(date_slice, &signature, headers);

        // Debug print
        std.debug.print("Authorization Header: {s}\n", .{auth_header});

        return auth_header;
    }

    fn calculateSignature(self: *Signer, date: []const u8, string_to_sign: []const u8) ![64]u8 {
        var aws4_secret: [4 + 256]u8 = undefined;
        _ = try std.fmt.bufPrint(&aws4_secret, "AWS4{s}", .{self.secret_access_key});

        var k_date: [HmacSha256.mac_length]u8 = undefined;
        hmacSha256(&aws4_secret, date, &k_date);

        var k_region: [HmacSha256.mac_length]u8 = undefined;
        hmacSha256(&k_date, self.region, &k_region);

        var k_service: [HmacSha256.mac_length]u8 = undefined;
        hmacSha256(&k_region, "bedrock", &k_service);

        var k_signing: [HmacSha256.mac_length]u8 = undefined;
        hmacSha256(&k_service, "aws4_request", &k_signing);

        var signature: [HmacSha256.mac_length]u8 = undefined;
        hmacSha256(&k_signing, string_to_sign, &signature);

        var result: [64]u8 = undefined;
        _ = try std.fmt.bufPrint(&result, "{s}", .{std.fmt.fmtSliceHexLower(&signature)});
        return result;
    }

    fn getSigningKey(self: *Signer, date: []const u8) ![]u8 {
        var signing_key = std.ArrayList(u8).init(self.allocator);
        defer signing_key.deinit();

        try signing_key.appendSlice("AWS4");
        try signing_key.appendSlice(self.secret_access_key);

        const k_date = try self.hmacSha256(signing_key.items, date);
        const k_region = try self.hmacSha256(k_date, self.region);
        const k_service = try self.hmacSha256(k_region, "bedrock");
        const k_signing = try self.hmacSha256(k_service, "aws4_request");

        return k_signing;
    }

    pub fn hashSha256(self: *Signer, data: []const u8) ![]u8 {
        var hash: [Sha256.digest_length]u8 = undefined;
        Sha256.hash(data, &hash, .{});
        return try std.fmt.allocPrint(self.allocator, "{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    }

    fn createCanonicalRequest(self: *Signer, method: []const u8, url: []const u8, headers: *const std.StringHashMap([]const u8), payload: []const u8) ![]u8 {
        var canonical_request = std.ArrayList(u8).init(self.allocator);
        defer canonical_request.deinit();

        try canonical_request.appendSlice(method);
        try canonical_request.append('\n');

        const uri = try std.Uri.parse(url);

        // Handle the path
        switch (uri.path) {
            .raw => |raw| try canonical_request.appendSlice(raw),
            .percent_encoded => |encoded| {
                const decoded_buffer = try self.allocator.dupe(u8, encoded);
                defer self.allocator.free(decoded_buffer);
                const decoded = std.Uri.percentDecodeInPlace(decoded_buffer);
                try canonical_request.appendSlice(decoded);
            },
        }
        try canonical_request.append('\n');

        // Add canonical query string (sorted by key)
        try canonical_request.append('\n'); // Empty query string

        // Add canonical headers
        const SortedHeader = struct { name: []const u8, value: []const u8 };
        var sorted_headers = std.ArrayList(SortedHeader).init(self.allocator);
        defer sorted_headers.deinit();

        var headers_it = headers.iterator();
        while (headers_it.next()) |entry| {
            try sorted_headers.append(.{ .name = entry.key_ptr.*, .value = entry.value_ptr.* });
        }

        std.mem.sort(SortedHeader, sorted_headers.items, {}, struct {
            fn lessThan(_: void, a: SortedHeader, b: SortedHeader) bool {
                return std.ascii.lessThanIgnoreCase(a.name, b.name);
            }
        }.lessThan);

        for (sorted_headers.items) |header| {
            const lower_name = try std.ascii.allocLowerString(self.allocator, header.name);
            defer self.allocator.free(lower_name);
            try canonical_request.appendSlice(lower_name);
            try canonical_request.append(':');
            try canonical_request.appendSlice(std.mem.trim(u8, header.value, " "));
            try canonical_request.append('\n');
        }
        try canonical_request.append('\n');

        // Add signed headers
        for (sorted_headers.items, 0..) |header, i| {
            if (i > 0) try canonical_request.append(';');
            const lower_name = try std.ascii.allocLowerString(self.allocator, header.name);
            defer self.allocator.free(lower_name);
            try canonical_request.appendSlice(lower_name);
        }
        try canonical_request.append('\n');

        // Add payload hash
        const payload_hash = try self.hashSha256(payload);
        try canonical_request.appendSlice(payload_hash);

        return canonical_request.toOwnedSlice();
    }

    fn createStringToSign(self: *Signer, date: []const u8, canonical_request: []const u8) ![]u8 {
        var string_to_sign = std.ArrayList(u8).init(self.allocator);
        defer string_to_sign.deinit();

        try string_to_sign.appendSlice("AWS4-HMAC-SHA256\n");
        try string_to_sign.appendSlice(date);
        try string_to_sign.append('\n');
        try string_to_sign.appendSlice(date[0..8]);
        try string_to_sign.append('/');
        try string_to_sign.appendSlice(self.region);
        try string_to_sign.appendSlice("/bedrock/aws4_request\n");

        const request_hash = try self.hashSha256(canonical_request);
        try string_to_sign.appendSlice(request_hash);

        return string_to_sign.toOwnedSlice();
    }

    fn createAuthorizationHeader(self: *Signer, date: []const u8, signature: *const [64]u8, headers: *const std.StringHashMap([]const u8)) ![]u8 {
        var auth_header = std.ArrayList(u8).init(self.allocator);
        defer auth_header.deinit();

        try auth_header.appendSlice("AWS4-HMAC-SHA256 ");
        try auth_header.appendSlice("Credential=");
        try auth_header.appendSlice(self.access_key_id);
        try auth_header.append('/');
        try auth_header.appendSlice(date);
        try auth_header.append('/');
        try auth_header.appendSlice(self.region);
        try auth_header.appendSlice("/bedrock/aws4_request,");

        try auth_header.appendSlice("SignedHeaders=");
        var signed_headers = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (signed_headers.items) |item| {
                self.allocator.free(item);
            }
            signed_headers.deinit();
        }

        var headers_it = headers.iterator();
        while (headers_it.next()) |entry| {
            const lower_key = try std.ascii.allocLowerString(self.allocator, entry.key_ptr.*);
            try signed_headers.append(lower_key);
        }

        std.mem.sort([]const u8, signed_headers.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        for (signed_headers.items, 0..) |header, i| {
            if (i > 0) try auth_header.append(';');
            try auth_header.appendSlice(header);
        }
        try auth_header.append(',');

        try auth_header.appendSlice("Signature=");
        try auth_header.appendSlice(signature);

        return auth_header.toOwnedSlice();
    }

    pub fn getFormattedDate(self: *Signer) ![]const u8 {
        const timestamp = std.time.timestamp();
        const datetime = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        return std.fmt.allocPrint(self.allocator, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
            datetime.getEpochDay().calculateYearDay().year,
            @intFromEnum(datetime.getEpochDay().calculateYearDay().calculateMonthDay().month),
            datetime.getEpochDay().calculateYearDay().calculateMonthDay().day_index + 1,
            datetime.getDaySeconds().getHoursIntoDay(),
            datetime.getDaySeconds().getMinutesIntoHour(),
            datetime.getDaySeconds().getSecondsIntoMinute(),
        });
    }

    fn hashSha256Internal(self: *Signer, data: []const u8) ![]u8 {
        var hash: [Sha256.digest_length]u8 = undefined;
        Sha256.hash(data, &hash, .{});
        return try std.fmt.allocPrint(self.allocator, "{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    }

    fn hmacSha256(key: []const u8, data: []const u8, out: *[HmacSha256.mac_length]u8) void {
        HmacSha256.create(out, data, key);
    }
};
