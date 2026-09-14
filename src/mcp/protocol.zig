//! MCP message classification and JSON-RPC envelopes.
//!
//! This module knows the wire and nothing else: no graph, no snapshot, no tool.
//! It decides which protocol era a message belongs to and writes the envelopes
//! both eras share, so the two eras cannot drift into two dispatchers.
//!
//! Two eras are served by one dispatcher:
//!
//! - `2026-07-28` ("modern"): every request carries its protocol version and
//!   client capabilities in `params._meta`, and the server keeps no state
//!   between requests.
//! - `2025-06-18` ("legacy"): the client opens with `initialize`, and later
//!   requests carry no version of their own.
//!
//! A request carrying the modern `_meta` version is modern whatever came before
//! it on the same stream. A request without it is legacy, and is served only
//! after `initialize`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Stringify = std.json.Stringify;
const Writer = std.Io.Writer;

pub const modern_version = "2026-07-28";
pub const legacy_version = "2025-06-18";

pub const server_name = "semidx";
pub const server_title = "semidx local MCP preview";
/// The product version, from `build.zig.zon`. It versions the binary and its
/// behavior, never the semantic contract, which stays unpublished.
pub const product_version = @import("semidx_version").product_version;

/// Messages longer than this are refused rather than buffered without bound.
pub const max_message_bytes: usize = 1 << 20;

pub const meta_protocol_version = "io.modelcontextprotocol/protocolVersion";
pub const meta_client_capabilities = "io.modelcontextprotocol/clientCapabilities";
pub const meta_server_info = "io.modelcontextprotocol/serverInfo";

pub const ErrorCode = enum(i32) {
    parse_error = -32700,
    invalid_request = -32600,
    method_not_found = -32601,
    invalid_params = -32602,
    internal_error = -32603,
    /// Defined by `2026-07-28` in the range reserved for the MCP specification.
    unsupported_protocol_version = -32022,
};

pub const Era = enum { modern, legacy };

pub const Id = union(enum) {
    integer: i64,
    string: []const u8,
};

pub const Request = struct {
    id: Id,
    method: []const u8,
    params: ?std.json.ObjectMap,
};

pub const Notification = struct {
    method: []const u8,
};

/// A line that is not a request or notification this server can act on.
pub const Invalid = struct {
    /// Absent when the id could not be read.
    id: ?Id,
    code: ErrorCode,
    message: []const u8,
};

pub const Message = union(enum) {
    request: Request,
    notification: Notification,
    invalid: Invalid,
};

/// Classifies one line. Everything returned borrows from `arena`.
pub fn parse(arena: Allocator, line: []const u8) Allocator.Error!Message {
    const value = std.json.parseFromSliceLeaky(std.json.Value, arena, line, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .invalid = .{ .id = null, .code = .parse_error, .message = "Parse error: invalid JSON" } },
    };
    const object = switch (value) {
        .object => |object| object,
        // Batches were removed in 2025-06-18 and are not part of 2026-07-28.
        .array => return .{ .invalid = .{ .id = null, .code = .invalid_request, .message = "JSON-RPC batches are not supported" } },
        else => return .{ .invalid = .{ .id = null, .code = .invalid_request, .message = "a JSON-RPC message must be an object" } },
    };

    var id: ?Id = null;
    var has_id = false;
    if (object.get("id")) |raw_id| {
        has_id = true;
        id = switch (raw_id) {
            .integer => |n| .{ .integer = n },
            .string => |s| .{ .string = s },
            else => return .{ .invalid = .{ .id = null, .code = .invalid_request, .message = "a request id must be a string or an integer" } },
        };
    }

    const version_ok = if (object.get("jsonrpc")) |v| v == .string and std.mem.eql(u8, v.string, "2.0") else false;
    if (!version_ok) {
        return .{ .invalid = .{ .id = id, .code = .invalid_request, .message = "jsonrpc must be \"2.0\"" } };
    }

    const method = if (object.get("method")) |m| switch (m) {
        .string => |s| s,
        else => return .{ .invalid = .{ .id = id, .code = .invalid_request, .message = "method must be a string" } },
    } else return .{ .invalid = .{ .id = id, .code = .invalid_request, .message = "a client message must be a request or a notification" } };

    // A notification is never answered, not even when its params are malformed.
    if (!has_id) return .{ .notification = .{ .method = method } };

    var params: ?std.json.ObjectMap = null;
    if (object.get("params")) |raw_params| {
        params = switch (raw_params) {
            .object => |p| p,
            else => return .{ .invalid = .{ .id = id, .code = .invalid_params, .message = "params must be an object" } },
        };
    }
    return .{ .request = .{ .id = id.?, .method = method, .params = params } };
}

/// How a request's `_meta` places it among the eras.
pub const MetaCheck = union(enum) {
    /// No modern protocol version: a legacy request.
    legacy,
    modern,
    /// A modern request this server must refuse before dispatch.
    refused: Refusal,
};

