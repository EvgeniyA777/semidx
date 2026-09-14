//! The local MCP stdio preview.
//!
//! A consumer of the graph, not a producer: the server scans a configured root
//! into an in-memory index, publishes one snapshot, and answers every tool call
//! from the snapshot that is published when the call arrives. A refresh builds
//! and publishes the next snapshot before any later call can observe it, so no
//! response mixes two graph states.
//!
//! This is an experimental consumer interface. It publishes no semantic
//! contract version, and its tool schemas may change with the implementation.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Reader = std.Io.Reader;
const Stringify = std.json.Stringify;
const Writer = std.Io.Writer;

const semidx = @import("semidx");

pub const protocol = @import("protocol.zig");
pub const stdio = @import("stdio.zig");
pub const tools = @import("tools.zig");

const model = semidx.model;

pub const Options = struct {
    /// The source tree to index. Unit paths in results are relative to it.
    root: []const u8,
    /// Opt-in: tool results may carry the source text producers recorded as
    /// evidence for each claim, bounded per claim.
    evidence_text: bool = false,
};

const instructions = "semidx answers from an in-memory semantic graph of the configured root. " ++
    "Every relationship carries its resolution (fact, unresolved, approximate), freshness, and producer; " ++
    "an unresolved designator is a name the graph could not resolve, not a relationship to a definition of that name. " ++
    "Results carry paths and ranges, not source text. Call semidx_refresh after editing files.";

/// How long a client may cache the tool list and discovery result. The tool
/// set is fixed for the lifetime of the binary.
const list_ttl_ms: u64 = 3_600_000;

