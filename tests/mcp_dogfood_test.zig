//! Dogfood proof for the local MCP preview over this repository.
//!
//! It copies the source units a scan of this repository finds into a temporary
//! root, byte for byte, and drives the built `semidx-mcp` over stdio through the
//! agent habit loop: health, repository map, definition lookup, references and
//! context, an edit of the copy, and a refresh that publishes a new revision.
//! The repository itself is never edited.
//!
//! Timing and size notes are printed for the progress log. They are
//! observations, not bounds the test enforces.

const std = @import("std");
const build_options = @import("build_options");
const source = @import("semidx_source");

const stdio_client = @import("mcp_stdio_client.zig");
const Client = stdio_client.Client;

const testing = std.testing;
const io = testing.io;
const ObjectMap = std.json.ObjectMap;

/// The definition the proof looks up. `scan` calls it in the same unit, so it
/// has an incoming call fact, and `scan` also calls through a value, which
/// stays unresolved.
const definition_path = "src/source/discovery.zig";
const definition_name = "scanDir";
const caller_name = "scan";

/// Plan 006 deltas. `Server.handleLine` is a member function of a top-level
/// container; `tools.zig` calls `protocol.writeString` through
/// `const protocol = @import("protocol.zig")`.
const member_path = "src/mcp/root.zig";
const member_container = "Server";
const member_name = "handleLine";
const imported_path = "src/mcp/protocol.zig";
const imported_name = "writeString";
const importer_path = "src/mcp/tools.zig";
/// A top-level function in `importer_path` that calls both
/// `protocol.writeString` and a `std` function.
const importer_caller = "health";

/// Appended to `definition_path` in the copy: one new function calling another.
const probe_marker = "semidx-dogfood-probe-body";
const appended = "\npub fn dogfoodProbe() void {\n" ++
    "    const marker = \"" ++ probe_marker ++ "\";\n" ++
    "    _ = marker;\n" ++
    "    dogfoodProbeCallee();\n" ++
    "}\n\n" ++
    "fn dogfoodProbeCallee() void {}\n";

/// Comment text inside a function body of `definition_path`. It is in the
/// source, so its absence from every result shows no source text was returned.
const body_comment = "Every allocation happens before the struct literal.";

/// Must match `max_evidence_text_bytes` in `src/mcp/tools.zig`; health reports
/// the value the server uses and the test compares against it.
const evidence_text_max_bytes = 400;

const Copy = struct {
    tmp: testing.TmpDir,
    root: []const u8,
    units: usize,
    bytes: usize,
    definition_source: []const u8,
    /// Every copied unit's contents, by root-relative path.
    sources: std.StringHashMapUnmanaged([]const u8),
};

/// Copies every source unit a scan of this repository finds into a temporary
/// directory.
fn copyRepository(arena: std.mem.Allocator) !Copy {
    var scan = try source.discovery.scan(testing.allocator, io, build_options.repo_root, .{});
    defer scan.deinit();
    var tmp = testing.tmpDir(.{});
    errdefer tmp.cleanup();
    var bytes: usize = 0;
    var sources: std.StringHashMapUnmanaged([]const u8) = .empty;
    for (scan.units) |unit| {
        if (std.fs.path.dirnamePosix(unit.path)) |parent| try tmp.dir.createDirPath(io, parent);
        try tmp.dir.writeFile(io, .{ .sub_path = unit.path, .data = unit.bytes });
        try sources.put(arena, try arena.dupe(u8, unit.path), try arena.dupe(u8, unit.bytes));
        bytes += unit.bytes.len;
    }
    const definition_unit = scan.unitByPath(definition_path) orelse {
        std.debug.print("the dogfood proof names {s}, which this repository no longer has\n", .{definition_path});
        return error.DogfoodTreeChanged;
    };
    return .{
        .tmp = tmp,
        .root = try tmp.dir.realPathFileAlloc(io, ".", arena),
        .units = scan.units.len,
        .bytes = bytes,
        .definition_source = try arena.dupe(u8, definition_unit.bytes),
        .sources = sources,
    };
}