pub const Refusal = struct {
    code: ErrorCode,
    message: []const u8,
    /// Set for `unsupported_protocol_version`.
    requested: ?[]const u8 = null,
};

pub fn checkMeta(params: ?std.json.ObjectMap) MetaCheck {
    const p = params orelse return .legacy;
    const meta = switch (p.get("_meta") orelse return .legacy) {
        .object => |m| m,
        else => return .{ .refused = .{ .code = .invalid_params, .message = "_meta must be an object" } },
    };
    const version = switch (meta.get(meta_protocol_version) orelse return .legacy) {
        .string => |s| s,
        else => return .{ .refused = .{ .code = .invalid_params, .message = meta_protocol_version ++ " must be a string" } },
    };
    if (!std.mem.eql(u8, version, modern_version)) {
        return .{ .refused = .{ .code = .unsupported_protocol_version, .message = "Unsupported protocol version", .requested = version } };
    }
    switch (meta.get(meta_client_capabilities) orelse .null) {
        .object => {},
        else => return .{ .refused = .{ .code = .invalid_params, .message = meta_client_capabilities ++ " is required and must be an object" } },
    }
    return .modern;
}

// -- writing ----------------------------------------------------------------

/// Writes a JSON string, replacing invalid UTF-8 with U+FFFD.
///
/// Paths and designators come from files, and a file name or source line is
/// not guaranteed to be UTF-8. `Stringify.write` would render such bytes as an
/// array of numbers, which silently changes a field's type; stdio messages
/// must be UTF-8 JSON, so the replacement is made visible instead.
pub fn writeString(s: *Stringify, bytes: []const u8) Writer.Error!void {
    if (std.unicode.utf8ValidateSlice(bytes)) return s.write(bytes);
    try s.beginWriteRaw();
    try s.writer.writeByte('"');
    var i: usize = 0;
    while (i < bytes.len) {
        const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch 0;
        if (len != 0 and i + len <= bytes.len) {
            if (std.unicode.utf8Decode(bytes[i..][0..len])) |_| {
                try Stringify.encodeJsonStringChars(bytes[i..][0..len], s.options, s.writer);
                i += len;
                continue;
            } else |_| {}
        }
        try s.writer.writeAll("\\ufffd");
        i += 1;
    }
    try s.writer.writeByte('"');
    s.endWriteRaw();
}

pub fn writeId(s: *Stringify, id: Id) Writer.Error!void {
    switch (id) {
        .integer => |n| try s.write(n),
        .string => |str| try writeString(s, str),
    }
}

/// Opens `{"jsonrpc":"2.0","id":…,"result":{` and, for the modern era, writes
/// the fields every modern result carries. The caller writes the rest of the
/// result's fields and then calls `endResult`.
pub fn beginResult(s: *Stringify, id: Id, era: Era) Writer.Error!void {
    try s.beginObject();
    try s.objectField("jsonrpc");
    try s.write("2.0");
    try s.objectField("id");
    try writeId(s, id);
    try s.objectField("result");
    try s.beginObject();
    if (era == .modern) {
        try s.objectField("resultType");
        try s.write("complete");
        try s.objectField("_meta");
        try s.beginObject();
        try s.objectField(meta_server_info);
        try writeImplementation(s);
        try s.endObject();
    }
}

pub fn endResult(s: *Stringify) Writer.Error!void {
    try s.endObject();
    try s.endObject();
}

pub fn writeImplementation(s: *Stringify) Writer.Error!void {
    try s.beginObject();
    try s.objectField("name");
    try s.write(server_name);
    try s.objectField("title");
    try s.write(server_title);
    try s.objectField("version");
    try s.write(product_version);
    try s.endObject();
}

/// Writes a complete error response object. `requested` adds the
/// `UnsupportedProtocolVersionError` data.
pub fn writeError(
    s: *Stringify,
    id: ?Id,
    code: ErrorCode,
    message: []const u8,
    requested: ?[]const u8,
) Writer.Error!void {
    try s.beginObject();
    try s.objectField("jsonrpc");
    try s.write("2.0");
    if (id) |value| {
        try s.objectField("id");
        try writeId(s, value);
    }
    try s.objectField("error");
    try s.beginObject();
    try s.objectField("code");
    try s.write(@intFromEnum(code));
    try s.objectField("message");
    try writeString(s, message);
    if (code == .unsupported_protocol_version) {
        try s.objectField("data");
        try s.beginObject();
        try s.objectField("supported");
        try s.beginArray();
        try s.write(modern_version);
        try s.endArray();
        try s.objectField("requested");
        try writeString(s, requested orelse "");
        try s.endObject();
    }
    try s.endObject();
    try s.endObject();
}

const testing = std.testing;

fn parseForTest(arena: *std.heap.ArenaAllocator, line: []const u8) !Message {
    return parse(arena.allocator(), line);
}

