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

pub const Error = graph_mod.GraphError || error{
    /// Containment and definition introduction are claims about one unit's own
    /// organization; no unit introduces what another unit declares.
    ExternalStructuralTarget,
    /// An entity of the analyzed unit is a local target, not an external one.
    ExternalTargetInsideUnit,
    /// The batch relies on another unit without saying so, so a change there
    /// would never reach it.
    UndeclaredExternalProvider,
    ExternalTargetMustBeDefinition,
    /// The target was not introduced by the unit the batch named for it.
    ExternalTargetProviderMismatch,
    /// The target is not a current fact of its provider.
    ExternalTargetNotCurrent,
};

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
    // Checked before anything is touched, so a rejected batch leaves the unit
    // exactly as its previous analysis left it.
    if (!batch.hasBlockingDiagnostic()) try checkExternalTargets(graph, batch);
    const revision = graph.beginRevision();
    const producer = batch.capabilities.producer;

    // Diagnostics describe the latest analysis attempt for this unit, so the
    // previous attempt's are withdrawn whether this one succeeds or not.
    graph.dropDiagnosticsForUnit(batch.unit);

    if (batch.hasBlockingDiagnostic()) {
        for (batch.diagnostics) |diagnostic| {
            try graph.addDiagnostic(diagnostic.kind, batch.unit, producer, diagnostic.message);
        }
        // The unit's existing assertions are neither withdrawn nor refreshed.
        // Withdrawing them would assert an absence nothing observed; refreshing
        // them would claim they describe contents nobody read. `markAnalyzed`
        // is deliberately not called, so the unit reports itself stale and its
        // assertions stop answering current-state queries.
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

    var outcome: Outcome = .{ .revision = revision, .applied = true };

    // Pass 1: correspondence. A matched entity keeps its id.
    //
    // This is quadratic in the size of one unit, and deliberately not in the
    // size of the graph: only the definitions of the unit being reconciled are
    // ever compared.
    graph.unit_work += batch.entities.len * previous.items.len;
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
        // A new entity in the same slot is the replacement. Failing that, one
        // with the same name under other containers is: a renamed container
        // takes its members' containment with it.
        for ([_]*const fn (model.IdentityEvidence, model.IdentityEvidence) bool{
            model.IdentityEvidence.sameSlot,
            model.IdentityEvidence.sameNameElsewhere,
        }) |replaces| {
            for (batch.entities, 0..) |draft, index| {
                if (claimed_replacement[index]) continue;
                // Only an entity created in this revision can be a replacement;
                // a preserved one is already accounted for.
                const created_here = graph.entity(local_ids[index].?).?.created_revision == revision;
                if (!created_here) continue;
                if (!replaces(existing.identity, draft.identity)) continue;
                claimed_replacement[index] = true;
                replacement = local_ids[index].?;
                replacement_evidence = draft.evidence;
                break;
            }
            if (replacement != null) break;
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

    // Allocating an entity does not claim it exists; the frontend that saw it
    // does. Preserved entities need this as much as created ones, because the
    // previous revision's existence assertions were withdrawn with the rest of
    // the unit's analysis.
    for (batch.entities, 0..) |draft, index| {
        _ = try graph.addAssertion(
            .{ .entity_exists = local_ids[index].? },
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
            .external => |external| .{ .entity = external.entity },
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

    // What the previous run of this unit read is not evidence about what this
    // one read, so the old declarations go before the new ones arrive.
    graph.dependencies.clearDependent(batch.unit);
    for (batch.dependencies) |declared| {
        try graph.dependencies.declare(.{
            .dependent = batch.unit,
            .provider = declared.provider,
            .reason = try graph.pool.intern(declared.reason),
        });
    }

    try graph.markAnalyzed(batch.unit);
    return outcome;
}

/// A frontend never allocates identity, and an id it hands back for another
/// unit's entity is not taken on trust: it must still name a current fact of
/// the unit the batch says it came from, and the batch must depend on that unit.
fn checkExternalTargets(graph: *Graph, batch: contract.FrontendBatch) Error!void {
    for (batch.relationships) |draft| {
        const external = switch (draft.target) {
            .external => |external| external,
            .local, .designator => continue,
        };
        switch (draft.kind) {
            .contains, .defines => return error.ExternalStructuralTarget,
            .references, .calls => {},
        }
        if (external.provider == batch.unit) return error.ExternalTargetInsideUnit;
        if (!declaresProvider(batch.dependencies, external.provider)) {
            return error.UndeclaredExternalProvider;
        }

        const target = graph.entity(external.entity) orelse return error.UnknownEntity;
        if (!target.isLive()) return error.RemovedEntity;
        if (target.kind != .definition) return error.ExternalTargetMustBeDefinition;
        const observed = target.evidence orelse return error.ExternalTargetProviderMismatch;
        if (observed.unit != external.provider) return error.ExternalTargetProviderMismatch;
        if (graph.currentDefinitionFact(external.entity) == null) return error.ExternalTargetNotCurrent;
    }
}

fn declaresProvider(declared: []const contract.DraftDependency, provider: model.SourceUnitId) bool {
    for (declared) |dependency| {
        if (dependency.provider == provider) return true;
    }
    return false;
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
    names: []const []const u8,
    body_marker: []const u8,
) !void {
    for (names, 0..) |name, index| {
        const start: u32 = @intCast(index * 100);
        _ = try builder.addEntity(.{
            .kind = .definition,
            .identity = .{
                .scope = .{ .unit = builder.unit },
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
    try syntheticBatch(&builder, names, body_marker);
    return integrate(graph, builder.batch());
}

test "an unresolved designator outlives the batch that produced it" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "v1");

    {
        var builder = contract.BatchBuilder.init(graph.gpa, unit, test_capabilities);
        defer builder.deinit();
        try syntheticBatch(&builder, &.{"greet"}, "v1");
        _ = try integrate(&graph, builder.batch());

        // Every string the batch handed over lives in its arena, which is
        // released right after integration; overwrite them first so a borrowed
        // one is visible rather than left to whatever reuses the memory.
        for (builder.relationships.items) |relationship| {
            switch (relationship.target) {
                .designator => |name| @memset(@constCast(name), 'x'),
                .local, .external => {},
            }
        }
    }

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .calls,
        .designator = "report",
        .resolution = .unresolved,
    }));
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

    _ = try graph.setSourceUnitBytes(unit, "v2");
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
    try testing.expectEqual(@as(usize, 3), after.countEntities(.{ .kind = .definition }));
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

/// A batch declaring one member named `member` inside a container named
/// `container`, which the unit introduces.
fn integrateMember(graph: *Graph, unit: model.SourceUnitId, container: []const u8, member: []const u8) !Outcome {
    var builder = contract.BatchBuilder.init(graph.gpa, unit, test_capabilities);
    defer builder.deinit();
    const evidence: model.SourceEvidence = .{ .unit = unit, .range = range(0, 10), .text = "decl" };
    const outer = try builder.addEntity(.{
        .kind = .definition,
        .identity = .{
            .scope = .{ .unit = unit },
            .language = .java,
            .role = "class",
            .name = container,
            .signature = null,
            .container_path = &.{},
        },
        .evidence = evidence,
        .extension = .{ .namespace = "java", .labels = &.{} },
        .resolution = .{ .fact = .{ .method = "declaration in source" } },
    });
    const inner = try builder.addEntity(.{
        .kind = .definition,
        .identity = .{
            .scope = .{ .unit = unit },
            .language = .java,
            .role = "method",
            .name = member,
            .signature = null,
            .container_path = try builder.dupeSlice(&.{container}),
        },
        .evidence = evidence,
        .extension = .{ .namespace = "java", .labels = &.{} },
        .resolution = .{ .fact = .{ .method = "declaration in source" } },
    });
    try builder.addRelationship(.{
        .kind = .defines,
        .source = .unit_container,
        .target = .{ .local = outer },
        .evidence = evidence,
        .resolution = .{ .fact = .{ .method = "declared in the unit" } },
    });
    try builder.addRelationship(.{
        .kind = .defines,
        .source = .{ .entity = outer },
        .target = .{ .local = inner },
        .evidence = evidence,
        .resolution = .{ .fact = .{ .method = "declared in the container" } },
    });
    return integrate(graph, builder.batch());
}

test "a renamed container makes its members' identity loss observable too" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "v1");
    _ = try integrateMember(&graph, unit, "Greeter", "greet");

    var before = try graph.publish();
    defer before.deinit();
    const member_before = before.findEntity(.{ .kind = .definition, .role = "method", .name = "greet" }).?;

    const outcome = try integrateMember(&graph, unit, "Welcomer", "greet");
    try testing.expectEqual(@as(usize, 2), outcome.lost);
    try testing.expectEqual(@as(usize, 2), outcome.created);
    try testing.expectEqual(@as(usize, 0), outcome.removed);
    try testing.expectEqual(@as(usize, 0), outcome.preserved);

    var after = try graph.publish();
    defer after.deinit();
    const member_after = after.findEntity(.{ .kind = .definition, .role = "method", .name = "greet" }).?;
    try testing.expectEqualStrings("Welcomer", member_after.identity.container_path[0]);
    const event = after.identityEventFor(member_before.id, outcome.revision).?;
    try testing.expectEqual(model.IdentityEventKind.lost, event.kind);
    try testing.expectEqual(member_after.id, event.replacement.?);

    // A body-level rename of the member alone stays a same-slot loss, and an
    // unchanged container keeps its identity.
    const renamed = try integrateMember(&graph, unit, "Welcomer", "welcome");
    try testing.expectEqual(@as(usize, 1), renamed.preserved);
    try testing.expectEqual(@as(usize, 1), renamed.lost);
    try testing.expectEqual(@as(usize, 0), renamed.removed);
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

fn failAnalysis(graph: *Graph, unit: model.SourceUnitId) !Outcome {
    var builder = contract.BatchBuilder.init(graph.gpa, unit, test_capabilities);
    defer builder.deinit();
    try builder.addDiagnostic(.analysis_unavailable, "parser could not run for this unit");
    return integrate(graph, builder.batch());
}

test "failed analysis of unchanged contents leaves the unit current" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "v1");
    _ = try integrateNames(&graph, unit, &.{ "greet", "greeting" }, "v1");

    var before = try graph.publish();
    defer before.deinit();
    const greet_before = before.findDefinition("a/A.java", "greet").?;

    const outcome = try failAnalysis(&graph, unit);
    try testing.expect(!outcome.applied);

    var after = try graph.publish();
    defer after.deinit();

    // Nothing was withdrawn, and nothing went stale: the contents these
    // assertions describe are still the contents the unit has.
    try testing.expectEqual(graph_mod.UnitAnalysis.current, after.unitAnalysis(unit).?);
    try testing.expectEqual(@as(usize, 2), after.countEntities(.{ .kind = .definition }));
    try testing.expectEqual(greet_before.id, after.findDefinition("a/A.java", "greet").?.id);
    try testing.expectEqual(@as(usize, 1), after.countDiagnostics(.analysis_unavailable));
}