pub const Server = struct {
    gpa: Allocator,
    io: Io,
    options: Options,
    /// Diagnostics for the operator. Never stdout.
    log: *Writer,
    index: semidx.Index,
    snapshot: semidx.Snapshot,
    last_scan: semidx.Index.ScanOutcome,
    /// Set by a legacy `initialize`. Modern requests never read it.
    legacy_initialized: bool,
    message_arena: std.heap.ArenaAllocator,

    /// Scans `options.root` and publishes the first snapshot.
    pub fn init(gpa: Allocator, io: Io, options: Options, log: *Writer) !Server {
        var index = try semidx.Index.init(gpa, options.root);
        errdefer index.deinit();

        var found = try semidx.source.discovery.scan(gpa, io, options.root, .{});
        defer found.deinit();
        const outcome = try index.applyScan(found);
        var snapshot = try index.publish();
        errdefer snapshot.deinit();

        try log.print("semidx-mcp: indexed {d} source units under {s}; snapshot revision {d}; {d} scan diagnostics\n", .{
            snapshot.units.len,
            options.root,
            snapshot.revision,
            found.diagnostics.len,
        });
        try log.flush();

        return .{
            .gpa = gpa,
            .io = io,
            .options = options,
            .log = log,
            .index = index,
            .snapshot = snapshot,
            .last_scan = outcome,
            .legacy_initialized = false,
            .message_arena = std.heap.ArenaAllocator.init(gpa),
        };
    }

    pub fn deinit(self: *Server) void {
        self.message_arena.deinit();
        self.snapshot.deinit();
        self.index.deinit();
        self.* = undefined;
    }

    pub fn serve(self: *Server, in: *Reader, out: *Writer) !void {
        return stdio.serve(self, in, out);
    }

    fn logf(self: *Server, comptime fmt: []const u8, args: anytype) Writer.Error!void {
        try self.log.print("semidx-mcp: " ++ fmt ++ "\n", args);
        try self.log.flush();
    }

    /// Answers one message with zero or one complete line on `out`.
    ///
    /// The response is rendered in full before any of it is written, so a
    /// failure while rendering can still be answered with an error instead of
    /// a truncated line.
    pub fn handleLine(self: *Server, line: []const u8, out: *Writer) !void {
        defer _ = self.message_arena.reset(.retain_capacity);
        const arena = self.message_arena.allocator();

        var response: Writer.Allocating = .init(arena);
        var request_id: ?protocol.Id = null;
        self.respond(arena, line, &response.writer, &request_id) catch |err| {
            try self.logf("internal error while answering a message: {t}", .{err});
            response.clearRetainingCapacity();
            var s: Stringify = .{ .writer = &response.writer };
            try protocol.writeError(&s, request_id, .internal_error, "Internal error", null);
        };
        const written = response.written();
        if (written.len == 0) return;
        try out.writeAll(written);
        try out.writeByte('\n');
    }

    pub fn oversized(self: *Server, out: *Writer) !void {
        try self.logf("refused a message longer than {d} bytes", .{protocol.max_message_bytes});
        var buffer: [256]u8 = undefined;
        var fixed: Writer = .fixed(&buffer);
        var s: Stringify = .{ .writer = &fixed };
        try protocol.writeError(&s, null, .invalid_request, "message exceeds the maximum length of 1048576 bytes", null);
        try out.writeAll(fixed.buffered());
        try out.writeByte('\n');
    }

    fn respond(self: *Server, arena: Allocator, line: []const u8, w: *Writer, request_id: *?protocol.Id) !void {
        var s: Stringify = .{ .writer = w };
        switch (try protocol.parse(arena, line)) {
            .invalid => |invalid| try protocol.writeError(&s, invalid.id, invalid.code, invalid.message, null),
            .notification => |notification| try self.notify(notification),
            .request => |request| {
                request_id.* = request.id;
                switch (protocol.checkMeta(request.params)) {
                    .refused => |refusal| try protocol.writeError(&s, request.id, refusal.code, refusal.message, refusal.requested),
                    .modern => try self.dispatchModern(arena, &s, request),
                    .legacy => try self.dispatchLegacy(arena, &s, request),
                }
            },
        }
    }

    fn notify(self: *Server, notification: protocol.Notification) !void {
        // Requests are answered one at a time, in order, so a cancellation can
        // only arrive after the response it names has been written.
        if (std.mem.eql(u8, notification.method, "notifications/initialized")) return;
        if (std.mem.eql(u8, notification.method, "notifications/cancelled")) return;
        try self.logf("ignored notification {s}", .{notification.method});
    }

    fn dispatchModern(self: *Server, arena: Allocator, s: *Stringify, request: protocol.Request) !void {
        const method = request.method;
        if (std.mem.eql(u8, method, "server/discover")) {
            try protocol.beginResult(s, request.id, .modern);
            try s.objectField("supportedVersions");
            try s.beginArray();
            try s.write(protocol.modern_version);
            try s.endArray();
            try writeServerCapabilities(s);
            try s.objectField("instructions");
            try s.write(instructions);
            try writeCacheFields(s);
            return protocol.endResult(s);
        }
        if (std.mem.eql(u8, method, "tools/list")) return self.listTools(s, request, .modern);
        if (std.mem.eql(u8, method, "tools/call")) return self.callTool(arena, s, request, .modern);
        const message = try std.fmt.allocPrint(arena, "Method not found: {s}", .{method});
        try protocol.writeError(s, request.id, .method_not_found, message, null);
    }

    fn dispatchLegacy(self: *Server, arena: Allocator, s: *Stringify, request: protocol.Request) !void {
        const method = request.method;
        if (std.mem.eql(u8, method, "initialize")) return self.initialize(s, request);
        if (std.mem.eql(u8, method, "ping")) {
            try protocol.beginResult(s, request.id, .legacy);
            return protocol.endResult(s);
        }
        const needs_session = std.mem.eql(u8, method, "tools/list") or std.mem.eql(u8, method, "tools/call");
        if (needs_session and !self.legacy_initialized) {
            return protocol.writeError(s, request.id, .invalid_params, "this request carries no " ++
                protocol.meta_protocol_version ++ " in _meta and no initialize preceded it; " ++
                "send per-request _meta for " ++ protocol.modern_version ++ " or initialize for " ++
                protocol.legacy_version, null);
        }
        if (std.mem.eql(u8, method, "tools/list")) return self.listTools(s, request, .legacy);
        if (std.mem.eql(u8, method, "tools/call")) return self.callTool(arena, s, request, .legacy);
        if (std.mem.eql(u8, method, "server/discover")) {
            return protocol.writeError(s, request.id, .invalid_params, "server/discover requires " ++
                protocol.meta_protocol_version ++ " and " ++ protocol.meta_client_capabilities ++ " in _meta", null);
        }
        const message = try std.fmt.allocPrint(arena, "Method not found: {s}", .{method});
        try protocol.writeError(s, request.id, .method_not_found, message, null);
    }

    fn initialize(self: *Server, s: *Stringify, request: protocol.Request) !void {
        const params = request.params orelse
            return protocol.writeError(s, request.id, .invalid_params, "initialize requires params", null);
        switch (params.get("protocolVersion") orelse .null) {
            .string => {},
            else => return protocol.writeError(s, request.id, .invalid_params, "initialize requires a string protocolVersion", null),
        }
        // 2025-06-18 lifecycle: answer with the requested version when it is
        // supported, otherwise with the one this server supports. Either way
        // that is the only legacy version served here.
        self.legacy_initialized = true;
        try protocol.beginResult(s, request.id, .legacy);
        try s.objectField("protocolVersion");
        try s.write(protocol.legacy_version);
        try writeServerCapabilities(s);
        try s.objectField("serverInfo");
        try protocol.writeImplementation(s);
        try s.objectField("instructions");
        try s.write(instructions);
        try protocol.endResult(s);
    }

    fn listTools(self: *Server, s: *Stringify, request: protocol.Request, era: protocol.Era) !void {
        _ = self;
        if (request.params) |params| {
            // No list here is paginated, so no cursor was ever issued.
            if (params.get("cursor") != null) {
                return protocol.writeError(s, request.id, .invalid_params, "Invalid cursor", null);
            }
        }
        try protocol.beginResult(s, request.id, era);
        try s.objectField("tools");
        try tools.writeToolList(s);
        if (era == .modern) try writeCacheFields(s);
        try protocol.endResult(s);
    }

    fn callTool(self: *Server, arena: Allocator, s: *Stringify, request: protocol.Request, era: protocol.Era) !void {
        const params = request.params orelse
            return protocol.writeError(s, request.id, .invalid_params, "tools/call requires params", null);
        const name = switch (params.get("name") orelse .null) {
            .string => |value| value,
            else => return protocol.writeError(s, request.id, .invalid_params, "tools/call requires a string name", null),
        };
        const arguments: ?std.json.ObjectMap = if (params.get("arguments")) |value| switch (value) {
            .object => |object| object,
            else => return protocol.writeError(s, request.id, .invalid_params, "tools/call arguments must be an object", null),
        } else null;
        const tool = tools.byName(name) orelse {
            const message = try std.fmt.allocPrint(arena, "Unknown tool: {s}", .{name});
            return protocol.writeError(s, request.id, .invalid_params, message, null);
        };

        var body: Writer.Allocating = .init(arena);
        var body_stringify: Stringify = .{ .writer = &body.writer };
        var ctx: tools.Context = .{
            .arena = arena,
            .snapshot = &self.snapshot,
            .evidence_text = self.options.evidence_text,
        };
        const outcome = switch (tool) {
            .semidx_health => tools.health(&ctx, &body_stringify, arguments, try self.status(arena)),
            .semidx_repo_map => tools.repoMap(&ctx, &body_stringify, arguments),
            .semidx_find_definitions => tools.findDefinitions(&ctx, &body_stringify, arguments),
            .semidx_references => tools.references(&ctx, &body_stringify, arguments),
            .semidx_context => tools.context(&ctx, &body_stringify, arguments),
            .semidx_refresh => self.refresh(&ctx, &body_stringify, arguments),
        };

        try protocol.beginResult(s, request.id, era);
        try s.objectField("content");
        try s.beginArray();
        try s.beginObject();
        try s.objectField("type");
        try s.write("text");
        try s.objectField("text");
        outcome catch |err| switch (err) {
            error.ToolFailed => {
                try protocol.writeString(s, ctx.failure.?);
                try s.endObject();
                try s.endArray();
                try s.objectField("isError");
                try s.write(true);
                return protocol.endResult(s);
            },
            else => |e| return e,
        };
        // The compact text fallback is the structured result serialized, as
        // both protocol versions recommend for structured tool output.
        try s.write(body.written());
        try s.endObject();
        try s.endArray();
        try s.objectField("structuredContent");
        try s.beginWriteRaw();
        try s.writer.writeAll(body.written());
        s.endWriteRaw();
        try s.objectField("isError");
        try s.write(false);
        try protocol.endResult(s);
    }

    fn status(self: *Server, arena: Allocator) !tools.Status {
        const languages = std.enums.values(model.Language);
        const statuses = try arena.alloc(tools.LanguageStatus, languages.len);
        for (languages, statuses) |language, *entry| {
            var extensions: std.ArrayList([]const u8) = .empty;
            for (semidx.source.languages.mappings) |mapping| {
                if (mapping.language == language) try extensions.append(arena, mapping.extension);
            }
            entry.* = .{
                .language = language,
                .extensions = extensions.items,
                .parser_error = if (self.index.analyzer.probeParser(language)) |_| null else |err| @errorName(err),
                .capabilities = semidx.frontends.capabilitiesFor(language),
            };
        }
        return .{ .root = self.options.root, .languages = statuses, .last_scan = self.last_scan };
    }

    /// Rescans the root and publishes the next snapshot. On any failure the
    /// published snapshot stays the one every earlier call observed.
    fn refresh(self: *Server, ctx: *tools.Context, s: *Stringify, arguments: ?std.json.ObjectMap) tools.Error!void {
        try tools.expectNoArguments(ctx, arguments);
        const previous = self.snapshot.revision;

        var found = semidx.source.discovery.scan(self.gpa, self.io, self.options.root, .{}) catch |err| {
            try self.logf("refresh: scanning {s} failed: {t}", .{ self.options.root, err });
            return ctx.fail("refresh could not scan the root: {t}; snapshot revision {d} is still published", .{ err, previous });
        };
        defer found.deinit();
        const outcome = self.index.applyScan(found) catch |err| {
            try self.logf("refresh: applying the scan failed: {t}", .{err});
            return ctx.fail("refresh failed while applying the scan: {t}; snapshot revision {d} is still published", .{ err, previous });
        };
        const next = self.index.publish() catch |err| {
            try self.logf("refresh: publishing failed: {t}", .{err});
            return ctx.fail("refresh failed to publish: {t}; snapshot revision {d} is still published", .{ err, previous });
        };

        self.snapshot.deinit();
        self.snapshot = next;
        self.last_scan = outcome;
        ctx.snapshot = &self.snapshot;
        ctx.existence = null;

        try tools.beginStructured(ctx, s);
        try s.objectField("previous_revision");
        try s.write(previous);
        try s.objectField("scan");
        try s.write(outcome);
        try s.objectField("units");
        try tools.writeUnitCounts(ctx, s);
        try s.objectField("diagnostics");
        try tools.writeDiagnosticCounts(ctx, s, null);
        try s.endObject();
    }
};

