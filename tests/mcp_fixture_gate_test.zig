//! The `fixture` profile of the habit loop gate (`docs/mcp/habit_loop_gate.md`).
//!
//! It copies a few `fixtures/vertical-slice` files into a temporary root, adds
//! a unit that fails analysis and a file no frontend indexes, and drives the
//! built `semidx-mcp` over stdio through the habit loop. The edit makes one
//! analyzed unit unparsable and repairs the failing one, so the refreshed
//! snapshot must show stale claims as stale and repaired ones as current.
//! Nothing under `fixtures/` is edited.

const std = @import("std");
const build_options = @import("build_options");

const mcp_gate = @import("mcp_gate.zig");
const Gate = mcp_gate.Gate;
const ObjectMap = mcp_gate.ObjectMap;

const testing = std.testing;
const io = testing.io;

/// Fixture files copied into the root, as `fixtures/vertical-slice` path and
/// root path.
const copied = [_][2][]const u8{
    .{ "zig/greeter.zig", "greeter.zig" },
    .{ "zig/edits/05_unparsable.zig", "broken.zig" },
    .{ "clojure/greeter.clj", "greeter.clj" },
    .{ "java/Greeter.java", "Greeter.java" },
    .{ "zig/imports/session.zig", "imports/session.zig" },
    .{ "zig/imports/wire.zig", "imports/wire.zig" },
    .{ "zig/imports/support/util.zig", "imports/support/util.zig" },
};

/// A file in the root with an extension no frontend declares.
const unindexed_path = "tool.py";

/// Body text of the copied source. No result may contain it.
const body_texts = [_][]const u8{ "hello", "self.name", "text.len", "self.sent" };

fn readFixture(arena: std.mem.Allocator, path: []const u8) ![]const u8 {
    const full = try std.fs.path.join(arena, &.{ build_options.fixtures_dir, path });
    return std.Io.Dir.cwd().readFileAlloc(io, full, arena, .limited(1 << 20));
}

fn category(relationship: std.json.Value) []const u8 {
    return relationship.object.get("resolution").?.object.get("category").?.string;
}

/// The top-level definition among `definitions`, the one with no container.
fn topLevel(definitions: []const std.json.Value) ?ObjectMap {
    for (definitions) |definition| {
        if (definition.object.get("container_path").?.array.items.len == 0) return definition.object;
    }
    return null;
}