test "requests, notifications, and invalid lines are told apart" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const request = try parseForTest(&arena, "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/list\",\"params\":{}}");
    try testing.expectEqual(@as(i64, 7), request.request.id.integer);
    try testing.expectEqualStrings("tools/list", request.request.method);

    const string_id = try parseForTest(&arena, "{\"jsonrpc\":\"2.0\",\"id\":\"a\",\"method\":\"x\"}");
    try testing.expectEqualStrings("a", string_id.request.id.string);
    try testing.expect(string_id.request.params == null);

    const notification = try parseForTest(&arena, "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}");
    try testing.expectEqualStrings("notifications/initialized", notification.notification.method);
    const malformed_notification = try parseForTest(&arena, "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":[1]}");
    try testing.expectEqualStrings("notifications/cancelled", malformed_notification.notification.method);

    const cases = [_]struct { line: []const u8, code: ErrorCode, has_id: bool }{
        .{ .line = "{not json", .code = .parse_error, .has_id = false },
        .{ .line = "[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"x\"}]", .code = .invalid_request, .has_id = false },
        .{ .line = "42", .code = .invalid_request, .has_id = false },
        .{ .line = "{\"jsonrpc\":\"2.0\",\"id\":null,\"method\":\"x\"}", .code = .invalid_request, .has_id = false },
        .{ .line = "{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"x\"}", .code = .invalid_request, .has_id = true },
        .{ .line = "{\"jsonrpc\":\"2.0\",\"id\":1}", .code = .invalid_request, .has_id = true },
        .{ .line = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"x\",\"params\":[]}", .code = .invalid_params, .has_id = true },
    };
    for (cases) |case| {
        const message = try parseForTest(&arena, case.line);
        try testing.expectEqual(case.code, message.invalid.code);
        try testing.expectEqual(case.has_id, message.invalid.id != null);
    }
}

test "the modern era is selected only by the request's own _meta" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const cases = [_]struct { params: []const u8, expected: std.meta.Tag(MetaCheck), code: ?ErrorCode = null }{
        .{ .params = "{}", .expected = .legacy },
        .{ .params = "{\"_meta\":{\"progressToken\":1}}", .expected = .legacy },
        .{ .params = "{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{}}}", .expected = .modern },
        .{ .params = "{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\"}}", .expected = .refused, .code = .invalid_params },
        .{ .params = "{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"1900-01-01\",\"io.modelcontextprotocol/clientCapabilities\":{}}}", .expected = .refused, .code = .unsupported_protocol_version },
        .{ .params = "{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":20260728}}", .expected = .refused, .code = .invalid_params },
        .{ .params = "{\"_meta\":[]}", .expected = .refused, .code = .invalid_params },
    };
    for (cases) |case| {
        const line = try std.fmt.allocPrint(arena.allocator(), "{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{s}}}", .{case.params});
        const message = try parseForTest(&arena, line);
        const check = checkMeta(message.request.params);
        try testing.expectEqual(case.expected, std.meta.activeTag(check));
        if (case.code) |code| try testing.expectEqual(code, check.refused.code);
    }
    try testing.expectEqual(std.meta.Tag(MetaCheck).legacy, std.meta.activeTag(checkMeta(null)));
}

test "invalid utf-8 is replaced rather than changing a string's type" {
    var out: Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var s: Stringify = .{ .writer = &out.writer };
    try s.beginArray();
    try writeString(&s, "ok\n");
    try writeString(&s, "a\xffb\xc3");
    try writeString(&s, "é");
    try s.endArray();
    try testing.expectEqualStrings("[\"ok\\n\",\"a\\ufffdb\\ufffd\",\"é\"]", out.written());
}

test "error envelopes carry the fields each era requires" {
    var out: Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var s: Stringify = .{ .writer = &out.writer };
    try writeError(&s, .{ .integer = 1 }, .unsupported_protocol_version, "Unsupported protocol version", "1900-01-01");
    try testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32022,\"message\":\"Unsupported protocol version\"," ++
            "\"data\":{\"supported\":[\"2026-07-28\"],\"requested\":\"1900-01-01\"}}}",
        out.written(),
    );

    out.clearRetainingCapacity();
    s = .{ .writer = &out.writer };
    try writeError(&s, null, .parse_error, "Parse error: invalid JSON", null);
    try testing.expectEqualStrings("{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32700,\"message\":\"Parse error: invalid JSON\"}}", out.written());

    out.clearRetainingCapacity();
    s = .{ .writer = &out.writer };
    try beginResult(&s, .{ .string = "x" }, .modern);
    try endResult(&s);
    try testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":\"x\",\"result\":{\"resultType\":\"complete\",\"_meta\":{\"io.modelcontextprotocol/serverInfo\":" ++
            "{\"name\":\"semidx\",\"title\":\"semidx local MCP preview\",\"version\":\"" ++ product_version ++ "\"}}}}",
        out.written(),
    );

    out.clearRetainingCapacity();
    s = .{ .writer = &out.writer };
    try beginResult(&s, .{ .integer = 2 }, .legacy);
    try endResult(&s);
    try testing.expectEqualStrings("{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}", out.written());
}