fn writeServerCapabilities(s: *Stringify) Writer.Error!void {
    try s.objectField("capabilities");
    try s.beginObject();
    try s.objectField("tools");
    try s.beginObject();
    try s.endObject();
    try s.endObject();
}

fn writeCacheFields(s: *Stringify) Writer.Error!void {
    try s.objectField("ttlMs");
    try s.write(list_ttl_ms);
    try s.objectField("cacheScope");
    try s.write("public");
}

// -- tests ------------------------------------------------------------------

const testing = std.testing;
const test_io = testing.io;

const modern_meta = "\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\"," ++
    "\"io.modelcontextprotocol/clientCapabilities\":{}}";

const greeter_source =
    \\const std = @import("std");
    \\
    \\fn greeting() []const u8 {
    \\    return "a greeting body that must not leak";
    \\}
    \\
    \\pub fn greet() []const u8 {
    \\    return greeting();
    \\}
    \\
;

const Harness = struct {
    tmp: testing.TmpDir,
    root: [:0]u8,
    log: Writer.Allocating,
    server: Server,
    out: Writer.Allocating,

    fn init(self: *Harness, evidence_text: bool, extra: []const u8) !void {
        self.tmp = testing.tmpDir(.{});
        errdefer self.tmp.cleanup();
        try self.tmp.dir.writeFile(test_io, .{ .sub_path = "greeter.zig", .data = greeter_source });
        if (extra.len != 0) try self.tmp.dir.writeFile(test_io, .{ .sub_path = "extra.zig", .data = extra });
        self.root = try self.tmp.dir.realPathFileAlloc(test_io, ".", testing.allocator);
        errdefer testing.allocator.free(self.root);
        self.log = .init(testing.allocator);
        errdefer self.log.deinit();
        self.server = try Server.init(testing.allocator, test_io, .{ .root = self.root, .evidence_text = evidence_text }, &self.log.writer);
        self.out = .init(testing.allocator);
    }

    fn deinit(self: *Harness) void {
        self.out.deinit();
        self.server.deinit();
        self.log.deinit();
        testing.allocator.free(self.root);
        self.tmp.cleanup();
    }

    /// Sends one line and returns the parsed response, or null for none.
    fn send(self: *Harness, arena: Allocator, line: []const u8) !?std.json.Value {
        self.out.clearRetainingCapacity();
        try self.server.handleLine(line, &self.out.writer);
        const written = self.out.written();
        if (written.len == 0) return null;
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, written, "\n"));
        try testing.expect(written[written.len - 1] == '\n');
        return try std.json.parseFromSliceLeaky(std.json.Value, arena, try arena.dupe(u8, written), .{});
    }

    fn callTool(self: *Harness, arena: Allocator, name: []const u8, arguments: []const u8) !std.json.Value {
        const line = try std.fmt.allocPrint(arena, "{{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{{" ++
            "{s},\"name\":\"{s}\",\"arguments\":{s}}}}}", .{ modern_meta, name, arguments });
        const response = (try self.send(arena, line)).?;
        return response.object.get("result").?;
    }
};