fn startServer(gpa: std.mem.Allocator, root: []const u8, extra_args: []const []const u8, log_dir: std.Io.Dir) !*Client {
    const stderr_file = try log_dir.createFile(io, "stderr.log", .{});
    defer stderr_file.close(io);
    return Client.start(gpa, build_options.mcp_exe, root, extra_args, log_dir, stderr_file);
}

/// Calls a tool and prints how long it took and how large its result was.
fn timedCall(client: *Client, id: i64, name: []const u8, arguments: []const u8) !ObjectMap {
    const started = std.Io.Timestamp.now(io, .awake);
    const before = client.transcript.items.len;
    const result = try client.callTool(id, name, arguments);
    std.debug.print("dogfood: {s} {s}: {d} ms, {d} bytes\n", .{
        name,
        arguments,
        started.untilNow(io, .awake).toMilliseconds(),
        client.transcript.items.len - before,
    });
    return result;
}

fn revisionOf(result: ObjectMap) i64 {
    return result.get("snapshot").?.object.get("revision").?.integer;
}

fn category(relationship: std.json.Value) []const u8 {
    return relationship.object.get("resolution").?.object.get("category").?.string;
}

test "dogfood: the agent habit loop over a copy of this repository, through stdio" {
    const gpa = testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var copy = try copyRepository(arena);
    defer copy.tmp.cleanup();
    try testing.expect(std.mem.indexOf(u8, copy.definition_source, body_comment) != null);
    std.debug.print("dogfood: copied {d} source units ({d} bytes) of {s}\n", .{ copy.units, copy.bytes, build_options.repo_root });

    var log_dir = testing.tmpDir(.{});
    defer log_dir.cleanup();
    const started = std.Io.Timestamp.now(io, .awake);
    const client = try startServer(gpa, copy.root, &.{}, log_dir.dir);
    defer client.destroy();

    // -- health ---------------------------------------------------------------
    const health = try timedCall(client, 1, "semidx_health", "{}");
    std.debug.print("dogfood: first response {d} ms after start\n", .{started.untilNow(io, .awake).toMilliseconds()});
    const first_revision = revisionOf(health);
    try testing.expectEqualStrings(build_options.product_version, health.get("product_version").?.string);
    try testing.expect(health.get("semantic_contract_version").? == .null);
    try testing.expectEqualStrings(copy.root, health.get("root").?.string);
    try testing.expect(!health.get("evidence_text").?.object.get("enabled").?.bool);
    const units = health.get("units").?.object;
    try testing.expectEqual(@as(i64, @intCast(copy.units)), units.get("total").?.integer);
    try testing.expect(units.get("current").?.integer > 0);
    for (health.get("languages").?.array.items) |language| {
        try testing.expect(language.object.get("parser").?.object.get("available").?.bool);
    }
    const diagnostics = health.get("diagnostics").?.object;
    try testing.expect(diagnostics.get("unsupported_construct").?.integer > 0);

    // -- repository map --------------------------------------------------------
    const map = try timedCall(client, 2, "semidx_repo_map", "{\"limit\":1000}");
    try testing.expectEqual(first_revision, revisionOf(map));
    try testing.expectEqual(@as(i64, @intCast(copy.units)), map.get("files_total").?.integer);
    try testing.expect(!map.get("truncated").?.bool);
    var mapped_definition = false;
    for (map.get("files").?.array.items) |file| {
        if (!std.mem.eql(u8, definition_path, file.object.get("unit").?.object.get("path").?.string)) continue;
        for (file.object.get("definitions").?.array.items) |definition| {
            if (std.mem.eql(u8, definition_name, definition.object.get("name").?.string)) mapped_definition = true;
        }
    }
    try testing.expect(mapped_definition);

    // -- definition lookup -----------------------------------------------------
    const found = try timedCall(client, 3, "semidx_find_definitions", "{\"name\":\"" ++ definition_name ++ "\",\"language\":\"zig\"}");
    try testing.expectEqual(@as(i64, 1), found.get("total").?.integer);
    const definition = found.get("definitions").?.array.items[0].object;
    const definition_id = definition.get("id").?.integer;
    try testing.expectEqualStrings(definition_path, definition.get("evidence").?.object.get("unit").?.object.get("path").?.string);
    try testing.expectEqualStrings("fact", definition.get("existence").?.object.get("resolution").?.object.get("category").?.string);
    try testing.expectEqualStrings("frontend.zig", definition.get("existence").?.object.get("producer").?.object.get("name").?.string);

    // -- references: the caller is a fact ----------------------------------------
    const by_id = try std.fmt.allocPrint(arena, "{{\"entity_id\":{d}}}", .{definition_id});
    const references = try timedCall(client, 4, "semidx_references", by_id);
    var caller_fact = false;
    for (references.get("relationships").?.array.items) |relationship| {
        const source_name = relationship.object.get("source").?.object.get("name").?.string;
        if (std.mem.eql(u8, caller_name, source_name) and std.mem.eql(u8, "fact", category(relationship))) {
            try testing.expectEqualStrings("calls", relationship.object.get("kind").?.string);
            caller_fact = true;
        }
    }
    try testing.expect(caller_fact);

    // -- context: the caller also calls through a value, which stays unresolved --
    const context = try timedCall(client, 5, "semidx_context", "{\"name\":\"" ++ caller_name ++ "\",\"path\":\"" ++ definition_path ++ "\"}");
    // Since Plan 006 the name also matches the `scan` member of the unit's test
    // `Tree` container; the top-level function is the one without a container.
    try testing.expectEqual(@as(i64, 2), context.get("focus_total").?.integer);
    const focus = for (context.get("focus").?.array.items) |item| {
        if (item.object.get("entity").?.object.get("container_path").?.array.items.len == 0) break item.object;
    } else return error.TestExpectedTopLevelFocus;
    var unresolved_designator: ?[]const u8 = null;
    var fact_to_definition = false;
    for (focus.get("outgoing").?.array.items) |relationship| {
        const target = relationship.object.get("target").?.object;
        if (std.mem.eql(u8, "unresolved", category(relationship))) {
            // An unresolved claim names no entity and says why.
            try testing.expect(target.get("entity") == null);
            try testing.expect(relationship.object.get("resolution").?.object.get("explanation") != null);
            unresolved_designator = target.get("designator").?.string;
        } else if (target.get("entity")) |entity| {
            if (entity.object.get("id").?.integer == definition_id) fact_to_definition = true;
        }
    }
    try testing.expect(fact_to_definition);
    try testing.expect(unresolved_designator != null);
    try testing.expect(focus.get("diagnostics_total").?.integer > 0);
    std.debug.print("dogfood: {s} has an unresolved outgoing call to `{s}`; {d} diagnostics in its unit\n", .{
        caller_name,
        unresolved_designator.?,
        focus.get("diagnostics_total").?.integer,
    });

    // -- Plan 006: a member function of a top-level container is a definition ---
    // Before Plan 006 it was an unsupported container member. The repository
    // map counts it as nested rather than as a top-level definition.
    var member_unit_nested: i64 = 0;
    for (map.get("files").?.array.items) |file| {
        if (!std.mem.eql(u8, member_path, file.object.get("unit").?.object.get("path").?.string)) continue;
        member_unit_nested = file.object.get("nested_definitions_total").?.integer;
        for (file.object.get("definitions").?.array.items) |top_level| {
            try testing.expect(!std.mem.eql(u8, member_name, top_level.object.get("name").?.string));
        }
    }
    try testing.expect(member_unit_nested > 0);
    const member = try timedCall(client, 21, "semidx_find_definitions", "{\"name\":\"" ++ member_name ++ "\",\"path\":\"" ++ member_path ++ "\"}");
    try testing.expectEqual(@as(i64, 1), member.get("total").?.integer);
    const member_definition = member.get("definitions").?.array.items[0].object;
    const member_containers = member_definition.get("container_path").?.array.items;
    try testing.expectEqual(@as(usize, 1), member_containers.len);
    try testing.expectEqualStrings(member_container, member_containers[0].string);
    try testing.expectEqualStrings("fact", member_definition.get("existence").?.object.get("resolution").?.object.get("category").?.string);
    try testing.expectEqualStrings("frontend.zig", member_definition.get("existence").?.object.get("producer").?.object.get("name").?.string);
    std.debug.print("dogfood: {s}.{s} is a definition; {d} nested definitions in {s}\n", .{ member_container, member_name, member_unit_nested, member_path });

    // -- Plan 006: a call through a local relative import is a cross-unit fact ---
    // Before Plan 006 every `protocol.writeString(...)` was an unresolved
    // designator, so references listed only same-unit callers.
    const imported = try timedCall(client, 22, "semidx_references", "{\"name\":\"" ++ imported_name ++ "\",\"path\":\"" ++ imported_path ++ "\",\"limit\":1000}");
    try testing.expect(!imported.get("truncated").?.bool);
    var cross_unit_facts: usize = 0;
    var same_unit_facts: usize = 0;
    for (imported.get("relationships").?.array.items) |relationship| {
        try testing.expectEqualStrings("calls", relationship.object.get("kind").?.string);
        try testing.expectEqualStrings("fact", category(relationship));
        try testing.expectEqualStrings("current", relationship.object.get("freshness").?.string);
        try testing.expectEqualStrings("frontend.zig", relationship.object.get("producer").?.object.get("name").?.string);
        const caller_path = relationship.object.get("evidence").?.object.get("unit").?.object.get("path").?.string;
        if (std.mem.eql(u8, caller_path, importer_path)) {
            cross_unit_facts += 1;
        } else if (std.mem.eql(u8, caller_path, imported_path)) {
            same_unit_facts += 1;
        }
    }
    try testing.expect(cross_unit_facts > 0);
    try testing.expect(same_unit_facts > 0);
    std.debug.print("dogfood: {s} in {s} has {d} call facts from {s} and {d} from its own unit\n", .{ imported_name, imported_path, cross_unit_facts, importer_path, same_unit_facts });

    // An import of a package stays unresolved: `std` is not a local file.
    const importer_context = try timedCall(client, 23, "semidx_context", "{\"name\":\"" ++ importer_caller ++ "\",\"path\":\"" ++ importer_path ++ "\",\"relationship_limit\":500}");
    var package_call_unresolved = false;
    var imported_call_fact = false;
    const importer_focus = for (importer_context.get("focus").?.array.items) |item| {
        if (item.object.get("entity").?.object.get("container_path").?.array.items.len == 0) break item.object;
    } else return error.TestExpectedTopLevelFocus;
    for (importer_focus.get("outgoing").?.array.items) |relationship| {
        const target = relationship.object.get("target").?.object;
        if (target.get("designator")) |designator| {
            if (std.mem.startsWith(u8, designator.string, "std.")) package_call_unresolved = true;
        } else if (std.mem.eql(u8, "fact", category(relationship))) {
            const target_path = target.get("entity").?.object.get("evidence").?.object.get("unit").?.object.get("path").?.string;
            if (std.mem.eql(u8, target_path, imported_path)) imported_call_fact = true;
        }
    }
    try testing.expect(imported_call_fact);
    try testing.expect(package_call_unresolved);

    // -- edit the copy, refresh, and observe the new revision --------------------
    const edited = try std.mem.concat(arena, u8, &.{ copy.definition_source, appended });
    try copy.tmp.dir.writeFile(io, .{ .sub_path = definition_path, .data = edited });
    const refreshed = try timedCall(client, 6, "semidx_refresh", "{}");
    const second_revision = revisionOf(refreshed);
    try testing.expect(second_revision > first_revision);
    try testing.expectEqual(first_revision, refreshed.get("previous_revision").?.integer);
    try testing.expect(refreshed.get("entity_ids_preserved").?.bool);
    const scan_outcome = refreshed.get("scan").?.object;
    try testing.expectEqual(@as(i64, 1), scan_outcome.get("changed").?.integer);
    try testing.expectEqual(@as(i64, 0), scan_outcome.get("added").?.integer);
    try testing.expectEqual(@as(i64, 0), scan_outcome.get("removed").?.integer);

    const probe = try timedCall(client, 7, "semidx_references", "{\"name\":\"dogfoodProbeCallee\",\"path\":\"" ++ definition_path ++ "\"}");
    try testing.expectEqual(second_revision, revisionOf(probe));
    try testing.expectEqual(@as(i64, 1), probe.get("relationships_total").?.integer);
    const probe_call = probe.get("relationships").?.array.items[0];
    try testing.expectEqualStrings("dogfoodProbe", probe_call.object.get("source").?.object.get("name").?.string);
    try testing.expectEqualStrings("fact", category(probe_call));
    try testing.expectEqualStrings("current", probe_call.object.get("freshness").?.string);

    // An edit elsewhere in the unit keeps the looked-up definition's identity.
    const again = try timedCall(client, 8, "semidx_find_definitions", "{\"name\":\"" ++ definition_name ++ "\",\"language\":\"zig\"}");
    try testing.expectEqual(second_revision, revisionOf(again));
    try testing.expectEqual(definition_id, again.get("definitions").?.array.items[0].object.get("id").?.integer);

    // -- shutdown and output discipline ----------------------------------------
    const ended = try client.shutdown();
    try testing.expectEqualStrings("", ended.trailing);
    try testing.expectEqual(@as(u8, 0), ended.exit_code);
    try testing.expect(std.unicode.utf8ValidateSlice(client.transcript.items));
    try testing.expect(std.mem.indexOf(u8, client.transcript.items, body_comment) == null);
    try testing.expect(std.mem.indexOf(u8, client.transcript.items, probe_marker) == null);
    try testing.expect(std.mem.indexOf(u8, client.transcript.items, "source_text") == null);
    const stderr_text = try log_dir.dir.readFileAlloc(io, "stderr.log", arena, .limited(1 << 20));
    try testing.expect(std.mem.indexOf(u8, stderr_text, "semidx-mcp: input closed; exiting") != null);
}

