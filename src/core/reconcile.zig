//! Applying one frontend's account of one source unit to an existing graph.
//!
//! This is the only path into the graph for frontend output, on a first build
//! and on every later edit alike. There is no separate "full rebuild" path to
//! fall back to, so incrementality and identity preservation cannot quietly
//! stop being exercised.
//!
//! Correspondence is decided from identity evidence, never from a frontend's
//! own identifiers and never from source position. When correspondence cannot
//! be established, the break is recorded as a break.

const std = @import("std");
const Allocator = std.mem.Allocator;

const model = @import("model.zig");
const contract = @import("contract.zig");
const graph_mod = @import("graph.zig");
const Graph = graph_mod.Graph;

pub const Error = graph_mod.GraphError;

pub const Outcome = struct {
    revision: u64,
    /// False when the batch reported that analysis could not run. The prior
    /// state of the unit is then left in place: unavailable analysis must not
    /// be applied as if it were an observation of absence.
    applied: bool,
    preserved: usize = 0,
    created: usize = 0,
    removed: usize = 0,
    lost: usize = 0,
};

pub fn integrate(graph: *Graph, batch: contract.FrontendBatch) Error!Outcome {
    const unit = graph.unit(batch.unit) orelse return error.UnknownSourceUnit;
    const revision = graph.beginRevision();
    const producer = batch.capabilities.producer;

    if (batch.hasBlockingDiagnostic()) {
        for (batch.diagnostics) |diagnostic| {
            try graph.addDiagnostic(diagnostic.kind, batch.unit, producer, diagnostic.message);
        }
        return .{ .revision = revision, .applied = false };
    }

    const gpa = graph.gpa;

    var previous: std.ArrayList(model.EntityId) = .empty;
    defer previous.deinit(gpa);
    try graph.definitionsInUnit(batch.unit, &previous, gpa);

    const matched_previous = try gpa.alloc(bool, previous.items.len);
    defer gpa.free(matched_previous);
    @memset(matched_previous, false);

    const local_ids = try gpa.alloc(?model.EntityId, batch.entities.len);
    defer gpa.free(local_ids);
    @memset(local_ids, null);

    // Every assertion derived from this unit's contents is withdrawn before
    // the new ones are recorded. Other units keep their entities and their
    // assertions: an edit here is not a reason to reanalyze them.
    graph.dropAssertionsForUnit(batch.unit);
    graph.dropDiagnosticsForUnit(batch.unit);

    var outcome: Outcome = .{ .revision = revision, .applied = true };

    // Pass 1: correspondence. A matched entity keeps its id.
    for (batch.entities, 0..) |draft, index| {
        for (previous.items, matched_previous) |candidate, *matched| {
            if (matched.*) continue;
            const existing = graph.entity(candidate).?;
            if (!existing.identity.corresponds(draft.identity)) continue;
            matched.* = true;
            local_ids[index] = candidate;
            try graph.refreshEntity(candidate, draft.evidence, draft.extension);
            try graph.addIdentityEvent(
                .preserved,
                candidate,
                null,
                "identity evidence matched the previous revision",
            );
            _ = try graph.addAssertion(
                .{ .identity_correspondence = .{ .current = candidate, .previous = candidate } },
                graph_mod.reconciler,
                draft.evidence,
                .{ .fact = .{ .method = "identity evidence matched the previous revision" } },
            );
            outcome.preserved += 1;
            break;
        }
    }

    // Pass 2: everything without correspondence becomes a new entity.
    for (batch.entities, 0..) |draft, index| {
        if (local_ids[index] != null) continue;
        const id = try graph.addEntity(.{
            .kind = draft.kind,
            .identity = draft.identity,
            .evidence = draft.evidence,
            .extension = draft.extension,
            .producer = producer,
            .resolution = draft.resolution,
        });
        local_ids[index] = id;
        try graph.addIdentityEvent(.created, id, null, "no previous entity corresponded");
        outcome.created += 1;
    }

    // Pass 3: previous entities nothing corresponded to. If a new entity took
    // the same slot, the break is reported as identity loss with its
    // replacement, not as an unrelated deletion followed by a creation.
    var claimed_replacement = try gpa.alloc(bool, batch.entities.len);
    defer gpa.free(claimed_replacement);
    @memset(claimed_replacement, false);

    for (previous.items, matched_previous) |candidate, matched| {
        if (matched) continue;
        const existing = graph.entity(candidate).?;

        var replacement: ?model.EntityId = null;
        var replacement_evidence: ?model.SourceEvidence = null;
        for (batch.entities, 0..) |draft, index| {
            if (claimed_replacement[index]) continue;
            // Only an entity created in this revision can be a replacement; a
            // preserved one is already accounted for.
            const created_here = graph.entity(local_ids[index].?).?.created_revision == revision;
            if (!created_here) continue;
            if (!existing.identity.sameSlot(draft.identity)) continue;
            claimed_replacement[index] = true;
            replacement = local_ids[index].?;
            replacement_evidence = draft.evidence;
            break;
        }

        if (replacement) |new_id| {
            try graph.addIdentityEvent(
                .lost,
                candidate,
                new_id,
                "a new entity took this slot and correspondence could not be established",
            );
            _ = try graph.addAssertion(
                .{ .identity_correspondence = .{ .current = new_id, .previous = candidate } },
                graph_mod.reconciler,
                replacement_evidence.?,
                .{ .unresolved = .{
                    .missing = .identity_correspondence,
                    .explanation = "identity evidence differs from the previous revision",
                } },
            );
            outcome.lost += 1;
        } else {
            try graph.addIdentityEvent(
                .removed,
                candidate,
                null,
                "the definition is no longer present in this source unit",
            );
            outcome.removed += 1;
        }
        try graph.removeEntity(candidate);
    }

    // Existence assertions are re-recorded for preserved entities too: the old
    // ones were withdrawn with the rest of the unit's analysis.
    for (batch.entities, 0..) |draft, index| {
        const id = local_ids[index].?;
        if (graph.entity(id).?.created_revision == revision) continue;
        _ = try graph.addAssertion(
            .{ .entity_exists = id },
            producer,
            draft.evidence,
            draft.resolution,
        );
    }

    for (batch.relationships) |draft| {
        const source = switch (draft.source) {
            .unit_container => unit.entity,
            .entity => |index| local_ids[index].?,
        };
        const target: model.Target = switch (draft.target) {
            .local => |index| .{ .entity = local_ids[index].? },
            .designator => |name| .{ .designator = name },
        };
        _ = try graph.addRelationship(
            .{ .kind = draft.kind, .source = source, .target = target },
            producer,
            draft.evidence,
            draft.resolution,
        );
    }

    for (batch.diagnostics) |diagnostic| {
        try graph.addDiagnostic(diagnostic.kind, batch.unit, producer, diagnostic.message);
    }

    return outcome;
}