fn errorCode(response: std.json.Value) i64 {
    return response.object.get("error").?.object.get("code").?.integer;
}

test "one dispatcher serves modern requests statelessly and legacy requests after initialize" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var h: Harness = undefined;
    try h.init(false, "");
    defer h.deinit();

    const discover = (try h.send(arena, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"server/discover\",\"params\":{" ++ modern_meta ++ "}}")).?;
    const discovered = discover.object.get("result").?.object;
    try testing.expectEqualStrings("complete", discovered.get("resultType").?.string);
    try testing.expectEqualStrings("2026-07-28", discovered.get("supportedVersions").?.array.items[0].string);
    try testing.expect(discovered.get("capabilities").?.object.get("tools") != null);
    try testing.expect(discovered.get("ttlMs") != null and discovered.get("cacheScope") != null);
    try testing.expectEqualStrings("semidx", discovered.get("_meta").?.object.get("io.modelcontextprotocol/serverInfo").?.object.get("name").?.string);

    // A modern tools/list needs no handshake, and says nothing legacy-shaped.
    const modern_list = (try h.send(arena, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{" ++ modern_meta ++ "}}")).?;
    try testing.expectEqual(tools.definitions.len, modern_list.object.get("result").?.object.get("tools").?.array.items.len);
    try testing.expect(!h.server.legacy_initialized);

    // Without _meta and before initialize, a legacy request is refused.
    const early = (try h.send(arena, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/list\"}")).?;
    try testing.expectEqual(@as(i64, -32602), errorCode(early));

    const init_response = (try h.send(arena, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{},\"clientInfo\":{\"name\":\"t\",\"version\":\"1\"}}}")).?;
    const initialized = init_response.object.get("result").?.object;
    try testing.expectEqualStrings("2025-06-18", initialized.get("protocolVersion").?.string);
    try testing.expect(initialized.get("resultType") == null);
    try testing.expect(try h.send(arena, "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}") == null);

    const legacy_list = (try h.send(arena, "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/list\"}")).?;
    const legacy_result = legacy_list.object.get("result").?.object;
    try testing.expect(legacy_result.get("resultType") == null and legacy_result.get("ttlMs") == null);
    try testing.expectEqual(tools.definitions.len, legacy_result.get("tools").?.array.items.len);

    const ping = (try h.send(arena, "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"ping\"}")).?;
    try testing.expectEqual(@as(usize, 0), ping.object.get("result").?.object.count());

    // Modern refusals are decided by the request alone.
    const unsupported = (try h.send(arena, "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/list\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2025-11-25\",\"io.modelcontextprotocol/clientCapabilities\":{}}}}")).?;
    try testing.expectEqual(@as(i64, -32022), errorCode(unsupported));
    try testing.expectEqualStrings("2025-11-25", unsupported.object.get("error").?.object.get("data").?.object.get("requested").?.string);
    const modern_ping = (try h.send(arena, "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"ping\",\"params\":{" ++ modern_meta ++ "}}")).?;
    try testing.expectEqual(@as(i64, -32601), errorCode(modern_ping));
    const cursor = (try h.send(arena, "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/list\",\"params\":{" ++ modern_meta ++ ",\"cursor\":\"x\"}}")).?;
    try testing.expectEqual(@as(i64, -32602), errorCode(cursor));

    const unknown_tool = (try h.send(arena, "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":{" ++ modern_meta ++ ",\"name\":\"nope\"}}")).?;
    try testing.expectEqual(@as(i64, -32602), errorCode(unknown_tool));

    // An invalid argument is a tool execution error the model can act on.
    const bad = try h.callTool(arena, "semidx_find_definitions", "{\"limit\":0}");
    try testing.expect(bad.object.get("isError").?.bool);
    try testing.expect(bad.object.get("structuredContent") == null);
    const unknown_argument = try h.callTool(arena, "semidx_health", "{\"verbose\":true}");
    try testing.expect(unknown_argument.object.get("isError").?.bool);

    try testing.expect(std.mem.indexOf(u8, h.log.written(), "indexed 1 source units") != null);
}

test "the product version is reported in server identity and health, apart from the contract version" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var h: Harness = undefined;
    try h.init(false, "");
    defer h.deinit();

    const discover = (try h.send(arena, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"server/discover\",\"params\":{" ++ modern_meta ++ "}}")).?;
    const server_info = discover.object.get("result").?.object.get("_meta").?.object.get("io.modelcontextprotocol/serverInfo").?.object;
    try testing.expectEqualStrings(protocol.product_version, server_info.get("version").?.string);

    const health = try h.callTool(arena, "semidx_health", "{}");
    const structured = health.object.get("structuredContent").?.object;
    try testing.expectEqualStrings(protocol.product_version, structured.get("product_version").?.string);
    try testing.expectEqualStrings(protocol.product_version, structured.get("server").?.object.get("version").?.string);
    try testing.expect(structured.get("semantic_contract_version").? == .null);
}

