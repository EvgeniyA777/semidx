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
    /// The index `snapshot` borrows from, when a rebuild has replaced it and
    /// no snapshot of the rebuilt index has been published yet.
    retired: ?semidx.Index,
    /// Set when a refresh failed part-way and the index could not be rebuilt.
    /// Such an index is never reconciled again; the next refresh rebuilds it.
    poisoned: bool,
    /// How many times the index was rebuilt after a failed refresh.
    rebuilds: u32,
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
            .retired = null,
            .poisoned = false,
            .rebuilds = 0,
            .last_scan = outcome,
            .legacy_initialized = false,
            .message_arena = std.heap.ArenaAllocator.init(gpa),
        };
    }

    pub fn deinit(self: *Server) void {
        self.message_arena.deinit();
        self.snapshot.deinit();
        if (self.retired) |*retired| retired.deinit();
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
        return .{
            .root = self.options.root,
            .languages = statuses,
            .last_scan = self.last_scan,
            .recovery = .{
                .rebuilds = self.rebuilds,
                .rebuilt_index_unpublished = self.retired != null,
                .needs_rebuild = self.poisoned,
            },
        };
    }

    /// Rescans the root and publishes the next snapshot.
    ///
    /// On any failure the published snapshot stays the one every earlier call
    /// observed. A failure after reconciliation started can leave the index
    /// partly updated, and a partly updated index is not trusted again: it is
    /// replaced by an index rebuilt from the same scan. The rebuilt index
    /// issues none of the old index's ids, so an id from an earlier snapshot
    /// names nothing in it rather than a different entity.
    fn refresh(self: *Server, ctx: *tools.Context, s: *Stringify, arguments: ?std.json.ObjectMap) tools.Error!void {
        try tools.expectNoArguments(ctx, arguments);
        const previous = self.snapshot.revision;

        var found = semidx.source.discovery.scan(self.gpa, self.io, self.options.root, .{}) catch |err| {
            try self.logf("refresh: scanning {s} failed: {t}", .{ self.options.root, err });
            return ctx.fail("refresh could not scan the root: {t}; the index was not changed and snapshot revision {d} is still published", .{ err, previous });
        };
        defer found.deinit();

        if (self.poisoned and !try self.rebuild(found)) {
            return ctx.fail("an earlier refresh failed and rebuilding the index failed again; snapshot revision {d} is still published, and the next refresh retries the rebuild", .{previous});
        }
        const outcome = self.index.applyScan(found) catch |err| return self.recoverFrom(ctx, found, "applying the scan", err, previous);
        const next = self.index.publish() catch |err| return self.recoverFrom(ctx, found, "publishing", err, previous);

        const rebuilt = self.retired != null;
        self.snapshot.deinit();
        self.snapshot = next;
        if (self.retired) |*retired| {
            retired.deinit();
            self.retired = null;
        }
        self.last_scan = outcome;
        ctx.snapshot = &self.snapshot;
        ctx.existence = null;

        try tools.beginStructured(ctx, s);
        try s.objectField("previous_revision");
        try s.write(previous);
        try s.objectField("entity_ids_preserved");
        try s.write(!rebuilt);
        try s.objectField("scan");
        try s.write(outcome);
        try s.objectField("units");
        try tools.writeUnitCounts(ctx, s);
        try s.objectField("diagnostics");
        try tools.writeDiagnosticCounts(ctx, s, null);
        try s.endObject();
    }

    /// Replaces a failed refresh's index with one rebuilt from the same scan,
    /// and reports the failure with whether that recovery completed.
    fn recoverFrom(
        self: *Server,
        ctx: *tools.Context,
        found: semidx.source.SourceScan,
        stage: []const u8,
        err: anyerror,
        previous: u64,
    ) tools.Error {
        try self.logf("refresh: {s} failed: {t}; rebuilding the index", .{ stage, err });
        self.poisoned = true;
        if (try self.rebuild(found)) {
            return ctx.fail("refresh failed while {s}: {t}. The index was rebuilt from a fresh scan; snapshot revision {d} " ++
                "is still published, and the next refresh publishes the rebuilt index, in which entity ids from " ++
                "earlier snapshots name nothing", .{ stage, err, previous });
        }
        return ctx.fail("refresh failed while {s}: {t}, and rebuilding the index failed too; snapshot revision {d} " ++
            "is still published, and the next refresh retries the rebuild", .{ stage, err, previous });
    }

    /// Builds a fresh index from `found` above the current index's ids. On
    /// success it becomes the index; the index the published snapshot borrows
    /// from stays alive until a snapshot of the new one replaces it.
    fn rebuild(self: *Server, found: semidx.source.SourceScan) Writer.Error!bool {
        const floor = self.index.graph.idFloor();
        var fresh = semidx.Index.initAfter(self.gpa, self.options.root, floor) catch |err| {
            try self.logf("recovery: creating a fresh index failed: {t}", .{err});
            self.poisoned = true;
            return false;
        };
        _ = fresh.applyScan(found) catch |err| {
            try self.logf("recovery: indexing the scan into a fresh index failed: {t}", .{err});
            fresh.deinit();
            self.poisoned = true;
            return false;
        };
        if (self.retired == null) {
            self.retired = self.index;
        } else {
            self.index.deinit();
        }
        self.index = fresh;
        self.poisoned = false;
        self.rebuilds += 1;
        try self.logf("recovery: rebuilt the index ({d} rebuilds so far)", .{self.rebuilds});
        return true;
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
/// Set only by `zig build dogfood`, which runs the tests over this repository.
const dogfood = @import("semidx_dogfood");

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

test "every declared argument is validated as its advertised schema says, and annotations stay accurate" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var h: Harness = undefined;
    try h.init(false, "");
    defer h.deinit();

    const Check = struct {
        fn call(harness: *Harness, a: Allocator, tool: tools.Tool, base: []const u8, argument: []const u8, value: []const u8) !std.json.Value {
            const arguments = try std.fmt.allocPrint(a, "{{{s}\"{s}\":{s}}}", .{ base, argument, value });
            return harness.callTool(a, @tagName(tool), arguments);
        }
        fn refused(result: std.json.Value, needle: []const u8) !void {
            try testing.expect(result.object.get("isError").?.bool);
            const text = result.object.get("content").?.array.items[0].object.get("text").?.string;
            try testing.expect(std.mem.indexOf(u8, text, needle) != null);
        }
        fn accepted(result: std.json.Value) !void {
            try testing.expect(!result.object.get("isError").?.bool);
        }
    };

    for (tools.definitions) |definition| {
        // References and context need a target; the others need nothing.
        const base: []const u8 = switch (definition.tool) {
            .semidx_references, .semidx_context => "\"name\":\"greet\",",
            else => "",
        };
        try Check.refused(try Check.call(&h, arena, definition.tool, base, "bogus_argument", "1"), "unknown argument \"bogus_argument\"");
        for (definition.params) |param| {
            const own_base = if (std.mem.eql(u8, param.name, "name") or std.mem.eql(u8, param.name, "entity_id")) "" else base;
            switch (param.type) {
                .string => try Check.refused(try Check.call(&h, arena, definition.tool, own_base, param.name, "1"), "must be a string"),
                .entity_id => {
                    try Check.refused(try Check.call(&h, arena, definition.tool, own_base, param.name, "\"1\""), "must be an integer");
                    try Check.refused(try Check.call(&h, arena, definition.tool, own_base, param.name, "-1"), "is not an entity id");
                },
                .count => |count| {
                    try Check.refused(try Check.call(&h, arena, definition.tool, own_base, param.name, "\"1\""), "must be an integer");
                    try Check.refused(try Check.call(&h, arena, definition.tool, own_base, param.name, "0"), "must be between 1 and");
                    const above = try std.fmt.allocPrint(arena, "{d}", .{count.maximum + 1});
                    try Check.refused(try Check.call(&h, arena, definition.tool, own_base, param.name, above), "must be between 1 and");
                    const maximum = try std.fmt.allocPrint(arena, "{d}", .{count.maximum});
                    try Check.accepted(try Check.call(&h, arena, definition.tool, own_base, param.name, maximum));
                },
                .choice => |choice| {
                    try Check.refused(try Check.call(&h, arena, definition.tool, own_base, param.name, "1"), "must be a string");
                    try Check.refused(try Check.call(&h, arena, definition.tool, own_base, param.name, "\"not-a-value\""), "unsupported value");
                    for (choice.values) |value| {
                        const quoted = try std.fmt.allocPrint(arena, "\"{s}\"", .{value});
                        try Check.accepted(try Check.call(&h, arena, definition.tool, own_base, param.name, quoted));
                    }
                },
            }
        }
    }

    const list = (try h.send(arena, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{" ++ modern_meta ++ "}}")).?;
    for (list.object.get("result").?.object.get("tools").?.array.items) |tool| {
        const annotations = tool.object.get("annotations").?.object;
        const is_refresh = std.mem.eql(u8, "semidx_refresh", tool.object.get("name").?.string);
        try testing.expectEqual(!is_refresh, annotations.get("readOnlyHint").?.bool);
        try testing.expect(!annotations.get("openWorldHint").?.bool);
        // Refresh rebuilds the server's own index and touches no file.
        if (is_refresh) try testing.expect(!annotations.get("destructiveHint").?.bool);
    }
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

/// Fails exactly one allocation, or every allocation from one onwards, so a
/// test can inject a failure at each point of an operation in turn.
const InjectedFailures = struct {
    child: Allocator,
    count: usize = 0,
    fail_at: usize = std.math.maxInt(usize),
    sticky: bool = false,
    fired: bool = false,

    fn allocator(self: *InjectedFailures) Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        } };
    }

    fn arm(self: *InjectedFailures, offset: usize, sticky: bool) void {
        self.fail_at = self.count + offset;
        self.sticky = sticky;
        self.fired = false;
    }

    fn disarm(self: *InjectedFailures) void {
        self.fail_at = std.math.maxInt(usize);
        self.sticky = false;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *InjectedFailures = @ptrCast(@alignCast(ctx));
        const index = self.count;
        self.count += 1;
        if (index == self.fail_at or (self.sticky and index > self.fail_at)) {
            self.fired = true;
            return null;
        }
        return self.child.rawAlloc(len, alignment, ret_addr);
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *InjectedFailures = @ptrCast(@alignCast(ctx));
        return self.child.rawResize(memory, alignment, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *InjectedFailures = @ptrCast(@alignCast(ctx));
        return self.child.rawRemap(memory, alignment, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *InjectedFailures = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ret_addr);
    }
};

