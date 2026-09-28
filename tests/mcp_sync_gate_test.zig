//! The `sync-trust` profile of the habit loop gate (`docs/mcp/habit_loop_gate.md`,
//! [Plan 016](../docs/plans/016_trustworthy_working_copy_sync.md) Stage 5).
//!
//! It copies the nine synthetic units `fixtures/working_copy_sync/units/`
//! froze in Stage 0 into a temporary root and reproduces the ADR 014
//! regression sequence end to end over the built `semidx-mcp`: index, an
//! external branch-switch-shaped edit (one unit changed, one removed, one
//! added) applied directly to the root from outside the server, a graph read
//! that must fail closed before syncing, a sync that publishes the batch in
//! one pass, a graph read that must then succeed with corrected data, a
//! cursor issued before the edit that must fail after the revision changes,
//! and a scan failure once the root disappears entirely. Nothing under
//! `fixtures/` is edited.

const std = @import("std");
const build_options = @import("build_options");

const mcp_gate = @import("mcp_gate.zig");
const Gate = mcp_gate.Gate;
const ObjectMap = mcp_gate.ObjectMap;
const stdio_client = @import("mcp_stdio_client.zig");

const testing = std.testing;
const io = testing.io;

const unit_count = 9;

fn readFixture(arena: std.mem.Allocator, path: []const u8) ![]const u8 {
    const full = try std.fs.path.join(arena, &.{ build_options.fixtures_dir, path });
    return std.Io.Dir.cwd().readFileAlloc(io, full, arena, .limited(1 << 20));
}

fn workingCopyStatus(result: ObjectMap) []const u8 {
    return result.get("working_copy").?.object.get("status").?.string;
}

fn sourceStateId(result: ObjectMap) []const u8 {
    return result.get("snapshot").?.object.get("source_state_id").?.string;
}

/// Calls a tool and returns its raw `CallToolResult` object regardless of
/// `isError`, unlike `Gate.call`/`Gate.sizedCall`, which require success. Used
/// only for the calls this profile expects to fail closed.
fn rawCallTool(gate: *Gate, id: i64, name: []const u8, arguments: []const u8) !ObjectMap {
    const arena = gate.arena;
    const params = try std.fmt.allocPrint(arena, "{{{s},\"name\":\"{s}\",\"arguments\":{s}}}", .{ stdio_client.modern_meta, name, arguments });
    const response = try gate.client.request(id, "tools/call", params);
    const result = response.object.get("result").?.object;
    try testing.expectEqualStrings("complete", result.get("resultType").?.string);
    return result;
}