test "tool results carry resolution, freshness, producer, and the snapshot revision" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var h: Harness = undefined;
    try h.init(false, "");
    defer h.deinit();

    const found = try h.callTool(arena, "semidx_find_definitions", "{\"name\":\"greet\"}");
    try testing.expect(!found.object.get("isError").?.bool);
    const structured = found.object.get("structuredContent").?.object;
    try testing.expectEqual(@as(i64, @intCast(h.server.snapshot.revision)), structured.get("snapshot").?.object.get("revision").?.integer);
    const definition = structured.get("definitions").?.array.items[0].object;
    try testing.expectEqualStrings("function", definition.get("role").?.string);
    try testing.expectEqualStrings("current", definition.get("freshness").?.string);
    const existence = definition.get("existence").?.object;
    try testing.expectEqualStrings("fact", existence.get("resolution").?.object.get("category").?.string);
    try testing.expectEqualStrings("frontend.zig", existence.get("producer").?.object.get("name").?.string);
    try testing.expectEqualStrings("greeter.zig", definition.get("evidence").?.object.get("unit").?.object.get("path").?.string);

    // The text block is the structured result, serialized.
    const text = found.object.get("content").?.array.items[0].object.get("text").?.string;
    const reparsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{});
    try testing.expectEqual(structured.get("total").?.integer, reparsed.object.get("total").?.integer);

    const refs = try h.callTool(arena, "semidx_references", "{\"name\":\"greeting\"}");
    const relationships = refs.object.get("structuredContent").?.object.get("relationships").?.array.items;
    try testing.expectEqual(@as(usize, 1), relationships.len);
    const call = relationships[0].object;
    try testing.expectEqualStrings("calls", call.get("kind").?.string);
    try testing.expectEqualStrings("fact", call.get("resolution").?.object.get("category").?.string);
    try testing.expectEqualStrings("greet", call.get("source").?.object.get("name").?.string);

    const ctx = try h.callTool(arena, "semidx_context", "{\"path\":\"greeter.zig\"}");
    const focus = ctx.object.get("structuredContent").?.object.get("focus").?.array.items[0].object;
    try testing.expectEqualStrings("file", focus.get("entity").?.object.get("kind").?.string);
    try testing.expectEqualStrings("current", focus.get("unit").?.object.get("analysis").?.string);
    try testing.expect(focus.get("diagnostics").?.array.items.len > 0);
    var defines: usize = 0;
    for (focus.get("outgoing").?.array.items) |item| {
        if (std.mem.eql(u8, item.object.get("kind").?.string, "defines")) defines += 1;
    }
    try testing.expectEqual(@as(usize, 2), defines);

    // Bounds report truncation instead of silently dropping entries.
    const bounded = try h.callTool(arena, "semidx_find_definitions", "{\"limit\":1}");
    const bounded_result = bounded.object.get("structuredContent").?.object;
    try testing.expectEqual(@as(usize, 1), bounded_result.get("definitions").?.array.items.len);
    try testing.expectEqual(@as(i64, 2), bounded_result.get("total").?.integer);
    try testing.expect(bounded_result.get("truncated").?.bool);
}