const testing = std.testing;

const test_producer: model.Producer = .{ .name = "frontend.test", .version = "slice-001" };

const test_capabilities: contract.Capabilities = .{
    .language = .java,
    .producer = test_producer,
    .entity_roles = &.{"method"},
    .relationship_kinds = &.{ .defines, .references, .calls },
    .coverage_note = "synthetic batches for reconciliation tests",
};

fn range(start: u32, end: u32) model.SourceRange {
    return .{
        .start_byte = start,
        .end_byte = end,
        .start_row = 0,
        .start_column = start,
        .end_row = 0,
        .end_column = end,
    };
}

/// A batch describing a unit that declares `names` as methods, where the first
/// name calls the second when both are present, and always calls `report`,
/// which is resolved only when a definition of that name is present.
fn syntheticBatch(
    builder: *contract.BatchBuilder,
    scope: []const u8,
    names: []const []const u8,
    body_marker: []const u8,
) !void {
    for (names, 0..) |name, index| {
        const start: u32 = @intCast(index * 100);
        _ = try builder.addEntity(.{
            .kind = .definition,
            .identity = .{
                .scope = scope,
                .language = .java,
                .role = "method",
                .name = try builder.dupe(name),
                .signature = try builder.print("{s}()", .{name}),
                .container_path = &.{},
            },
            .evidence = .{
                .unit = builder.unit,
                .range = range(start, start + 10),
                .text = try builder.print("{s} {s}", .{ name, body_marker }),
            },
            .extension = .{ .namespace = "java", .labels = &.{} },
            .resolution = .{ .fact = .{ .method = "declaration in source" } },
        });
        try builder.addRelationship(.{
            .kind = .defines,
            .source = .unit_container,
            .target = .{ .local = @intCast(index) },
            .evidence = .{
                .unit = builder.unit,
                .range = range(start, start + 10),
                .text = try builder.dupe(name),
            },
            .resolution = .{ .fact = .{ .method = "direct containment in the source unit" } },
        });
    }

    var report_index: ?u32 = null;
    for (names, 0..) |name, index| {
        if (std.mem.eql(u8, name, "report")) report_index = @intCast(index);
    }

    try builder.addRelationship(.{
        .kind = .calls,
        .source = .{ .entity = 0 },
        .target = if (report_index) |index|
            .{ .local = index }
        else
            .{ .designator = try builder.dupe("report") },
        .evidence = .{
            .unit = builder.unit,
            .range = range(500, 510),
            .text = try builder.dupe("report()"),
        },
        .resolution = if (report_index != null)
            .{ .fact = .{ .method = "same-container name match" } }
        else
            .{ .unresolved = .{
                .missing = .target_entity,
                .explanation = "no definition of this name in the analyzed unit",
            } },
    });
}