test "habit loop gate: sync-trust profile proves the trust contract end to end" {
    const gpa = testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var root_dir = testing.tmpDir(.{});
    defer root_dir.cleanup();
    var bytes: usize = 0;
    for (1..unit_count + 1) |i| {
        const name = try std.fmt.allocPrint(arena, "unit_{d:0>2}.zig", .{i});
        const contents = try readFixture(arena, try std.fmt.allocPrint(arena, "units/{s}", .{name}));
        try root_dir.dir.writeFile(io, .{ .sub_path = name, .data = contents });
        bytes += contents.len;
    }
    const root = try root_dir.dir.realPathFileAlloc(io, ".", arena);

    var log_dir = testing.tmpDir(.{});
    defer log_dir.cleanup();
    const started = std.Io.Timestamp.now(io, .awake);
    const client = try mcp_gate.startServer(gpa, build_options.mcp_exe, root, &.{}, log_dir.dir);
    defer client.destroy();
    var gate = Gate.init(arena, "sync-trust", client, started);
    try gate.observe("root: temporary directory of {d} fixtures/working_copy_sync/units files ({d} bytes)", .{ unit_count, bytes });

    // -- sync first: idempotent, deterministic, and stable across repeats -----
    const first_sync = try gate.call(1, "semidx_sync", "{}");
    try gate.require(!first_sync.get("changed").?.bool, "source_state_identity_deterministic", "the first sync over an unscanned-but-unchanged root reported changed", .{});
    const first_revision = mcp_gate.snapshotRevision(first_sync).?;
    const first_id = sourceStateId(first_sync);

    const second_sync = try gate.call(2, "semidx_sync", "{}");
    try gate.require(!second_sync.get("changed").?.bool, "unchanged_sync_stable", "a second sync over the same unchanged root reported changed", .{});
    try gate.require(mcp_gate.snapshotRevision(second_sync).? == first_revision, "unchanged_sync_stable", "a second unchanged sync advanced the revision from {d}", .{first_revision});
    try gate.require(std.mem.eql(u8, first_id, sourceStateId(second_sync)), "source_state_identity_deterministic", "two syncs over the same unchanged root reported different source_state_id values", .{});
    try gate.pass("source_state_identity_deterministic", "repeated sync over an unchanged root reports the same source_state_id", .{});
    try gate.pass("unchanged_sync_stable", "revision {d} and source_state_id unchanged across a no-op sync", .{first_revision});

    // -- health, outline, map, definitions, references, context --------------
    const health = try gate.call(3, "semidx_health", "{}");
    _ = try gate.checkHealth(health, build_options.product_version);
    try gate.require(std.mem.eql(u8, "in_sync", workingCopyStatus(health)), "unchanged_sync_stable", "health does not report in_sync before any edit", .{});

    _ = try gate.call(4, "semidx_outline", "{}");

    // A bounded map issues a cursor this test later proves does not survive
    // the sync past the edit (the cursor-restart hard gate).
    const bounded_map = try gate.call(5, "semidx_repo_map", "{\"limit\":1}");
    try gate.requireTruncated("semidx_repo_map limit 1", bounded_map, "files", "files_total", "truncated");
    const pre_edit_cursor = bounded_map.get("next_cursor").?.string;

    const found = try gate.call(6, "semidx_find_definitions", "{\"name\":\"unit03Value\"}");
    try gate.require(found.get("total").?.integer == 1, "external_edit_detected", "unit03Value is not found uniquely before the edit", .{});
    const unit03_id = found.get("definitions").?.array.items[0].object.get("id").?.integer;
    const original_range = found.get("definitions").?.array.items[0].object.get("evidence").?.object.get("range").?.object;
    const original_end_line = original_range.get("end_line").?.integer;

    _ = try gate.call(7, "semidx_references", try std.fmt.allocPrint(arena, "{{\"entity_id\":{d}}}", .{unit03_id}));
    _ = try gate.call(8, "semidx_context", "{\"name\":\"unit03Value\"}");

    // -- branch-switch-shaped batch: one unit changed, one removed, one added -
    try root_dir.dir.writeFile(io, .{ .sub_path = "unit_03.zig", .data = try readFixture(arena, "units/unit_03_edited.zig") });
    try root_dir.dir.deleteFile(io, "unit_09.zig");
    try root_dir.dir.writeFile(io, .{ .sub_path = "unit_10.zig", .data = "pub fn unit10Value() i32 {\n    return 10;\n}\n" });
    try gate.edited("change unit_03.zig, remove unit_09.zig, add unit_10.zig in one batch");

    // -- graph reads fail closed before syncing this batch --------------------
    const blocked = try rawCallTool(&gate, 9, "semidx_find_definitions", "{\"name\":\"unit03Value\"}");
    try gate.require(blocked.get("isError").?.bool, "external_edit_detected", "a read after the external batch edit did not fail", .{});
    const blocked_text = blocked.get("content").?.array.items[0].object.get("text").?.string;
    try gate.require(std.mem.startsWith(u8, blocked_text, "semidx_preflight_out_of_date:"), "external_edit_detected", "the blocked read's error does not start with semidx_preflight_out_of_date:", .{});
    try gate.require(blocked.get("structuredContent") == null, "graph_read_refusal", "a blocked read still carries structuredContent", .{});
    try gate.pass("external_edit_detected", "a read after an external batch edit fails with semidx_preflight_out_of_date", .{});
    try gate.pass("graph_read_refusal", "the blocked read carries no structuredContent", .{});

    // -- sync publishes the whole batch in one pass ---------------------------
    const refreshed = try gate.refresh(10, first_revision);
    const scan = refreshed.get("scan").?.object;
    try gate.require(scan.get("changed").?.integer >= 1 and scan.get("removed").?.integer >= 1 and scan.get("added").?.integer >= 1, "branch_switch_batch", "one sync over a changed+removed+added batch does not report all three: changed {d}, removed {d}, added {d}", .{ scan.get("changed").?.integer, scan.get("removed").?.integer, scan.get("added").?.integer });
    try gate.pass("branch_switch_batch", "one sync reports changed {d}, removed {d}, added {d}", .{ scan.get("changed").?.integer, scan.get("removed").?.integer, scan.get("added").?.integer });
    try gate.require(std.mem.eql(u8, "in_sync", workingCopyStatus(refreshed)), "corrected_post_sync_ranges", "the sync's own result is not in_sync", .{});

    // -- reads succeed again, with corrected data -----------------------------
    const after = try gate.call(11, "semidx_context", "{\"name\":\"unit03Value\"}");
    try gate.require(std.mem.eql(u8, "in_sync", workingCopyStatus(after)), "corrected_post_sync_ranges", "a post-sync read does not report working_copy in_sync", .{});
    const after_focus = after.get("focus").?.array.items[0].object.get("entity").?.object;
    const after_end_line = after_focus.get("evidence").?.object.get("range").?.object.get("end_line").?.integer;
    try gate.require(after_end_line != original_end_line, "corrected_post_sync_ranges", "unit03Value's range did not change even though its body did", .{});
    try gate.pass("corrected_post_sync_ranges", "unit03Value's range changed from end_line {d} to {d} after sync", .{ original_end_line, after_end_line });

    const removed_gone = try gate.call(12, "semidx_find_definitions", "{\"name\":\"unit09Value\"}");
    try gate.require(removed_gone.get("total").?.integer == 0, "branch_switch_batch", "unit09Value still exists as current after its unit was removed", .{});
    const added_present = try gate.call(13, "semidx_find_definitions", "{\"name\":\"unit10Value\"}");
    try gate.require(added_present.get("total").?.integer == 1, "branch_switch_batch", "unit10Value is not found after its unit was added", .{});

    // -- a cursor issued before the sync fails after the revision changes -----
    const cursor_retry = try rawCallTool(&gate, 14, "semidx_repo_map", try std.fmt.allocPrint(arena, "{{\"limit\":1,\"cursor\":\"{s}\"}}", .{pre_edit_cursor}));
    try gate.require(cursor_retry.get("isError").?.bool, "cursor_restart", "a cursor issued before the sync still verifies after the revision changed", .{});
    try gate.pass("cursor_restart", "a pre-sync cursor fails after the revision changed", .{});

    // -- scan failure is refused, not silently answered from the old snapshot -
    try root_dir.parent_dir.deleteTree(io, &root_dir.sub_path);
    const scan_failed = try rawCallTool(&gate, 15, "semidx_find_definitions", "{\"name\":\"unit03Value\"}");
    try gate.require(scan_failed.get("isError").?.bool, "scan_failure_refusal", "a read after the root disappeared did not fail", .{});
    const scan_failed_text = scan_failed.get("content").?.array.items[0].object.get("text").?.string;
    try gate.require(std.mem.startsWith(u8, scan_failed_text, "semidx_preflight_scan_failed:"), "scan_failure_refusal", "the scan-failure read's error does not start with semidx_preflight_scan_failed:", .{});
    try gate.pass("scan_failure_refusal", "a read over a disappeared root fails with semidx_preflight_scan_failed", .{});

    const health_after_loss = try gate.call(16, "semidx_health", "{}");
    try gate.require(std.mem.eql(u8, "scan_failed", workingCopyStatus(health_after_loss)), "scan_failure_refusal", "health does not report scan_failed once the root disappeared", .{});
    try gate.require(health_after_loss.get("units") != null, "scan_failure_refusal", "health stopped reporting its retained counts on scan failure", .{});

    try gate.finish(log_dir.dir, &.{});
}