/// Everything a snapshot says, by content rather than by id or revision, in a
/// stable order: two graphs of the same tree project identically.
fn projectSnapshot(gpa: Allocator, snapshot: *const semidx.Snapshot) ![]const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    for (snapshot.units) |view| {
        try lines.append(gpa, try std.fmt.allocPrint(gpa, "unit {s} {s} {t}", .{ view.path, @tagName(view.language), view.analysis() }));
    }
    for (snapshot.entities) |entity| {
        try lines.append(gpa, try std.fmt.allocPrint(gpa, "entity {t} {s} {s} {s} {t}", .{
            entity.kind,
            entityPath(snapshot, entity),
            entity.identity.role,
            entity.identity.name orelse "",
            snapshot.entityFreshness(entity),
        }));
    }
    for (snapshot.assertions) |assertion| {
        const relationship = assertion.relationship() orelse continue;
        const source = snapshot.entityById(relationship.source).?;
        const target = switch (relationship.target) {
            .entity => |id| if (snapshot.entityById(id)) |found| try std.fmt.allocPrint(gpa, "{s}:{s}", .{ entityPath(snapshot, found), found.identity.name orelse found.identity.role }) else "<withdrawn>",
            .designator => |designator| designator,
        };
        try lines.append(gpa, try std.fmt.allocPrint(gpa, "relationship {t} {s}:{s} -> {s} {t} {t}", .{
            relationship.kind,
            entityPath(snapshot, source),
            source.identity.name orelse source.identity.role,
            target,
            assertion.resolution.category(),
            snapshot.assertionFreshness(assertion),
        }));
    }
    for (snapshot.diagnostics) |diagnostic| {
        const path = if (diagnostic.unit) |id| (if (snapshot.unit(id)) |view| view.path else "<unknown unit>") else "-";
        try lines.append(gpa, try std.fmt.allocPrint(gpa, "diagnostic {t} {s} {s}", .{ diagnostic.kind, path, diagnostic.message }));
    }
    std.mem.sort([]const u8, lines.items, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
    return std.mem.join(gpa, "\n", lines.items);
}