test "habit loop gate: fixture profile degrades honestly over a controlled root" {
    const gpa = testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var root_dir = testing.tmpDir(.{});
    defer root_dir.cleanup();
    var bytes: usize = 0;
    for (copied) |file| {
        const contents = try readFixture(arena, file[0]);
        if (std.fs.path.dirnamePosix(file[1])) |parent| try root_dir.dir.createDirPath(io, parent);
        try root_dir.dir.writeFile(io, .{ .sub_path = file[1], .data = contents });
        bytes += contents.len;
    }
    try root_dir.dir.writeFile(io, .{ .sub_path = unindexed_path, .data = "print(\"not indexed\")\n" });
    const root = try root_dir.dir.realPathFileAlloc(io, ".", arena);

    var log_dir = testing.tmpDir(.{});
    defer log_dir.cleanup();
    const started = std.Io.Timestamp.now(io, .awake);
    const client = try mcp_gate.startServer(gpa, build_options.mcp_exe, root, &.{}, log_dir.dir);
    defer client.destroy();
    var gate = Gate.init(arena, "fixture", client, started);
    try gate.observe("root: temporary directory of {d} fixtures/vertical-slice files ({d} bytes) and {s}", .{ copied.len, bytes, unindexed_path });

    // -- health: the failing unit is pending, the unindexed file is no unit ----
    const health = try gate.call(1, "semidx_health", "{}");
    const first_revision = mcp_gate.snapshotRevision(health).?;
    const diagnostics = try gate.checkHealth(health, build_options.product_version);
    try gate.requireDiagnostic(diagnostics, "unsupported_construct");
    try gate.requireDiagnostic(diagnostics, "analysis_failed");
    const units = health.get("units").?.object;
    try gate.require(units.get("total").?.integer == copied.len, "honest_degradation", "health counts {d} units for {d} indexable files", .{ units.get("total").?.integer, copied.len });
    try gate.require(units.get("pending").?.integer == 1, "honest_degradation", "health counts {d} pending units, not the one that failed analysis", .{units.get("pending").?.integer});

    // -- outline: the failing unit is counted pending, the unindexed file is absent
    const root_outline = try gate.call(12, "semidx_outline", "{}");
    const outline_totals = root_outline.get("totals").?.object;
    try gate.require(outline_totals.get("units").?.integer == copied.len and
        outline_totals.get("analysis").?.object.get("pending").?.integer == 1 and
        outline_totals.get("diagnostics").?.object.get("analysis_failed").?.integer == 1, "honest_degradation", "the outline does not count {d} units with one pending and one analysis failure", .{copied.len});
    for (root_outline.get("entries").?.array.items) |entry| {
        try gate.require(!std.mem.eql(u8, unindexed_path, entry.object.get("name").?.string), "honest_degradation", "{s} is listed in the outline", .{unindexed_path});
    }

    // -- repository map --------------------------------------------------------
    const map = try gate.call(2, "semidx_repo_map", "{}");
    try testing.expectEqual(@as(i64, copied.len), map.get("files_total").?.integer);
    var broken_pending = false;
    for (map.get("files").?.array.items) |file| {
        const unit = file.object.get("unit").?.object;
        const path = unit.get("path").?.string;
        try gate.require(!std.mem.eql(u8, path, unindexed_path), "honest_degradation", "{s} is listed as a unit", .{unindexed_path});
        if (std.mem.eql(u8, path, "broken.zig")) {
            broken_pending = std.mem.eql(u8, "pending", unit.get("analysis").?.string) and
                file.object.get("definitions").?.array.items.len == 0 and
                file.object.get("diagnostics").?.object.get("analysis_failed").?.integer == 1;
        }
    }
    try gate.require(broken_pending, "honest_degradation", "broken.zig is not reported pending, without definitions, with its analysis failure", .{});
    const bounded_map = try gate.call(3, "semidx_repo_map", "{\"limit\":2}");
    try gate.requireTruncated("semidx_repo_map limit 2", bounded_map, "files", "files_total", "truncated");

    // -- definition lookup: a current fact, told apart from a same-named member --
    const found = try gate.call(4, "semidx_find_definitions", "{\"name\":\"greet\",\"path\":\"greeter.zig\"}");
    try testing.expectEqual(@as(i64, 2), found.get("total").?.integer);
    const greet = topLevel(found.get("definitions").?.array.items) orelse return error.TestExpectedTopLevelGreet;
    const greet_id = greet.get("id").?.integer;
    try testing.expectEqualStrings("current", greet.get("freshness").?.string);
    try testing.expectEqualStrings("fact", greet.get("existence").?.object.get("resolution").?.object.get("category").?.string);

    // -- references: `announce` calls `greet` as a current fact -----------------
    const references = try gate.call(5, "semidx_references", try std.fmt.allocPrint(arena, "{{\"entity_id\":{d}}}", .{greet_id}));
    var announce_calls = false;
    for (references.get("relationships").?.array.items) |relationship| {
        if (std.mem.eql(u8, "announce", relationship.object.get("source").?.object.get("name").?.string) and
            std.mem.eql(u8, "fact", category(relationship)) and
            std.mem.eql(u8, "current", relationship.object.get("freshness").?.string)) announce_calls = true;
    }
    try gate.require(announce_calls, "resolution_visible", "references to greet list no current call fact from announce", .{});

    // -- context: `report` has no definition and stays unresolved ----------------
    const context = try gate.call(6, "semidx_context", "{\"name\":\"announce\",\"path\":\"greeter.zig\"}");
    const focus = context.get("focus").?.array.items[0].object;
    var report_unresolved = false;
    var greet_fact = false;
    for (focus.get("outgoing").?.array.items) |relationship| {
        const target = relationship.object.get("target").?.object;
        if (target.get("designator")) |designator| {
            if (std.mem.eql(u8, "report", designator.string)) {
                report_unresolved = std.mem.eql(u8, "unresolved", category(relationship)) and
                    target.get("entity") == null and
                    relationship.object.get("resolution").?.object.get("missing") != null;
            }
        } else if (target.get("entity").?.object.get("id").?.integer == greet_id) {
            greet_fact = std.mem.eql(u8, "fact", category(relationship));
        }
    }
    try gate.require(report_unresolved, "resolution_visible", "announce's call to report is not unresolved with a designator, no entity, and what is missing", .{});
    try gate.require(greet_fact, "resolution_visible", "announce's call to greet is not a fact", .{});
    try gate.pass("resolution_visible", "announce calls greet as a fact and `report` as unresolved", .{});
    try gate.require(focus.get("diagnostics_total").?.integer > 0, "diagnostics_visible", "announce's context shows no diagnostics for its unit", .{});

    // -- edit: break greeter.zig, repair broken.zig, and refresh ---------------
    try root_dir.dir.writeFile(io, .{ .sub_path = "greeter.zig", .data = try readFixture(arena, "zig/edits/05_unparsable.zig") });
    try root_dir.dir.writeFile(io, .{ .sub_path = "broken.zig", .data = try readFixture(arena, "zig/greeter.zig") });
    try gate.edited("make greeter.zig unparsable and repair broken.zig");
    const refreshed = try gate.refresh(7, first_revision);
    const refreshed_units = refreshed.get("units").?.object;
    try gate.require(refreshed_units.get("stale").?.integer == 1 and refreshed_units.get("pending").?.integer == 0, "honest_degradation", "after the refresh {d} units are stale and {d} pending, not 1 and 0", .{ refreshed_units.get("stale").?.integer, refreshed_units.get("pending").?.integer });

    // -- after the refresh: stale claims are not current, repaired ones are ----
    const current_greet = try gate.call(8, "semidx_find_definitions", "{\"name\":\"greet\",\"path\":\"greeter.zig\"}");
    try gate.require(current_greet.get("total").?.integer == 0, "honest_degradation", "a default lookup still returns greeter.zig's definitions as current", .{});
    const any_greet = try gate.call(9, "semidx_find_definitions", "{\"name\":\"greet\",\"path\":\"greeter.zig\",\"freshness\":\"any\"}");
    const stale_greet = topLevel(any_greet.get("definitions").?.array.items) orelse {
        try gate.require(false, "honest_degradation", "greeter.zig's greet is gone rather than stale", .{});
        unreachable;
    };
    try gate.require(stale_greet.get("id").?.integer == greet_id and std.mem.eql(u8, "stale", stale_greet.get("freshness").?.string), "honest_degradation", "greeter.zig's greet is not the same entity marked stale", .{});
    const stale_context = try gate.call(10, "semidx_context", "{\"path\":\"greeter.zig\",\"relationship_limit\":1}");
    const stale_unit = stale_context.get("focus").?.array.items[0].object.get("unit").?.object;
    try gate.require(std.mem.eql(u8, "stale", stale_unit.get("analysis").?.string), "honest_degradation", "greeter.zig's unit reports analysis {s}, not stale", .{stale_unit.get("analysis").?.string});
    try gate.pass("honest_degradation", "failing unit pending, unindexed file no unit, unparsable edit leaves greet stale under the same id", .{});

    const repaired = try gate.call(11, "semidx_find_definitions", "{\"name\":\"greet\",\"path\":\"broken.zig\"}");
    const repaired_greet = topLevel(repaired.get("definitions").?.array.items);
    try gate.require(repaired_greet != null and std.mem.eql(u8, "current", repaired_greet.?.get("freshness").?.string), "new_snapshot_observed", "the refreshed snapshot does not show broken.zig's repaired greet as current", .{});
    try gate.pass("new_snapshot_observed", "post-refresh calls read revision {d} and see the repair and the breakage", .{mcp_gate.snapshotRevision(refreshed).?});

    try gate.finish(log_dir.dir, &body_texts);
}