test "dogfood: --allow-evidence-text over a copy of this repository returns bounded source text from inside each evidence range" {
    const gpa = testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var copy = try copyRepository(arena);
    defer copy.tmp.cleanup();
    var log_dir = testing.tmpDir(.{});
    defer log_dir.cleanup();
    const client = try startServer(gpa, copy.root, &.{"--allow-evidence-text"}, log_dir.dir);
    defer client.destroy();

    const health = try timedCall(client, 1, "semidx_health", "{}");
    const evidence_text = health.get("evidence_text").?.object;
    try testing.expect(evidence_text.get("enabled").?.bool);
    try testing.expectEqual(@as(i64, evidence_text_max_bytes), evidence_text.get("max_bytes").?.integer);

    // Every definition's evidence carries at most the bound, and the text it
    // carries is source from inside the evidence range, not anything else.
    const map = try timedCall(client, 2, "semidx_repo_map", "{\"limit\":1000,\"definitions_per_file\":500}");
    try testing.expect(!map.get("truncated").?.bool);
    var checked: usize = 0;
    var truncated: usize = 0;
    for (map.get("files").?.array.items) |file| {
        const path = file.object.get("unit").?.object.get("path").?.string;
        const unit_source = copy.sources.get(path).?;
        try testing.expect(!file.object.get("definitions_truncated").?.bool);
        for (file.object.get("definitions").?.array.items) |definition| {
            const evidence = definition.object.get("evidence").?.object;
            const range = evidence.get("range").?.object;
            const start: usize = @intCast(range.get("start_byte").?.integer);
            const end: usize = @intCast(range.get("end_byte").?.integer);
            const returned = evidence.get("source_text").?.object;
            const text = returned.get("text").?.string;
            try testing.expect(text.len <= evidence_text_max_bytes);
            try testing.expect(std.mem.indexOf(u8, unit_source[start..end], text) != null);
            if (returned.get("truncated").?.bool) {
                try testing.expect(text.len > evidence_text_max_bytes - 4);
                truncated += 1;
            }
            checked += 1;
        }
    }
    try testing.expect(checked > 0);
    std.debug.print("dogfood: --allow-evidence-text: {d} definition evidence texts checked, {d} cut at the bound\n", .{ checked, truncated });

    const ended = try client.shutdown();
    try testing.expectEqualStrings("", ended.trailing);
    try testing.expectEqual(@as(u8, 0), ended.exit_code);
}