fn entityPath(snapshot: *const semidx.Snapshot, entity: model.Entity) []const u8 {
    const evidence = entity.evidence orelse return "-";
    const view = snapshot.unit(evidence.unit) orelse return "<unknown unit>";
    return view.path;
}

const recovery_v1 = [_][2][]const u8{
    .{ "demo/Helper.java", "package demo;\nclass Helper {}\n" },
    .{ "demo/Greeter.java", "package demo;\nclass Greeter {\n    Helper helper;\n    void go() { go2(); }\n    void go2() {}\n}\n" },
    .{ "a.zig", "fn a() void { b(); }\nfn b() void {}\n" },
    .{ "gone.zig", "pub fn gone() void {}\n" },
};

/// A rescan that renames a class other units resolve against, edits a unit,
/// removes one, and adds one: every kind of mutation a refresh performs.
const recovery_v2 = [_][2][]const u8{
    .{ "demo/Helper.java", "package demo;\nclass Aide {}\n" },
    .{ "demo/Greeter.java", recovery_v1[1][1] },
    .{ "a.zig", "fn a() void { c(); }\nfn c() void {}\n" },
    .{ "new.zig", "pub fn fresh() void {}\n" },
};

const TreeVersion = enum { before, after };

/// The small tree above: every kind of mutation in a handful of units, so
/// every allocation of the refresh can be failed in turn.
const SmallTree = struct {
    fn write(_: SmallTree, dir: std.Io.Dir, version: TreeVersion) !void {
        for ([_][]const u8{ "demo/Helper.java", "demo/Greeter.java", "a.zig", "gone.zig", "new.zig" }) |path| {
            dir.deleteFile(test_io, path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        }
        try dir.createDirPath(test_io, "demo");
        const files: []const [2][]const u8 = switch (version) {
            .before => &recovery_v1,
            .after => &recovery_v2,
        };
        for (files) |file| try dir.writeFile(test_io, .{ .sub_path = file[0], .data = file[1] });
    }
};

/// The projection of a server started fresh on `version` of `tree`.
fn oracleProjection(arena: Allocator, dir: std.Io.Dir, root: []const u8, tree: anytype, version: TreeVersion) ![]const u8 {
    try tree.write(dir, version);
    var log: Writer.Allocating = .init(arena);
    var server = try Server.init(std.heap.c_allocator, test_io, .{ .root = root }, &log.writer);
    defer server.deinit();
    return projectSnapshot(arena, &server.snapshot);
}

const refresh_line = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{" ++ modern_meta ++
    ",\"name\":\"semidx_refresh\",\"arguments\":{}}}";

const RefreshReply = struct {
    completed: bool,
    /// Present when the refresh completed.
    ids_preserved: ?bool = null,
};

/// Sends a refresh and reports whether it completed without a tool error.
fn refreshOnce(server: *Server, arena: Allocator) !RefreshReply {
    var out: Writer.Allocating = .init(arena);
    server.handleLine(refresh_line, &out.writer) catch return .{ .completed = false };
    const written = out.written();
    if (written.len == 0) return .{ .completed = false };
    const response = try std.json.parseFromSliceLeaky(std.json.Value, arena, written, .{});
    const result = response.object.get("result") orelse return .{ .completed = false };
    if (result.object.get("isError").?.bool) return .{ .completed = false };
    const structured = result.object.get("structuredContent").?.object;
    return .{ .completed = true, .ids_preserved = structured.get("entity_ids_preserved").?.bool };
}

const FailurePoints = union(enum) {
    /// Fail every allocation of the refresh in turn.
    every,
    /// Fail this many allocations spread evenly over the refresh, the first
    /// and last included. For trees whose refresh allocates too often to fail
    /// each allocation.
    spread: usize,
};

const RecoveryCounts = struct { points: usize, rebuilt: usize };

/// Starts a server on the `before` version of `tree`, changes it to `after`,
/// and fails allocations of the refresh that observes the change, checking
/// the three recovery guarantees against a fresh-index oracle at each point.
fn expectRecovery(tree: anytype, failure_points: FailurePoints, sticky: bool) !RecoveryCounts {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(test_io, ".", arena);

    const expected_before = try oracleProjection(arena, tmp.dir, root, tree, .before);
    const expected_after = try oracleProjection(arena, tmp.dir, root, tree, .after);
    try testing.expect(!std.mem.eql(u8, expected_before, expected_after));

    var counts: RecoveryCounts = .{ .points = 0, .rebuilt = 0 };
    switch (failure_points) {
        .every => {
            var offset: usize = 0;
            while (true) : (offset += 1) {
                try testing.expect(offset < 100_000);
                if (!try expectRecoveryAt(arena, tmp.dir, root, tree, expected_after, offset, sticky, &counts)) break;
            }
        },
        .spread => |wanted| {
            try testing.expect(wanted >= 2);
            const total = try refreshAllocations(arena, tmp.dir, root, tree, expected_after);
            try testing.expect(total >= wanted);
            for (0..wanted) |i| {
                const offset = i * (total - 1) / (wanted - 1);
                try testing.expect(try expectRecoveryAt(arena, tmp.dir, root, tree, expected_after, offset, sticky, &counts));
            }
        },
    }
    try testing.expect(counts.points > 0);
    try testing.expect(counts.rebuilt > 0);
    return counts;
}

/// How many allocations a refresh from `before` to `after` makes when none
/// fails.
fn refreshAllocations(arena: Allocator, dir: std.Io.Dir, root: []const u8, tree: anytype, expected_after: []const u8) !usize {
    var failures: InjectedFailures = .{ .child = std.heap.c_allocator };
    try tree.write(dir, .before);
    var log: Writer.Allocating = .init(arena);
    var server = try Server.init(failures.allocator(), test_io, .{ .root = root }, &log.writer);
    defer server.deinit();
    try tree.write(dir, .after);
    const start = failures.count;
    const reply = try refreshOnce(&server, arena);
    const total = failures.count - start;
    try testing.expect(reply.completed);
    try testing.expect(reply.ids_preserved.?);
    try testing.expectEqualStrings(expected_after, try projectSnapshot(arena, &server.snapshot));
    return total;
}

/// Checks the recovery guarantees with allocation `offset` of the refresh
/// failing. Returns false when the refresh made fewer allocations than that.
fn expectRecoveryAt(
    arena: Allocator,
    dir: std.Io.Dir,
    root: []const u8,
    tree: anytype,
    expected_after: []const u8,
    offset: usize,
    sticky: bool,
    counts: *RecoveryCounts,
) !bool {
    var failures: InjectedFailures = .{ .child = std.heap.c_allocator };
    try tree.write(dir, .before);
    var log: Writer.Allocating = .init(arena);
    var server = try Server.init(failures.allocator(), test_io, .{ .root = root }, &log.writer);
    defer server.deinit();
    const before = server.snapshot;
    const before_projection = try projectSnapshot(arena, &before);
    // Copied out: the earlier snapshot's strings belong to an index a
    // successful refresh releases.
    const Remembered = struct { id: model.EntityId, kind: model.EntityKind, role: []const u8, name: []const u8, path: []const u8 };
    var before_ids: std.ArrayList(Remembered) = .empty;
    for (before.entities) |entity| {
        try before_ids.append(arena, .{
            .id = entity.id,
            .kind = entity.kind,
            .role = try arena.dupe(u8, entity.identity.role),
            .name = try arena.dupe(u8, entity.identity.name orelse ""),
            .path = try arena.dupe(u8, entityPath(&before, entity)),
        });
    }
    const before_revision = before.revision;

    try tree.write(dir, .after);
    failures.arm(offset, sticky);
    const first = try refreshOnce(&server, arena);
    failures.disarm();
    if (!failures.fired) {
        try testing.expect(first.completed);
        try testing.expect(first.ids_preserved.?);
        try testing.expectEqualStrings(expected_after, try projectSnapshot(arena, &server.snapshot));
        return false;
    }
    counts.points += 1;

    // 1. The published snapshot is the one every earlier call observed,
    // unless the refresh finished and only its response was lost.
    const published = try projectSnapshot(arena, &server.snapshot);
    if (server.snapshot.revision == before_revision) {
        try testing.expectEqualStrings(before_projection, published);
    } else {
        try testing.expectEqualStrings(expected_after, published);
    }
    if (server.retired != null or server.poisoned) counts.rebuilt += 1;

    // 2. The next successful refresh publishes what a fresh index of the
    // tree holds.
    // A refresh whose response was lost may already have published.
    const second = if (server.snapshot.revision != before_revision and !server.poisoned and server.retired == null)
        RefreshReply{ .completed = true, .ids_preserved = true }
    else
        try refreshOnce(&server, arena);
    try testing.expect(second.completed);
    try testing.expect(!server.poisoned and server.retired == null);
    try testing.expectEqualStrings(expected_after, try projectSnapshot(arena, &server.snapshot));

    // 3. An id from the earlier snapshot never names a different entity:
    // after a rebuild it names nothing, and otherwise it names the same
    // entity.
    for (before_ids.items) |old| {
        const now = server.snapshot.entityById(old.id) orelse continue;
        try testing.expect(second.ids_preserved.?);
        try testing.expectEqual(old.kind, now.kind);
        try testing.expectEqualStrings(old.role, now.identity.role);
        try testing.expectEqualStrings(old.name, now.identity.name orelse "");
        try testing.expectEqualStrings(old.path, entityPath(&server.snapshot, now));
    }
    return true;
}

test "a refresh that fails at any allocation publishes nothing half-applied and the next refresh converges" {
    _ = try expectRecovery(SmallTree{}, .every, false);
}

test "when rebuilding after a failed refresh also fails, the next refresh rebuilds and converges" {
    _ = try expectRecovery(SmallTree{}, .every, true);
}

/// A copy of the source units a scan of this repository finds, byte for byte,
/// and a change to it that edits, removes, and adds units.
const RepositoryCopy = struct {
    scan: *const semidx.source.SourceScan,

    const edited_path = "src/source/discovery.zig";
    const removed_path = "src/mcp/stdio.zig";
    const added_path = "dogfood/added.zig";
    const appended =
        \\
        \\pub fn dogfoodProbe() void {
        \\    dogfoodProbeCallee();
        \\}
        \\
        \\fn dogfoodProbeCallee() void {}
        \\
    ;
    const added = "pub fn dogfoodAdded() void {}\n";

    fn write(self: RepositoryCopy, dir: std.Io.Dir, version: TreeVersion) !void {
        dir.deleteFile(test_io, added_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        for (self.scan.units) |unit| {
            if (std.fs.path.dirnamePosix(unit.path)) |parent| try dir.createDirPath(test_io, parent);
            if (version == .after and std.mem.eql(u8, unit.path, removed_path)) {
                dir.deleteFile(test_io, unit.path) catch |err| switch (err) {
                    error.FileNotFound => {},
                    else => return err,
                };
                continue;
            }
            if (version == .after and std.mem.eql(u8, unit.path, edited_path)) {
                const edited = try std.mem.concat(testing.allocator, u8, &.{ unit.bytes, appended });
                defer testing.allocator.free(edited);
                try dir.writeFile(test_io, .{ .sub_path = unit.path, .data = edited });
                continue;
            }
            try dir.writeFile(test_io, .{ .sub_path = unit.path, .data = unit.bytes });
        }
        if (version == .after) {
            try dir.createDirPath(test_io, "dogfood");
            try dir.writeFile(test_io, .{ .sub_path = added_path, .data = added });
        }
    }
};

test "dogfood: a refresh of a copy of this repository that fails part-way publishes nothing half-applied and the next refresh converges" {
    const repo_root = dogfood.repo_root orelse return error.SkipZigTest;
    var scan = try semidx.source.discovery.scan(testing.allocator, test_io, repo_root, .{});
    defer scan.deinit();
    for ([_][]const u8{ RepositoryCopy.edited_path, RepositoryCopy.removed_path }) |path| {
        if (scan.unitByPath(path) == null) {
            std.debug.print("the dogfood change names {s}, which this repository no longer has\n", .{path});
            return error.DogfoodTreeChanged;
        }
    }
    const tree: RepositoryCopy = .{ .scan = &scan };
    for ([_]bool{ false, true }) |sticky| {
        const counts = try expectRecovery(tree, .{ .spread = dogfood.failure_points }, sticky);
        std.debug.print("dogfood recovery over {d} units ({s} failures): {d} failure points, {d} rebuilds\n", .{
            scan.units.len,
            if (sticky) "sticky" else "one-shot",
            counts.points,
            counts.rebuilt,
        });
    }
}

test {
    _ = protocol;
    _ = stdio;
    _ = tools;
}