test "an edit whose analysis fails stops answering current-state queries" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "v1");
    _ = try integrateNames(&graph, unit, &.{ "greet", "greeting" }, "v1");

    var before = try graph.publish();
    defer before.deinit();
    const greet_before = before.findDefinition("a/A.java", "greet").?;
    const current_before = before.countRelationships(.{});
    try testing.expect(current_before > 0);

    _ = try graph.setSourceUnitBytes(unit, "v2 which nothing could parse");
    const outcome = try failAnalysis(&graph, unit);
    try testing.expect(!outcome.applied);

    var after = try graph.publish();
    defer after.deinit();

    // The unit says what happened to it.
    try testing.expectEqual(graph_mod.UnitAnalysis.stale, after.unitAnalysis(unit).?);
    try testing.expectEqual(@as(usize, 1), after.countUnits(.stale));
    try testing.expectEqual(@as(usize, 1), after.countDiagnostics(.analysis_unavailable));

    // Claims about contents the unit no longer has do not answer a query that
    // did not ask for them.
    try testing.expectEqual(@as(usize, 0), after.countEntities(.{ .kind = .definition }));
    try testing.expect(after.findDefinition("a/A.java", "greet") == null);
    try testing.expectEqual(@as(usize, 0), after.countRelationships(.{ .source = greet_before.id }));
    try testing.expectEqual(@as(usize, 0), after.countAssertions(.{
        .unit = unit,
        .producer = test_producer.name,
    }));

    // They are not withdrawn either, because nothing observed their absence.
    // Identity survives, so a later successful analysis can correspond to them.
    try testing.expectEqual(@as(usize, 2), after.countEntities(.{
        .kind = .definition,
        .freshness = .stale,
    }));
    try testing.expect(after.entityById(greet_before.id) != null);
    try testing.expect(after.countRelationships(.{
        .source = greet_before.id,
        .freshness = .stale,
    }) > 0);

    // What source ingestion establishes about the unit itself is current: it
    // read the new contents even though no frontend could analyze them.
    try testing.expectEqual(@as(usize, 2), after.countAssertions(.{
        .unit = unit,
        .producer = graph_mod.ingestion.name,
    }));
    const file = after.findEntity(.{ .kind = .file }).?;
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{
        .kind = .contains,
        .target = file.id,
    }));
}