test "no tool result carries source text unless evidence text was opted into, and then bounded" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const body = "a greeting body that must not leak";
    // Evidence text longer than the bound: the frontend records a
    // definition's name as its evidence.
    const long_name = "n" ** 600;
    const extra = "pub fn " ++ long_name ++ "() void {}\n";
    const calls = [_][2][]const u8{
        .{ "semidx_health", "{}" },
        .{ "semidx_repo_map", "{}" },
        .{ "semidx_find_definitions", "{}" },
        .{ "semidx_references", "{\"name\":\"greeting\",\"direction\":\"both\"}" },
        .{ "semidx_context", "{\"name\":\"greeting\"}" },
        .{ "semidx_context", "{\"path\":\"greeter.zig\"}" },
    };

    var off: Harness = undefined;
    try off.init(false, extra);
    defer off.deinit();
    for (calls) |call| {
        _ = try off.callTool(arena, call[0], call[1]);
        try testing.expect(std.mem.indexOf(u8, off.out.written(), body) == null);
        try testing.expect(std.mem.indexOf(u8, off.out.written(), "\"source_text\":{") == null);
    }

    var on: Harness = undefined;
    try on.init(true, extra);
    defer on.deinit();
    for (calls) |call| {
        _ = try on.callTool(arena, call[0], call[1]);
        // The opt-in covers recorded evidence text, never unit contents.
        try testing.expect(std.mem.indexOf(u8, on.out.written(), body) == null);
    }
    const greeting = try on.callTool(arena, "semidx_context", "{\"name\":\"greeting\"}");
    const greeting_text = greeting.object.get("structuredContent").?.object.get("focus").?.array.items[0].object
        .get("entity").?.object.get("evidence").?.object.get("source_text").?.object;
    try testing.expectEqualStrings("greeting", greeting_text.get("text").?.string);
    try testing.expect(!greeting_text.get("truncated").?.bool);

    const long = try on.callTool(arena, "semidx_find_definitions", "{\"path\":\"extra.zig\"}");
    const long_text = long.object.get("structuredContent").?.object.get("definitions").?.array.items[0].object
        .get("evidence").?.object.get("source_text").?.object;
    try testing.expectEqual(tools.max_evidence_text_bytes, long_text.get("text").?.string.len);
    try testing.expect(long_text.get("truncated").?.bool);
}