fn integrateNames(
    graph: *Graph,
    unit: model.SourceUnitId,
    names: []const []const u8,
    body_marker: []const u8,
) !Outcome {
    var builder = contract.BatchBuilder.init(graph.gpa, unit, test_capabilities);
    defer builder.deinit();
    try syntheticBatch(&builder, graph.unit(unit).?.path, names, body_marker);
    return integrate(graph, builder.batch());
}

test "a body-only edit preserves every entity id" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "v1");

    const first = try integrateNames(&graph, unit, &.{ "greet", "greeting" }, "v1");
    try testing.expectEqual(@as(usize, 2), first.created);

    var before = try graph.publish();
    defer before.deinit();
    const greet_before = before.findDefinition("a/A.java", "greet").?;
    const greeting_before = before.findDefinition("a/A.java", "greeting").?;

    try graph.setSourceUnitBytes(unit, "v2");
    const second = try integrateNames(&graph, unit, &.{ "greet", "greeting" }, "v2");
    try testing.expectEqual(@as(usize, 2), second.preserved);
    try testing.expectEqual(@as(usize, 0), second.created);
    try testing.expectEqual(@as(usize, 0), second.removed);
    try testing.expectEqual(@as(usize, 0), second.lost);

    var after = try graph.publish();
    defer after.deinit();
    try testing.expectEqual(greet_before.id, after.findDefinition("a/A.java", "greet").?.id);
    try testing.expectEqual(greeting_before.id, after.findDefinition("a/A.java", "greeting").?.id);

    const event = after.identityEventFor(greet_before.id, second.revision).?;
    try testing.expectEqual(model.IdentityEventKind.preserved, event.kind);
}

test "an added definition leaves the other entities alone" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "v1");
    _ = try integrateNames(&graph, unit, &.{ "greet", "greeting" }, "v1");

    var before = try graph.publish();
    defer before.deinit();
    const greet_before = before.findDefinition("a/A.java", "greet").?;

    const outcome = try integrateNames(&graph, unit, &.{ "greet", "greeting", "farewell" }, "v1");
    try testing.expectEqual(@as(usize, 2), outcome.preserved);
    try testing.expectEqual(@as(usize, 1), outcome.created);
    try testing.expectEqual(@as(usize, 0), outcome.removed);
    try testing.expectEqual(@as(usize, 0), outcome.lost);

    var after = try graph.publish();
    defer after.deinit();
    try testing.expectEqual(greet_before.id, after.findDefinition("a/A.java", "greet").?.id);
    try testing.expectEqual(@as(usize, 3), after.countEntities(.definition));
}

test "a rename is observable as identity loss, not as an unrelated delete and create" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "v1");
    _ = try integrateNames(&graph, unit, &.{ "greet", "greeting" }, "v1");

    var before = try graph.publish();
    defer before.deinit();
    const greeting_before = before.findDefinition("a/A.java", "greeting").?;

    const outcome = try integrateNames(&graph, unit, &.{ "greet", "salutation" }, "v1");
    try testing.expectEqual(@as(usize, 1), outcome.preserved);
    try testing.expectEqual(@as(usize, 1), outcome.created);
    try testing.expectEqual(@as(usize, 1), outcome.lost);
    try testing.expectEqual(@as(usize, 0), outcome.removed);

    var after = try graph.publish();
    defer after.deinit();
    try testing.expect(after.entityById(greeting_before.id) == null);

    const event = after.identityEventFor(greeting_before.id, outcome.revision).?;
    try testing.expectEqual(model.IdentityEventKind.lost, event.kind);
    const replacement = event.replacement.?;
    try testing.expectEqual(replacement, after.findDefinition("a/A.java", "salutation").?.id);

    // The loss is also a recorded assertion, and it is not a fact.
    var found = false;
    for (after.assertions) |assertion| {
        switch (assertion.claim) {
            .identity_correspondence => |corr| {
                if (corr.previous != greeting_before.id) continue;
                found = true;
                try testing.expectEqual(model.ResolutionCategory.unresolved, assertion.resolution.category());
            },
            else => {},
        }
    }
    try testing.expect(found);
}