test "a stale unit becomes current again, with identity preserved across the gap" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "v1");
    _ = try integrateNames(&graph, unit, &.{ "greet", "greeting" }, "v1");

    var before = try graph.publish();
    defer before.deinit();
    const greet_before = before.findDefinition("a/A.java", "greet").?;
    const greeting_before = before.findDefinition("a/A.java", "greeting").?;

    _ = try graph.setSourceUnitBytes(unit, "v2 which nothing could parse");
    _ = try failAnalysis(&graph, unit);

    _ = try graph.setSourceUnitBytes(unit, "v3");
    const repaired = try integrateNames(&graph, unit, &.{ "greet", "greeting" }, "v3");
    try testing.expect(repaired.applied);
    try testing.expectEqual(@as(usize, 2), repaired.preserved);
    try testing.expectEqual(@as(usize, 0), repaired.created);
    try testing.expectEqual(@as(usize, 0), repaired.lost);

    var after = try graph.publish();
    defer after.deinit();
    try testing.expectEqual(graph_mod.UnitAnalysis.current, after.unitAnalysis(unit).?);
    try testing.expectEqual(@as(usize, 0), after.countUnits(.stale));
    try testing.expectEqual(greet_before.id, after.findDefinition("a/A.java", "greet").?.id);
    try testing.expectEqual(greeting_before.id, after.findDefinition("a/A.java", "greeting").?.id);

    // The failed attempt's diagnostic is gone: diagnostics describe the latest
    // analysis, not every attempt ever made.
    try testing.expectEqual(@as(usize, 0), after.countDiagnostics(.analysis_unavailable));
}