test "refresh publishes a new snapshot that observes edited and added units" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var h: Harness = undefined;
    try h.init(false, "");
    defer h.deinit();

    const before = h.server.snapshot.revision;
    try h.tmp.dir.writeFile(test_io, .{ .sub_path = "greeter.zig", .data = greeter_source ++ "pub fn farewell() void {}\n" });
    try h.tmp.dir.writeFile(test_io, .{ .sub_path = "added.zig", .data = "pub fn added() void {}\n" });

    // Until the refresh, calls still observe the published snapshot.
    const stale_view = try h.callTool(arena, "semidx_find_definitions", "{\"name\":\"added\"}");
    try testing.expectEqual(@as(i64, 0), stale_view.object.get("structuredContent").?.object.get("total").?.integer);

    const refreshed = try h.callTool(arena, "semidx_refresh", "{}");
    const result = refreshed.object.get("structuredContent").?.object;
    const after = result.get("snapshot").?.object.get("revision").?.integer;
    try testing.expect(after > @as(i64, @intCast(before)));
    try testing.expectEqual(@as(i64, @intCast(before)), result.get("previous_revision").?.integer);
    try testing.expectEqual(@as(i64, 1), result.get("scan").?.object.get("added").?.integer);
    try testing.expectEqual(@as(i64, 1), result.get("scan").?.object.get("changed").?.integer);
    try testing.expectEqual(@as(i64, 2), result.get("units").?.object.get("total").?.integer);

    for ([_][]const u8{ "{\"name\":\"added\"}", "{\"name\":\"farewell\"}" }) |arguments| {
        const found = try h.callTool(arena, "semidx_find_definitions", arguments);
        const structured = found.object.get("structuredContent").?.object;
        try testing.expectEqual(after, structured.get("snapshot").?.object.get("revision").?.integer);
        try testing.expectEqual(@as(i64, 1), structured.get("total").?.integer);
    }

    // A refresh that cannot scan the root keeps the published snapshot.
    try h.tmp.parent_dir.deleteTree(test_io, &h.tmp.sub_path);
    const failed = try h.callTool(arena, "semidx_refresh", "{}");
    try testing.expect(failed.object.get("isError").?.bool);
    try testing.expectEqual(@as(u64, @intCast(after)), h.server.snapshot.revision);
    const still = try h.callTool(arena, "semidx_find_definitions", "{\"name\":\"added\"}");
    try testing.expectEqual(@as(i64, 1), still.object.get("structuredContent").?.object.get("total").?.integer);
}

test {
    _ = protocol;
    _ = stdio;
    _ = tools;
}