test "a removed definition is removed, not reported as lost" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "v1");
    _ = try integrateNames(&graph, unit, &.{ "greet", "greeting" }, "v1");

    var before = try graph.publish();
    defer before.deinit();
    const greeting_before = before.findDefinition("a/A.java", "greeting").?;

    const outcome = try integrateNames(&graph, unit, &.{"greet"}, "v1");
    try testing.expectEqual(@as(usize, 1), outcome.removed);
    try testing.expectEqual(@as(usize, 0), outcome.lost);

    var after = try graph.publish();
    defer after.deinit();
    const event = after.identityEventFor(greeting_before.id, outcome.revision).?;
    try testing.expectEqual(model.IdentityEventKind.removed, event.kind);
    try testing.expect(event.replacement == null);
}

test "a reference target moves between unresolved and resolved" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "v1");
    _ = try integrateNames(&graph, unit, &.{ "greet", "greeting" }, "v1");

    var before = try graph.publish();
    defer before.deinit();
    const greet = before.findDefinition("a/A.java", "greet").?;
    try testing.expectEqual(@as(usize, 1), before.countRelationships(.{
        .source = greet.id,
        .kind = .calls,
        .resolution = .unresolved,
        .designator = "report",
    }));

    _ = try integrateNames(&graph, unit, &.{ "greet", "greeting", "report" }, "v1");
    var resolved = try graph.publish();
    defer resolved.deinit();
    try testing.expectEqual(@as(usize, 0), resolved.countRelationships(.{
        .source = greet.id,
        .kind = .calls,
        .resolution = .unresolved,
    }));
    try testing.expectEqual(@as(usize, 1), resolved.countRelationships(.{
        .source = greet.id,
        .kind = .calls,
        .resolution = .fact,
        .target = resolved.findDefinition("a/A.java", "report").?.id,
    }));

    _ = try integrateNames(&graph, unit, &.{ "greet", "greeting" }, "v1");
    var again = try graph.publish();
    defer again.deinit();
    try testing.expectEqual(@as(usize, 1), again.countRelationships(.{
        .source = greet.id,
        .kind = .calls,
        .resolution = .unresolved,
        .designator = "report",
    }));
}

test "unavailable analysis leaves the previous state in place" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "v1");
    _ = try integrateNames(&graph, unit, &.{ "greet", "greeting" }, "v1");

    var before = try graph.publish();
    defer before.deinit();
    const greet_before = before.findDefinition("a/A.java", "greet").?;

    var builder = contract.BatchBuilder.init(testing.allocator, unit, test_capabilities);
    defer builder.deinit();
    try builder.addDiagnostic(.analysis_unavailable, "parser could not run for this unit");
    const outcome = try integrate(&graph, builder.batch());
    try testing.expect(!outcome.applied);

    var after = try graph.publish();
    defer after.deinit();
    try testing.expectEqual(@as(usize, 2), after.countEntities(.definition));
    try testing.expectEqual(greet_before.id, after.findDefinition("a/A.java", "greet").?.id);
    try testing.expectEqual(@as(usize, 1), after.countDiagnostics(.analysis_unavailable));
}

test "an edit to one unit does not disturb another unit" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const a = try graph.addSourceUnit("a/A.java", .java, "v1");
    const b = try graph.addSourceUnit("b/B.java", .java, "v1");
    _ = try integrateNames(&graph, a, &.{ "greet", "greeting" }, "v1");
    _ = try integrateNames(&graph, b, &.{"other"}, "v1");

    var before = try graph.publish();
    defer before.deinit();
    const other_before = before.findDefinition("b/B.java", "other").?;
    const other_assertions = before.countRelationships(.{ .source = other_before.id });

    const outcome = try integrateNames(&graph, a, &.{"greet"}, "v2");
    try testing.expectEqual(@as(usize, 1), outcome.preserved);
    try testing.expectEqual(@as(usize, 1), outcome.removed);

    var after = try graph.publish();
    defer after.deinit();
    const other_after = after.findDefinition("b/B.java", "other").?;
    try testing.expectEqual(other_before.id, other_after.id);
    try testing.expectEqual(other_before.evidence.?.range.start_byte, other_after.evidence.?.range.start_byte);
    try testing.expectEqual(other_assertions, after.countRelationships(.{ .source = other_before.id }));
}