test "one unit going stale does not make another unit stale" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const a = try graph.addSourceUnit("a/A.java", .java, "v1");
    const b = try graph.addSourceUnit("b/B.java", .java, "v1");
    _ = try integrateNames(&graph, a, &.{ "greet", "greeting" }, "v1");
    _ = try integrateNames(&graph, b, &.{"other"}, "v1");

    _ = try graph.setSourceUnitBytes(a, "v2 which nothing could parse");
    _ = try failAnalysis(&graph, a);

    var after = try graph.publish();
    defer after.deinit();
    try testing.expectEqual(graph_mod.UnitAnalysis.stale, after.unitAnalysis(a).?);
    try testing.expectEqual(graph_mod.UnitAnalysis.current, after.unitAnalysis(b).?);
    try testing.expectEqual(@as(usize, 1), after.countEntities(.{ .kind = .definition }));
    try testing.expect(after.findDefinition("b/B.java", "other") != null);
}

test "a frontend's declared dependency is recorded and reaches the dependent" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const provider = try graph.addSourceUnit("a/A.java", .java, "v1");
    const dependent = try graph.addSourceUnit("b/B.java", .java, "v1");

    _ = try integrateNames(&graph, provider, &.{"greet"}, "v1");

    {
        var builder = contract.BatchBuilder.init(testing.allocator, dependent, test_capabilities);
        defer builder.deinit();
        try syntheticBatch(&builder, &.{"other"}, "v1");
        try builder.addDependency(provider, "read a definition declared in another unit");
        _ = try integrate(&graph, builder.batch());
    }

    try testing.expectEqual(@as(usize, 1), graph.dependencies.count());

    // Changing the provider obliges the dependent to be re-read.
    const affected = try graph.dependencies.propagate(testing.allocator, &.{provider});
    defer testing.allocator.free(affected.affected);
    try testing.expectEqual(@as(usize, 1), affected.affected.len);
    try testing.expectEqual(dependent, affected.affected[0]);

    // Changing the dependent obliges the provider nothing.
    const other_way = try graph.dependencies.propagate(testing.allocator, &.{dependent});
    defer testing.allocator.free(other_way.affected);
    try testing.expectEqual(@as(usize, 0), other_way.affected.len);
}

