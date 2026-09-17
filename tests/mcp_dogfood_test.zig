//! Dogfood proof for the local MCP preview over this repository.
//!
//! It copies the source units a scan of this repository finds into a temporary
//! root, byte for byte, and drives the built `semidx-mcp` over stdio through the
//! agent habit loop: health, repository map, definition lookup, references and
//! context, an edit of the copy, and a refresh that publishes a new revision.
//! The repository itself is never edited.
//!
//! The habit loop test is the `repository-copy` profile of the habit loop
//! gate (`docs/mcp/habit_loop_gate.md`): named hard gates fail through
//! `mcp_gate.zig`, and timing and size are observations in its evidence
//! summary, except the Plan 007 `compact_budget` gate: the default repository
//! map, references, and context transcripts are at most half of the same
//! calls with `detail: "full"` over the same snapshot.

const std = @import("std");
const build_options = @import("build_options");
const source = @import("semidx_source");

const mcp_gate = @import("mcp_gate.zig");
const Gate = mcp_gate.Gate;

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

/// The Plan 007 `compact_budget` gate: the compact transcript is at most half
/// the full one.
fn expectAtMostHalf(gate: *Gate, what: []const u8, compact_bytes: usize, full_bytes: usize) !void {
    const percent = compact_bytes * 100 / full_bytes;
    try gate.observe("budget: {s}: compact {d} bytes, full {d} bytes ({d}%)", .{ what, compact_bytes, full_bytes, percent });
    try gate.require(compact_bytes * 2 <= full_bytes, "compact_budget", "{s}: compact {d} bytes is more than half of full {d} bytes", .{ what, compact_bytes, full_bytes });
    try gate.pass("compact_budget", "{s}: {d}% of full", .{ what, percent });
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

    var log_dir = testing.tmpDir(.{});
    defer log_dir.cleanup();
    const started = std.Io.Timestamp.now(io, .awake);
    const client = try mcp_gate.startServer(gpa, build_options.mcp_exe, copy.root, &.{}, log_dir.dir);
    defer client.destroy();
    var gate = Gate.init(arena, "repository-copy", client, started);
    try gate.observe("root: temporary copy of {s}: {d} source units, {d} bytes", .{ build_options.repo_root, copy.units, copy.bytes });

    // -- health ---------------------------------------------------------------
    const health = try gate.call(1, "semidx_health", "{}");
    const first_revision = revisionOf(health);
    const diagnostics = try gate.checkHealth(health, build_options.product_version);
    try gate.requireDiagnostic(diagnostics, "unsupported_construct");
    try testing.expectEqualStrings(copy.root, health.get("root").?.string);
    const units = health.get("units").?.object;
    try testing.expectEqual(@as(i64, @intCast(copy.units)), units.get("total").?.integer);
    try testing.expect(units.get("current").?.integer > 0);

    // -- outline: the cold-start orientation call ------------------------------
    var outline_bytes: usize = undefined;
    const root_outline = try gate.sizedCall(28, "semidx_outline", "{}", &outline_bytes);
    try testing.expectEqual(first_revision, revisionOf(root_outline));
    try testing.expect(!root_outline.get("truncated").?.bool);
    const outline_totals = root_outline.get("totals").?.object;
    try testing.expectEqual(units.get("total").?.integer, outline_totals.get("units").?.integer);
    var outlined_units: i64 = 0;
    var src_directory = false;
    for (root_outline.get("entries").?.array.items) |entry| {
        const entry_counts = entry.object.get("counts").?.object;
        if (std.mem.eql(u8, "directory", entry.object.get("type").?.string)) {
            outlined_units += entry_counts.get("units").?.integer;
            if (std.mem.eql(u8, "src/", entry.object.get("path").?.string)) src_directory = true;
        } else outlined_units += 1;
    }
    try testing.expectEqual(outline_totals.get("units").?.integer, outlined_units);
    try testing.expect(src_directory);

    // -- repository map --------------------------------------------------------
    var map_bytes: usize = undefined;
    const map = try gate.sizedCall(2, "semidx_repo_map", "{\"limit\":1000,\"max_response_bytes\":2000000}", &map_bytes);
    try testing.expectEqualStrings("compact", map.get("budget").?.object.get("detail").?.string);
    var full_map_bytes: usize = undefined;
    const full_map = try gate.sizedCall(20, "semidx_repo_map", "{\"limit\":1000,\"detail\":\"full\",\"max_response_bytes\":2000000}", &full_map_bytes);
    try testing.expectEqual(first_revision, revisionOf(full_map));
    try testing.expectEqual(map.get("files_total").?.integer, full_map.get("files_total").?.integer);
    try expectAtMostHalf(&gate, "semidx_repo_map limit 1000", map_bytes, full_map_bytes);
    try gate.observe("outline: root outline {d} bytes against the compact whole-repository map {d} bytes ({d}%)", .{ outline_bytes, map_bytes, outline_bytes * 100 / map_bytes });
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
    // The default whole-repository map either fits its response budget or says
    // it did not and continues through cursor pages that together return every
    // file exactly once over the same snapshot.
    var paged_paths: std.StringHashMapUnmanaged(void) = .empty;
    var page_cursor: ?[]const u8 = null;
    var pages: usize = 0;
    var largest_page: usize = 0;
    while (true) {
        const arguments = if (page_cursor) |c| try std.fmt.allocPrint(arena, "{{\"cursor\":\"{s}\"}}", .{c}) else "{}";
        var page_bytes: usize = undefined;
        const page = try gate.sizedCall(100 + @as(i64, @intCast(pages)), "semidx_repo_map", arguments, &page_bytes);
        pages += 1;
        largest_page = @max(largest_page, page_bytes);
        try gate.require(pages <= copy.units, "response_budget", "the map walk did not end after {d} pages", .{pages});
        try gate.require(revisionOf(page) == first_revision and page.get("files_total").?.integer == map.get("files_total").?.integer, "response_budget", "map page {d} reads another snapshot or total", .{pages});
        const files = page.get("files").?.array.items;
        try gate.require(files.len > 0, "response_budget", "map page {d} returned no file", .{pages});
        for (files) |file| {
            const path = file.object.get("unit").?.object.get("path").?.string;
            try gate.require(!(try paged_paths.getOrPut(arena, path)).found_existing, "response_budget", "map pages returned {s} twice", .{path});
        }
        const next = page.get("next_cursor") orelse break;
        try gate.require(page.get("truncated").?.bool, "response_budget", "map page {d} has a next_cursor but is not truncated", .{pages});
        const cut_by_limit = page.get("offset").?.integer + page.get("budget").?.object.get("limit").?.integer < page.get("files_total").?.integer;
        try gate.require(page.get("budget_exhausted").?.bool or cut_by_limit, "response_budget", "map page {d} continues without reporting budget_exhausted or a limit cut", .{pages});
        page_cursor = next.string;
    }
    try gate.require(paged_paths.count() == copy.units, "response_budget", "map pages returned {d} of {d} files", .{ paged_paths.count(), copy.units });
    try gate.pass("response_budget", "the default map returned {d} files over {d} pages", .{ paged_paths.count(), pages });
    try gate.observe("response_budget: default map walk: {d} pages, largest page {d} bytes", .{ pages, largest_page });

    const bounded_map = try gate.call(26, "semidx_repo_map", "{\"limit\":2}");
    try gate.requireTruncated("semidx_repo_map limit 2", bounded_map, "files", "files_total", "truncated");

    // -- definition lookup -----------------------------------------------------
    const found = try gate.call(3, "semidx_find_definitions", "{\"name\":\"" ++ definition_name ++ "\",\"language\":\"zig\"}");
    try testing.expectEqual(@as(i64, 1), found.get("total").?.integer);
    const definition = found.get("definitions").?.array.items[0].object;
    const definition_id = definition.get("id").?.integer;
    try testing.expectEqualStrings(definition_path, definition.get("evidence").?.object.get("unit").?.object.get("path").?.string);
    try testing.expectEqualStrings("fact", definition.get("existence").?.object.get("resolution").?.object.get("category").?.string);
    try testing.expectEqualStrings("frontend.zig", definition.get("existence").?.object.get("producer").?.object.get("name").?.string);

    // -- references: the caller is a fact ----------------------------------------
    const by_id = try std.fmt.allocPrint(arena, "{{\"entity_id\":{d}}}", .{definition_id});
    const references = try gate.call(4, "semidx_references", by_id);
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
    const context = try gate.call(5, "semidx_context", "{\"name\":\"" ++ caller_name ++ "\",\"path\":\"" ++ definition_path ++ "\"}");
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
            // An unresolved claim names no entity and what is missing.
            try testing.expect(target.get("entity") == null);
            try testing.expect(relationship.object.get("resolution").?.object.get("missing") != null);
            unresolved_designator = target.get("designator").?.string;
        } else if (target.get("entity")) |entity| {
            if (entity.object.get("id").?.integer == definition_id) fact_to_definition = true;
        }
    }
    try gate.require(fact_to_definition, "resolution_visible", "{s} has no fact call to {s}", .{ caller_name, definition_name });
    try gate.require(unresolved_designator != null, "resolution_visible", "{s} has no unresolved outgoing call", .{caller_name});
    try testing.expect(focus.get("diagnostics_total").?.integer > 0);
    // The full context says why each unresolved claim is unresolved.
    const full_context = try gate.call(24, "semidx_context", "{\"name\":\"" ++ caller_name ++ "\",\"path\":\"" ++ definition_path ++ "\",\"detail\":\"full\"}");
    const full_focus = for (full_context.get("focus").?.array.items) |item| {
        if (item.object.get("entity").?.object.get("container_path").?.array.items.len == 0) break item.object;
    } else return error.TestExpectedTopLevelFocus;
    try testing.expectEqual(focus.get("outgoing_total").?.integer, full_focus.get("outgoing_total").?.integer);
    for (full_focus.get("outgoing").?.array.items) |relationship| {
        if (std.mem.eql(u8, "unresolved", category(relationship))) {
            try testing.expect(relationship.object.get("resolution").?.object.get("explanation") != null);
        }
    }
    try gate.pass("resolution_visible", "{s} calls {s} as a fact and `{s}` as unresolved", .{ caller_name, definition_name, unresolved_designator.? });
    try gate.observe("{s} has an unresolved outgoing call to `{s}`; {d} diagnostics in its unit", .{
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
    const member = try gate.call(21, "semidx_find_definitions", "{\"name\":\"" ++ member_name ++ "\",\"path\":\"" ++ member_path ++ "\"}");
    try testing.expectEqual(@as(i64, 1), member.get("total").?.integer);
    const member_definition = member.get("definitions").?.array.items[0].object;
    const member_containers = member_definition.get("container_path").?.array.items;
    try testing.expectEqual(@as(usize, 1), member_containers.len);
    try testing.expectEqualStrings(member_container, member_containers[0].string);
    try testing.expectEqualStrings("fact", member_definition.get("existence").?.object.get("resolution").?.object.get("category").?.string);
    try testing.expectEqualStrings("frontend.zig", member_definition.get("existence").?.object.get("producer").?.object.get("name").?.string);
    try gate.observe("{s}.{s} is a definition; {d} nested definitions in {s}", .{ member_container, member_name, member_unit_nested, member_path });

    // -- Plan 006: a call through a local relative import is a cross-unit fact ---
    // Before Plan 006 every `protocol.writeString(...)` was an unresolved
    // designator, so references listed only same-unit callers.
    var imported_bytes: usize = undefined;
    const imported = try gate.sizedCall(22, "semidx_references", "{\"name\":\"" ++ imported_name ++ "\",\"path\":\"" ++ imported_path ++ "\",\"limit\":1000,\"max_response_bytes\":2000000}", &imported_bytes);
    try testing.expect(!imported.get("truncated").?.bool);
    try testing.expectEqualStrings("compact", imported.get("budget").?.object.get("detail").?.string);
    var full_imported_bytes: usize = undefined;
    const full_imported = try gate.sizedCall(27, "semidx_references", "{\"name\":\"" ++ imported_name ++ "\",\"path\":\"" ++ imported_path ++ "\",\"limit\":1000,\"detail\":\"full\",\"max_response_bytes\":2000000}", &full_imported_bytes);
    try testing.expectEqual(imported.get("relationships_total").?.integer, full_imported.get("relationships_total").?.integer);
    try expectAtMostHalf(&gate, "semidx_references writeString limit 1000", imported_bytes, full_imported_bytes);
    // Every caller is classified: the named importer, the unit itself, and any
    // other unit calling through its own local import alias.
    const Bucket = struct { path: []const u8, facts: usize };
    var other_callers: std.ArrayList(Bucket) = .empty;
    var cross_unit_facts: usize = 0;
    var same_unit_facts: usize = 0;
    const imported_relationships = imported.get("relationships").?.array.items;
    try testing.expectEqual(@as(i64, @intCast(imported_relationships.len)), imported.get("relationships_total").?.integer);
    for (imported_relationships) |relationship| {
        try testing.expectEqualStrings("calls", relationship.object.get("kind").?.string);
        try testing.expectEqualStrings("fact", category(relationship));
        try testing.expectEqualStrings("current", relationship.object.get("freshness").?.string);
        try testing.expectEqualStrings("frontend.zig", relationship.object.get("producer").?.object.get("name").?.string);
        const caller_path = relationship.object.get("evidence").?.object.get("unit").?.object.get("path").?.string;
        if (std.mem.eql(u8, caller_path, importer_path)) {
            cross_unit_facts += 1;
        } else if (std.mem.eql(u8, caller_path, imported_path)) {
            same_unit_facts += 1;
        } else {
            try testing.expect(std.mem.endsWith(u8, caller_path, ".zig"));
            for (other_callers.items) |*bucket| {
                if (std.mem.eql(u8, bucket.path, caller_path)) {
                    bucket.facts += 1;
                    break;
                }
            } else try other_callers.append(arena, .{ .path = caller_path, .facts = 1 });
        }
    }
    try testing.expect(cross_unit_facts > 0);
    try testing.expect(same_unit_facts > 0);
    var other_facts: usize = 0;
    for (other_callers.items) |bucket| other_facts += bucket.facts;
    try testing.expectEqual(imported_relationships.len, cross_unit_facts + same_unit_facts + other_facts);
    try gate.observe("{s} in {s} has {d} call facts: {d} from {s}, {d} from its own unit, {d} from other units", .{ imported_name, imported_path, imported_relationships.len, cross_unit_facts, importer_path, same_unit_facts, other_facts });
    for (other_callers.items) |bucket| {
        try gate.observe("  {d} from {s}", .{ bucket.facts, bucket.path });
    }

    // An import of a package stays unresolved: `std` is not a local file.
    var importer_context_bytes: usize = undefined;
    const importer_context = try gate.sizedCall(23, "semidx_context", "{\"name\":\"" ++ importer_caller ++ "\",\"path\":\"" ++ importer_path ++ "\",\"relationship_limit\":500,\"max_response_bytes\":2000000}", &importer_context_bytes);
    var full_importer_context_bytes: usize = undefined;
    const full_importer_context = try gate.sizedCall(25, "semidx_context", "{\"name\":\"" ++ importer_caller ++ "\",\"path\":\"" ++ importer_path ++ "\",\"relationship_limit\":500,\"detail\":\"full\",\"max_response_bytes\":2000000}", &full_importer_context_bytes);
    try testing.expectEqual(importer_context.get("focus_total").?.integer, full_importer_context.get("focus_total").?.integer);
    try expectAtMostHalf(&gate, "semidx_context health relationship_limit 500", importer_context_bytes, full_importer_context_bytes);
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
    try gate.edited("append dogfoodProbe calling dogfoodProbeCallee to " ++ definition_path);
    const refreshed = try gate.refresh(6, first_revision);
    const second_revision = revisionOf(refreshed);
    try testing.expect(refreshed.get("entity_ids_preserved").?.bool);
    const scan_outcome = refreshed.get("scan").?.object;
    try testing.expectEqual(@as(i64, 1), scan_outcome.get("changed").?.integer);
    try testing.expectEqual(@as(i64, 0), scan_outcome.get("added").?.integer);
    try testing.expectEqual(@as(i64, 0), scan_outcome.get("removed").?.integer);

    const probe = try gate.call(7, "semidx_references", "{\"name\":\"dogfoodProbeCallee\",\"path\":\"" ++ definition_path ++ "\"}");
    try testing.expectEqual(second_revision, revisionOf(probe));
    try gate.require(probe.get("relationships_total").?.integer == 1, "new_snapshot_observed", "the refreshed snapshot does not show the call added by the edit", .{});
    const probe_call = probe.get("relationships").?.array.items[0];
    try testing.expectEqualStrings("dogfoodProbe", probe_call.object.get("source").?.object.get("name").?.string);
    try testing.expectEqualStrings("fact", category(probe_call));
    try testing.expectEqualStrings("current", probe_call.object.get("freshness").?.string);

    // An edit elsewhere in the unit keeps the looked-up definition's identity.
    const again = try gate.call(8, "semidx_find_definitions", "{\"name\":\"" ++ definition_name ++ "\",\"language\":\"zig\"}");
    try testing.expectEqual(second_revision, revisionOf(again));
    try testing.expectEqual(definition_id, again.get("definitions").?.array.items[0].object.get("id").?.integer);
    try gate.pass("new_snapshot_observed", "post-refresh calls read revision {d} and see the added call", .{second_revision});

    // -- shutdown and output discipline ----------------------------------------
    try gate.finish(log_dir.dir, &.{ body_comment, probe_marker });
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
    const client = try mcp_gate.startServer(gpa, build_options.mcp_exe, copy.root, &.{"--allow-evidence-text"}, log_dir.dir);
    defer client.destroy();

    const health = try client.callTool(1, "semidx_health", "{}");
    const evidence_text = health.get("evidence_text").?.object;
    try testing.expect(evidence_text.get("enabled").?.bool);
    try testing.expectEqual(@as(i64, evidence_text_max_bytes), evidence_text.get("max_bytes").?.integer);

    // Every definition's evidence carries at most the bound, and the text it
    // carries is source from inside the evidence range, not anything else.
    const map = try client.callTool(2, "semidx_repo_map", "{\"limit\":1000,\"definitions_per_file\":500,\"detail\":\"full\",\"max_response_bytes\":2000000}");
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