test "reanalyzing a unit withdraws what its previous analysis depended on" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const provider = try graph.addSourceUnit("a/A.java", .java, "v1");
    const dependent = try graph.addSourceUnit("b/B.java", .java, "v1");
    _ = try integrateNames(&graph, provider, &.{"greet"}, "v1");

    {
        var builder = contract.BatchBuilder.init(testing.allocator, dependent, test_capabilities);
        defer builder.deinit();
        try syntheticBatch(&builder, &.{"other"}, "v1");
        try builder.addDependency(provider, "read a definition declared in another unit");
        _ = try integrate(&graph, builder.batch());
    }
    try testing.expectEqual(@as(usize, 1), graph.dependencies.count());

    // The next analysis of the dependent reads nothing outside itself, so the
    // previous run's declaration is not evidence about this one.
    _ = try graph.setSourceUnitBytes(dependent, "v2");
    _ = try integrateNames(&graph, dependent, &.{"other"}, "v2");
    try testing.expectEqual(@as(usize, 0), graph.dependencies.count());
}

test "a departing unit leaves no dependency pointing at it" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const provider = try graph.addSourceUnit("a/A.java", .java, "v1");
    const dependent = try graph.addSourceUnit("b/B.java", .java, "v1");
    _ = try integrateNames(&graph, provider, &.{"greet"}, "v1");

    var builder = contract.BatchBuilder.init(testing.allocator, dependent, test_capabilities);
    defer builder.deinit();
    try syntheticBatch(&builder, &.{"other"}, "v1");
    try builder.addDependency(provider, "read a definition declared in another unit");
    _ = try integrate(&graph, builder.batch());

    try graph.removeSourceUnit(provider);
    try testing.expectEqual(@as(usize, 0), graph.dependencies.count());
}

/// Integrates a dependent unit declaring `other`, whose first entity references
/// `target` as an external entity. `declare` names the provider the batch says
/// it relied on, or none.
fn integrateExternalReference(
    graph: *Graph,
    dependent: model.SourceUnitId,
    kind: model.RelationshipKind,
    target: contract.ExternalTarget,
    declare: ?model.SourceUnitId,
) !Outcome {
    var builder = contract.BatchBuilder.init(testing.allocator, dependent, test_capabilities);
    defer builder.deinit();
    try syntheticBatch(&builder, &.{"other"}, "v1");
    try builder.addRelationship(.{
        .kind = kind,
        .source = .{ .entity = 0 },
        .target = .{ .external = target },
        .evidence = .{ .unit = dependent, .range = range(600, 605), .text = try builder.dupe("greet") },
        .resolution = .{ .fact = .{ .method = "resolved by the analysis context" } },
    });
    if (declare) |provider| try builder.addDependency(provider, "read a definition declared in another unit");
    return integrate(graph, builder.batch());
}

test "a batch can target a definition another unit established" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const provider = try graph.addSourceUnit("a/A.java", .java, "v1");
    const dependent = try graph.addSourceUnit("b/B.java", .java, "v1");
    _ = try integrateNames(&graph, provider, &.{"greet"}, "v1");

    var before = try graph.publish();
    defer before.deinit();
    const greet = before.findDefinition("a/A.java", "greet").?;

    _ = try integrateExternalReference(&graph, dependent, .references, .{
        .entity = greet.id,
        .provider = provider,
    }, provider);

    var after = try graph.publish();
    defer after.deinit();
    const other = after.findDefinition("b/B.java", "other").?;
    const reference = after.firstRelationship(.{
        .kind = .references,
        .source = other.id,
        .target = greet.id,
    }).?;
    try testing.expectEqual(model.ResolutionCategory.fact, reference.resolution.category());
    try testing.expectEqualStrings(test_producer.name, reference.producer.name);
    // Recorded in the dependent unit, which is what withdraws it when that unit
    // is analyzed again.
    try testing.expectEqual(dependent, reference.evidence.?.unit);
    try testing.expectEqual(@as(usize, 1), graph.dependencies.count());
    // No entity was allocated for the target.
    try testing.expectEqual(before.countEntities(.{ .kind = .definition }) + 1, after.countEntities(.{ .kind = .definition }));
}

test "an external target is refused unless it is a current definition of its declared provider" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const provider = try graph.addSourceUnit("a/A.java", .java, "v1");
    const dependent = try graph.addSourceUnit("b/B.java", .java, "v1");
    const bystander = try graph.addSourceUnit("c/C.java", .java, "v1");
    _ = try integrateNames(&graph, provider, &.{"greet"}, "v1");
    _ = try integrateNames(&graph, bystander, &.{"elsewhere"}, "v1");
    _ = try integrateNames(&graph, dependent, &.{"other"}, "v1");

    var before = try graph.publish();
    defer before.deinit();
    const greet = before.findDefinition("a/A.java", "greet").?.id;
    const own = before.findDefinition("b/B.java", "other").?.id;
    const provider_file = before.unit(provider).?.entity;
    const valid: contract.ExternalTarget = .{ .entity = greet, .provider = provider };

    try testing.expectError(error.UndeclaredExternalProvider, integrateExternalReference(&graph, dependent, .references, valid, null));
    try testing.expectError(error.UndeclaredExternalProvider, integrateExternalReference(&graph, dependent, .references, valid, bystander));
    try testing.expectError(error.ExternalStructuralTarget, integrateExternalReference(&graph, dependent, .defines, valid, provider));
    try testing.expectError(error.ExternalTargetInsideUnit, integrateExternalReference(&graph, dependent, .references, .{
        .entity = own,
        .provider = dependent,
    }, dependent));
    try testing.expectError(error.UnknownEntity, integrateExternalReference(&graph, dependent, .references, .{
        .entity = @enumFromInt(999),
        .provider = provider,
    }, provider));
    try testing.expectError(error.ExternalTargetMustBeDefinition, integrateExternalReference(&graph, dependent, .references, .{
        .entity = provider_file,
        .provider = provider,
    }, provider));
    try testing.expectError(error.ExternalTargetProviderMismatch, integrateExternalReference(&graph, dependent, .references, .{
        .entity = greet,
        .provider = bystander,
    }, bystander));

    // Every refusal left the dependent exactly as its last analysis left it.
    var unchanged = try graph.publish();
    defer unchanged.deinit();
    try testing.expectEqual(own, unchanged.findDefinition("b/B.java", "other").?.id);
    try testing.expectEqual(graph_mod.UnitAnalysis.current, unchanged.unitAnalysis(dependent).?);
    try testing.expectEqual(@as(usize, 0), graph.dependencies.count());
    try testing.expectEqual(@as(usize, 0), unchanged.countRelationships(.{ .target = greet, .kind = .references }));

    // A provider whose contents changed without being analyzed again no longer
    // establishes anything another unit may rely on.
    _ = try graph.setSourceUnitBytes(provider, "v2");
    try testing.expectError(error.ExternalTargetNotCurrent, integrateExternalReference(&graph, dependent, .references, valid, provider));

    // Nor does a definition its provider has since withdrawn.
    _ = try integrateNames(&graph, provider, &.{"farewell"}, "v2");
    try testing.expectError(error.RemovedEntity, integrateExternalReference(&graph, dependent, .references, valid, provider));
}

test "only a stale claim may outlive the definition it reached into another unit for" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const provider = try graph.addSourceUnit("a/A.java", .java, "v1");
    const dependent = try graph.addSourceUnit("b/B.java", .java, "v1");
    _ = try integrateNames(&graph, provider, &.{"greet"}, "v1");

    var before = try graph.publish();
    defer before.deinit();
    const greet = before.findDefinition("a/A.java", "greet").?.id;
    _ = try integrateExternalReference(&graph, dependent, .references, .{
        .entity = greet,
        .provider = provider,
    }, provider);

    // The dependent's contents change and cannot be analyzed, so its claim goes
    // stale; then the provider withdraws the target.
    _ = try graph.setSourceUnitBytes(dependent, "v2 which nothing could parse");
    _ = try failAnalysis(&graph, dependent);
    _ = try integrateNames(&graph, provider, &.{"farewell"}, "v2");

    var after = try graph.publish();
    defer after.deinit();
    try testing.expect(after.entityById(greet) == null);
    try testing.expectEqual(@as(usize, 0), after.countRelationships(.{ .target = greet }));
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{
        .target = greet,
        .kind = .references,
        .freshness = .stale,
    }));
}

test "a current claim naming a withdrawn definition is refused at publication" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const provider = try graph.addSourceUnit("a/A.java", .java, "v1");
    const dependent = try graph.addSourceUnit("b/B.java", .java, "v1");
    _ = try integrateNames(&graph, provider, &.{"greet"}, "v1");

    var before = try graph.publish();
    defer before.deinit();
    _ = try integrateExternalReference(&graph, dependent, .references, .{
        .entity = before.findDefinition("a/A.java", "greet").?.id,
        .provider = provider,
    }, provider);

    // Nothing reanalyzed the dependent, so its claim is current and wrong. The
    // graph refuses to publish it rather than hand out a dangling fact.
    _ = try integrateNames(&graph, provider, &.{"farewell"}, "v2");
    try testing.expectError(error.DanglingAssertionEndpoint, graph.publish());
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
