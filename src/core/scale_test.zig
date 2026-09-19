//! A synthetic graph big enough for query cost to be visible, and the baseline
//! this plan's later stages are measured against.
//!
//! The graph this builds is deliberately not a realistic repository. It is a
//! shape with known answers: one focus entity whose neighbourhood is small and
//! exactly known, a depth-2 frontier that stays tiny however large the graph
//! grows, and everything else noise that no anchored query should ever have to
//! look at. That is what makes a cost claim falsifiable — the honest answer is
//! fixed, so any growth in examined records is the access path and nothing else.
//!
//! It is local, deterministic, and committed. No external repository is a
//! conformance target here.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const model = @import("model.zig");
const graph_mod = @import("graph.zig");

const Graph = graph_mod.Graph;
const Snapshot = graph_mod.Snapshot;
const EntityId = model.EntityId;
const SourceUnitId = model.SourceUnitId;

const testing = std.testing;

const producer: model.Producer = .{ .name = "frontend.synthetic", .version = "plan-011" };

/// How many entities the focus entity calls directly.
pub const fan_out = 4;
/// How many entities reference the focus entity.
pub const fan_in = 4;
/// How many entities each of the focus entity's callees calls in turn.
pub const fan_out_depth2 = 3;

/// Units reserved for the known shape. Everything at or above this index is a
/// plain unit that may be edited or removed without disturbing the answers the
/// measurements assert.
const structural_units = 1 + fan_out + fan_out * fan_out_depth2;

/// A designator recorded by several units, so a designator-anchored query has
/// more than one answer and cannot pass by accident.
pub const shared_designator = "synthetic.Shared";

pub const Spec = struct {
    units: u32 = 256,
    /// Definitions introduced per unit. Index 0 and index 1 carry the known
    /// shape; noise uses the rest, so noise can never reach the focus
    /// neighbourhood.
    definitions_per_unit: u32 = 10,
    /// Relationships per unit that touch neither the focus entity nor its
    /// neighbourhood. Capped by the definitions a unit has left for noise.
    noise_per_unit: u32 = 8,
    /// Every nth plain unit records relationships its frontend could not
    /// resolve to an entity.
    designator_every: u32 = 8,
    /// Every nth plain unit is edited after analysis, so its assertions are
    /// stale rather than absent.
    stale_every: u32 = 16,
    /// Every nth plain unit leaves the index after analysis, so snapshot
    /// positions and ids diverge.
    removed_every: u32 = 32,
};

/// A built synthetic graph and the entities whose neighbourhoods are known.
pub const Synthetic = struct {
    graph: Graph,
    spec: Spec,
    /// The anchor. Its answers are fixed by construction at every size.
    focus: EntityId,
    /// What `focus` calls.
    outgoing: [fan_out]EntityId,
    /// What references `focus`.
    incoming: [fan_in]EntityId,
    /// What `outgoing` calls, the depth-2 frontier.
    depth2: [fan_out * fan_out_depth2]EntityId,

    pub fn deinit(self: *Synthetic) void {
        self.graph.deinit();
    }

    pub fn publish(self: *Synthetic) !Snapshot {
        return self.graph.publish();
    }

    /// Entity targets reachable from `focus` within two steps, counted with
    /// repetition. Fixed by construction, so a traversal that returns anything
    /// else has changed an answer rather than an access path.
    pub fn depth2Reach(_: Synthetic) usize {
        return fan_out + fan_out * fan_out_depth2;
    }
};

fn isStructural(index: u32) bool {
    return index < structural_units;
}

fn isIncoming(spec: Spec, index: u32) bool {
    return index >= spec.units - fan_in;
}

/// A unit carrying no part of the known shape, and therefore free to be edited
/// or removed.
fn isPlain(spec: Spec, index: u32) bool {
    return !isStructural(index) and !isIncoming(spec, index);
}

fn noiseSpan(spec: Spec) u32 {
    return spec.definitions_per_unit - 2;
}

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

fn addDefinition(
    graph: *Graph,
    unit: SourceUnitId,
    name: []const u8,
    at: model.SourceRange,
) !EntityId {
    const evidence: model.SourceEvidence = .{ .unit = unit, .range = at, .text = name };
    const id = try graph.addEntity(.{
        .kind = .definition,
        .identity = .{
            .scope = .{ .unit = unit },
            .language = .java,
            .role = "method",
            .name = name,
            .signature = name,
            .container_path = &.{},
        },
        .evidence = evidence,
        .extension = .{ .namespace = "java", .labels = &.{} },
    });
    _ = try graph.addAssertion(
        .{ .entity_exists = id },
        producer,
        evidence,
        .{ .fact = .{ .method = "declaration in synthetic source" } },
    );
    return id;
}

fn addCall(
    graph: *Graph,
    unit: SourceUnitId,
    source: EntityId,
    target: EntityId,
    text: []const u8,
) !void {
    _ = try graph.addRelationship(
        .{ .kind = .calls, .source = source, .target = .{ .entity = target } },
        producer,
        .{ .unit = unit, .range = range(0, 1), .text = text },
        .{ .fact = .{ .method = "resolved in synthetic source" } },
    );
}

pub fn build(gpa: Allocator, spec: Spec) !Synthetic {
    std.debug.assert(spec.units >= structural_units + fan_in + 1);
    std.debug.assert(spec.definitions_per_unit >= 4);

    var graph = try Graph.init(gpa, "synthetic");
    errdefer graph.deinit();

    const per_unit = spec.definitions_per_unit;
    const units = try gpa.alloc(SourceUnitId, spec.units);
    defer gpa.free(units);
    const definitions = try gpa.alloc(EntityId, spec.units * per_unit);
    defer gpa.free(definitions);

    for (0..spec.units) |index| {
        var path_buffer: [64]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buffer, "synthetic/u{d:0>6}.java", .{index});
        var body_buffer: [64]u8 = undefined;
        const body = try std.fmt.bufPrint(&body_buffer, "// synthetic unit {d}\n", .{index});

        const unit = try graph.addSourceUnit(path, .java, body);
        units[index] = unit;
        for (0..per_unit) |slot| {
            var name_buffer: [64]u8 = undefined;
            const name = try std.fmt.bufPrint(&name_buffer, "d{d}_{d}", .{ index, slot });
            const start: u32 = @intCast(slot * 8);
            definitions[index * per_unit + slot] =
                try addDefinition(&graph, unit, name, range(start, start + 4));
        }
        try graph.markAnalyzed(unit);
    }

    const focus = definitions[0];

    var outgoing: [fan_out]EntityId = undefined;
    for (&outgoing, 0..) |*slot, step| {
        slot.* = definitions[(1 + step) * per_unit];
        try addCall(&graph, units[0], focus, slot.*, "call from focus");
    }

    var depth2: [fan_out * fan_out_depth2]EntityId = undefined;
    for (outgoing, 0..) |callee, step| {
        for (0..fan_out_depth2) |leaf| {
            const slot = step * fan_out_depth2 + leaf;
            const unit_index = 1 + fan_out + slot;
            depth2[slot] = definitions[unit_index * per_unit];
            try addCall(&graph, units[1 + step], callee, depth2[slot], "call from callee");
        }
    }

    var incoming: [fan_in]EntityId = undefined;
    for (&incoming, 0..) |*slot, step| {
        const unit_index = spec.units - 1 - @as(u32, @intCast(step));
        slot.* = definitions[unit_index * per_unit + 1];
        _ = try graph.addRelationship(
            .{ .kind = .references, .source = slot.*, .target = .{ .entity = focus } },
            producer,
            .{ .unit = units[unit_index], .range = range(0, 1), .text = "reference to focus" },
            .{ .fact = .{ .method = "resolved in synthetic source" } },
        );
    }

    // Noise. It never touches definition slots 0 and 1, which is what keeps the
    // focus neighbourhood exactly the size the measurements assert.
    const span = noiseSpan(spec);
    const noise = @min(spec.noise_per_unit, span);
    for (0..spec.units) |index| {
        for (0..noise) |step| {
            const from = definitions[index * per_unit + 2 + step];
            const to = definitions[index * per_unit + 2 + (step + 1) % span];
            if (from == to) continue;
            try addCall(&graph, units[index], from, to, "noise call");
        }
    }

    // Names no frontend could resolve. They stay designators, so an anchored
    // designator query has something to find and an entity-anchored one must
    // still skip them.
    for (0..spec.units) |index| {
        const unit_index: u32 = @intCast(index);
        if (!isPlain(spec, unit_index)) continue;
        if (unit_index % spec.designator_every != 0) continue;
        var unique_buffer: [64]u8 = undefined;
        const unique = try std.fmt.bufPrint(&unique_buffer, "synthetic.U{d}", .{index});
        for ([_][]const u8{ shared_designator, unique }) |designator| {
            _ = try graph.addRelationship(
                .{
                    .kind = .references,
                    .source = definitions[index * per_unit],
                    .target = .{ .designator = designator },
                },
                producer,
                .{ .unit = units[index], .range = range(0, 1), .text = designator },
                .{ .unresolved = .{
                    .missing = .target_entity,
                    .explanation = "no synthetic unit declares this name",
                } },
            );
        }
    }

    // Edits and removals last, so the graph a snapshot publishes holds stale
    // claims beside current ones and hands out entity ids that no longer match
    // their position in the published slice.
    for (0..spec.units) |index| {
        const unit_index: u32 = @intCast(index);
        if (!isPlain(spec, unit_index)) continue;
        if (unit_index % spec.removed_every == 0) {
            try graph.removeSourceUnit(units[index]);
        } else if (unit_index % spec.stale_every == 0) {
            _ = try graph.setSourceUnitBytes(units[index], "// edited after analysis\n");
        }
    }

    return .{
        .graph = graph,
        .spec = spec,
        .focus = focus,
        .outgoing = outgoing,
        .incoming = incoming,
        .depth2 = depth2,
    };
}

// -- measurement ------------------------------------------------------------

pub const Measurement = struct {
    /// Answers the query returned. Recorded beside the cost so a cheaper
    /// measurement that answered less is never mistaken for an improvement.
    answers: usize,
    identity_records: usize,
    candidates: usize,
};

/// No wall clock is taken here, and that is the design rather than a
/// limitation. D9 makes the deterministic work count the claim and leaves
/// timing an observation, and Zig 0.16 has no clock reachable from a
/// parser-free core test without building an `Io` this lane has no other use
/// for. Latency observations belong where a user actually feels them, at the
/// MCP hot path, and are recorded in the progress log.
fn measure(comptime run: anytype, args: anytype) !Measurement {
    graph_mod.work.reset();
    const answers = try @call(.auto, run, args);
    return .{
        .answers = answers,
        .identity_records = graph_mod.work.identity_records,
        .candidates = graph_mod.work.candidates,
    };
}

fn countCurrentAssertions(snapshot: *const Snapshot) !usize {
    return snapshot.countAssertions(.{});
}

fn countAnchoredOutgoing(snapshot: *const Snapshot, focus: EntityId) !usize {
    return snapshot.countRelationships(.{ .source = focus });
}

fn countAnchoredIncoming(snapshot: *const Snapshot, focus: EntityId) !usize {
    return snapshot.countRelationships(.{ .target = focus });
}

/// The depth-2 shape `semidx_context` walks: expand the frontier one anchored
/// query per entity, following entity targets only.
fn traverseDepth2(snapshot: *const Snapshot, focus: EntityId, gpa: Allocator) !usize {
    var frontier: std.ArrayList(EntityId) = .empty;
    defer frontier.deinit(gpa);
    var next: std.ArrayList(EntityId) = .empty;
    defer next.deinit(gpa);

    try frontier.append(gpa, focus);
    var reached: usize = 0;
    for (0..2) |_| {
        next.clearRetainingCapacity();
        for (frontier.items) |entity| {
            var iterator = snapshot.relationships(.{ .source = entity });
            while (iterator.next()) |assertion| {
                const relationship = assertion.relationship() orelse continue;
                switch (relationship.target) {
                    .entity => |id| {
                        reached += 1;
                        try next.append(gpa, id);
                    },
                    .designator => {},
                }
            }
        }
        std.mem.swap(std.ArrayList(EntityId), &frontier, &next);
    }
    return reached;
}

/// Whether the measurement test prints its table.
///
/// Off in the committed lane, because a lane that prints on every run makes
/// every other failure harder to read. The assertions are the gate; the numbers
/// a progress log records are asked for deliberately, by flipping this and
/// re-running `zig build test-core`. That is written down in the plan's
/// progress log so the next agent does not have to rediscover it.
const print_measurements = false;

fn report(label: []const u8, measurement: Measurement) void {
    if (!print_measurements) return;
    std.debug.print("| {s} | {d} | {d} | {d} |\n", .{
        label,
        measurement.answers,
        measurement.identity_records,
        measurement.candidates,
    });
}

fn reportHeader(spec: Spec, snapshot: *const Snapshot) void {
    if (!print_measurements) return;
    std.debug.print(
        "\nsynthetic graph: {d} units requested, {d} live, {d} entities, {d} assertions\n" ++
            "| query | answers | identity records | candidates |\n" ++
            "| --- | --- | --- | --- |\n",
        .{ spec.units, snapshot.units.len, snapshot.entities.len, snapshot.assertions.len },
    );
}

test "the synthetic graph has the shape its measurements assume" {
    var synthetic = try build(testing.allocator, .{});
    defer synthetic.deinit();
    var snapshot = try synthetic.publish();
    defer snapshot.deinit();

    // Removals happened, so an entity's id is no longer its position in the
    // published slice. Every identity-lookup claim in this plan depends on this
    // gap being exercised rather than assumed.
    try testing.expect(snapshot.units.len < synthetic.spec.units);
    var identity_gap = false;
    for (snapshot.entities, 0..) |entity, position| {
        if (entity.id.index() != position) identity_gap = true;
    }
    try testing.expect(identity_gap);

    // Stale claims sit beside current ones, so a freshness filter has something
    // to exclude.
    const current = snapshot.countAssertions(.{ .freshness = .current });
    const stale = snapshot.countAssertions(.{ .freshness = .stale });
    try testing.expect(current > 0);
    try testing.expect(stale > 0);

    // Unresolved designators sit beside facts.
    try testing.expect(snapshot.countRelationships(.{ .resolution = .unresolved }) > 0);
    try testing.expect(snapshot.countRelationships(.{ .designator = shared_designator }) > 1);

    // The focus neighbourhood is exactly what the builder put there.
    try testing.expectEqual(
        @as(usize, fan_out),
        snapshot.countRelationships(.{ .source = synthetic.focus }),
    );
    try testing.expectEqual(
        @as(usize, fan_in),
        snapshot.countRelationships(.{ .target = synthetic.focus }),
    );
    try testing.expectEqual(
        synthetic.depth2Reach(),
        try traverseDepth2(&snapshot, synthetic.focus, testing.allocator),
    );

    // The neighbourhood stays small relative to the graph, which is the only
    // reason a cost claim about it means anything.
    try testing.expect(snapshot.assertions.len > 50 * synthetic.depth2Reach());
}

/// What `Snapshot.unit` did before it had a table: walk the published slice.
fn referenceUnit(snapshot: *const Snapshot, id: SourceUnitId) ?graph_mod.SourceUnitView {
    for (snapshot.units) |view| {
        if (view.id == id) return view;
    }
    return null;
}

/// What `Snapshot.entityById` did before it had a table.
fn referenceEntity(snapshot: *const Snapshot, id: EntityId) ?model.Entity {
    for (snapshot.entities) |item| {
        if (item.id == id) return item;
    }
    return null;
}

test "indexed identity lookups answer exactly what a scan answered" {
    var synthetic = try build(testing.allocator, .{});
    defer synthetic.deinit();
    var snapshot = try synthetic.publish();
    defer snapshot.deinit();

    // The graph has removed units and removed entities, so ids and published
    // positions have diverged. Without that this proves nothing.
    try testing.expect(snapshot.units.len < synthetic.spec.units);

    // Every id the graph ever issued is asked for, plus a margin past the
    // highest one: an id above the table is absent, and must be answered as
    // absent rather than searched for.
    const unit_ids = synthetic.spec.units + 8;
    for (0..unit_ids) |index| {
        const id: SourceUnitId = @enumFromInt(@as(u32, @intCast(index)));
        const expected = referenceUnit(&snapshot, id);
        const actual = snapshot.unit(id);
        if (expected) |view| {
            try testing.expect(actual != null);
            try testing.expect(std.meta.eql(view, actual.?));
            try testing.expectEqual(view.analysis(), snapshot.unitAnalysis(id).?);
        } else {
            try testing.expect(actual == null);
            try testing.expect(snapshot.unitAnalysis(id) == null);
        }
    }

    var highest_entity: u32 = 0;
    for (snapshot.entities) |item| highest_entity = @max(highest_entity, @intFromEnum(item.id));
    for (0..highest_entity + 8) |index| {
        const id: EntityId = @enumFromInt(@as(u32, @intCast(index)));
        const expected = referenceEntity(&snapshot, id);
        const actual = snapshot.entityById(id);
        if (expected) |item| {
            try testing.expect(actual != null);
            try testing.expect(std.meta.eql(item, actual.?));
        } else {
            try testing.expect(actual == null);
        }
    }

    // A removed entity is absent, not a neighbour of the position its id once
    // named. This is the failure a position table makes possible and the reason
    // parity is asserted over the whole id range rather than over live ids.
    var removed_seen = false;
    for (0..highest_entity) |index| {
        const id: EntityId = @enumFromInt(@as(u32, @intCast(index)));
        if (snapshot.entityById(id) == null) removed_seen = true;
    }
    try testing.expect(removed_seen);
}

test "identity lookup cost does not grow with the graph" {
    for ([_]u32{ 64, 256 }) |units| {
        var synthetic = try build(testing.allocator, .{ .units = units });
        defer synthetic.deinit();
        var snapshot = try synthetic.publish();
        defer snapshot.deinit();

        // One lookup examines one record, at either size. Before the position
        // table this was half the live units on average, and it was paid once
        // per assertion visited.
        graph_mod.work.reset();
        _ = snapshot.unit(@enumFromInt(0));
        try testing.expectEqual(@as(usize, 1), graph_mod.work.identity_records);

        graph_mod.work.reset();
        _ = snapshot.entityById(synthetic.focus);
        try testing.expectEqual(@as(usize, 1), graph_mod.work.identity_records);

        // An id the snapshot does not hold costs the same. A fallback scan here
        // would be the defect this stage removes, wearing a different name.
        graph_mod.work.reset();
        _ = snapshot.unit(@enumFromInt(units + 1000));
        try testing.expectEqual(@as(usize, 1), graph_mod.work.identity_records);

        // A freshness-filtered walk therefore costs one lookup per assertion,
        // not one scan per assertion.
        const counting = try measure(countCurrentAssertions, .{&snapshot});
        try testing.expect(counting.identity_records <= snapshot.assertions.len);
    }
}

// -- adjacency parity -------------------------------------------------------

/// What `Snapshot.relationships` did before it had an index: walk every
/// assertion and apply every filter inline.
///
/// This is the oracle, so it is written out in full rather than sharing code
/// with the implementation. A parity test that shares the logic it is checking
/// proves only that the logic equals itself.
fn oracle(
    snapshot: *const Snapshot,
    filter: Snapshot.RelationshipFilter,
    out: *std.ArrayList(model.AssertionId),
    gpa: Allocator,
) !void {
    out.clearRetainingCapacity();
    for (snapshot.assertions) |assertion| {
        if (filter.freshness) |freshness| {
            if (snapshot.assertionFreshness(assertion) != freshness) continue;
        }
        const relationship = assertion.relationship() orelse continue;
        if (filter.reference_query) {
            if (!relationship.kind.satisfiesReferenceQuery()) continue;
        } else if (filter.kind) |kind| {
            if (relationship.kind != kind) continue;
        }
        if (filter.source) |source| {
            if (relationship.source != source) continue;
        }
        if (filter.target) |target| {
            switch (relationship.target) {
                .entity => |id| if (id != target) continue,
                .designator => continue,
            }
        }
        if (filter.designator) |designator| {
            switch (relationship.target) {
                .designator => |value| if (!std.mem.eql(u8, value, designator)) continue,
                .entity => continue,
            }
        }
        if (filter.resolution) |category| {
            if (assertion.resolution.category() != category) continue;
        }
        try out.append(gpa, assertion.id);
    }
}

fn indexed(
    snapshot: *const Snapshot,
    filter: Snapshot.RelationshipFilter,
    out: *std.ArrayList(model.AssertionId),
    gpa: Allocator,
) !void {
    out.clearRetainingCapacity();
    var iterator = snapshot.relationships(filter);
    while (iterator.next()) |assertion| try out.append(gpa, assertion.id);
}

/// The filter combinations the parity test runs. An anchor, crossed with every
/// post-filter, because the anchor decides what is looked at and the
/// post-filters decide what survives — a break in either direction has to show
/// up as a different list.
fn expectParityOverFilters(snapshot: *const Snapshot, anchors: []const Snapshot.RelationshipFilter) !void {
    const gpa = testing.allocator;
    var expected: std.ArrayList(model.AssertionId) = .empty;
    defer expected.deinit(gpa);
    var actual: std.ArrayList(model.AssertionId) = .empty;
    defer actual.deinit(gpa);

    const kinds = [_]?model.RelationshipKind{ null, .contains, .defines, .references, .calls };
    const resolutions = [_]?model.ResolutionCategory{ null, .fact, .unresolved, .approximate };
    const freshnesses = [_]?model.Freshness{ .current, .stale, null };

    for (anchors) |anchor| {
        for (kinds) |kind| {
            for ([_]bool{ false, true }) |reference_query| {
                for (resolutions) |resolution| {
                    for (freshnesses) |freshness| {
                        var filter = anchor;
                        filter.kind = kind;
                        filter.reference_query = reference_query;
                        filter.resolution = resolution;
                        filter.freshness = freshness;

                        try oracle(snapshot, filter, &expected, gpa);
                        try indexed(snapshot, filter, &actual, gpa);
                        // Ids and order, not just counts: a consumer reads this
                        // list in the order it arrives.
                        try testing.expectEqualSlices(
                            model.AssertionId,
                            expected.items,
                            actual.items,
                        );
                    }
                }
            }
        }
    }
}

/// An entity id the snapshot no longer holds, and one past every id it ever
/// issued.
fn absentIds(snapshot: *const Snapshot) struct { removed: EntityId, beyond: EntityId } {
    var highest: u32 = 0;
    for (snapshot.entities) |item| highest = @max(highest, @intFromEnum(item.id));
    var removed: EntityId = @enumFromInt(0);
    for (0..highest) |index| {
        const id: EntityId = @enumFromInt(@as(u32, @intCast(index)));
        if (snapshot.entityById(id) == null) removed = id;
    }
    return .{ .removed = removed, .beyond = @enumFromInt(highest + 100) };
}

test "indexed relationship queries answer exactly what a full scan answered" {
    var synthetic = try build(testing.allocator, .{ .units = 64 });
    defer synthetic.deinit();
    var snapshot = try synthetic.publish();
    defer snapshot.deinit();

    const absent = absentIds(&snapshot);
    const anchors = [_]Snapshot.RelationshipFilter{
        // No anchor: the whole array is the candidate list, as before.
        .{},
        // Entity anchors, each direction, including entities that have
        // relationships in one direction only.
        .{ .source = synthetic.focus },
        .{ .target = synthetic.focus },
        .{ .source = synthetic.outgoing[0] },
        .{ .target = synthetic.depth2[0] },
        .{ .source = synthetic.depth2[0] },
        .{ .target = synthetic.incoming[0] },
        // Both anchors, so the shorter candidate list is chosen and the other
        // anchor still has to be applied.
        .{ .source = synthetic.focus, .target = synthetic.outgoing[0] },
        .{ .source = synthetic.focus, .target = synthetic.depth2[0] },
        // Ids the snapshot does not hold: one removed, one never issued.
        .{ .source = absent.removed },
        .{ .target = absent.removed },
        .{ .source = absent.beyond },
        .{ .target = absent.beyond },
        // Designators, including one several units share, one recorded by a
        // unit whose contents changed afterwards, one whose unit left the
        // index, and one nothing ever recorded.
        .{ .designator = shared_designator },
        .{ .designator = "synthetic.U24" },
        .{ .designator = "synthetic.U48" },
        .{ .designator = "synthetic.U32" },
        .{ .designator = "synthetic.NeverRecorded" },
        // A target is an entity or a designator and never both, so these must
        // stay empty whichever anchor is chosen.
        .{ .source = synthetic.focus, .designator = shared_designator },
        .{ .target = synthetic.focus, .designator = shared_designator },
    };

    try expectParityOverFilters(&snapshot, &anchors);
}

test "an anchor the index does not hold returns empty without a scan" {
    var synthetic = try build(testing.allocator, .{ .units = 64 });
    defer synthetic.deinit();
    var snapshot = try synthetic.publish();
    defer snapshot.deinit();

    const absent = absentIds(&snapshot);
    const anchors = [_]Snapshot.RelationshipFilter{
        .{ .source = absent.beyond },
        .{ .target = absent.beyond },
        .{ .designator = "synthetic.NeverRecorded" },
        // An entity that exists and simply has nothing pointing out of it.
        .{ .source = synthetic.depth2[0] },
    };

    for (anchors) |filter| {
        graph_mod.work.reset();
        var iterator = snapshot.relationships(filter);
        try testing.expect(iterator.next() == null);
        // Not "few". None: the index already said this key holds nothing, and
        // looking anyway would be the linear path under another name.
        try testing.expectEqual(@as(usize, 0), graph_mod.work.candidates);
    }
}

test "a snapshot published after an edit is indexed against its own assertions" {
    var synthetic = try build(testing.allocator, .{ .units = 64 });
    defer synthetic.deinit();

    var before = try synthetic.publish();
    defer before.deinit();
    const before_outgoing = before.countRelationships(.{ .source = synthetic.focus });
    const before_assertions = before.assertions.len;

    // An edit that adds a relationship the earlier snapshot never saw, in a
    // unit that already carries part of the known shape.
    const unit = before.unitByPath("synthetic/u000001.java").?.id;
    const revision = try synthetic.graph.setSourceUnitBytes(unit, "// edited, then analyzed\n");
    try testing.expect(revision > before.revision);
    try addCall(
        &synthetic.graph,
        unit,
        synthetic.outgoing[0],
        synthetic.focus,
        "call added by the edit",
    );
    try synthetic.graph.markAnalyzed(unit);

    var after = try synthetic.publish();
    defer after.deinit();

    // The earlier snapshot is untouched by a later publication, index included.
    try testing.expectEqual(before_assertions, before.assertions.len);
    try testing.expectEqual(before_outgoing, before.countRelationships(.{ .source = synthetic.focus }));

    // The new snapshot's index describes the new snapshot, not a mix of the
    // two: the added relationship is reachable from both its anchors, and every
    // filter still agrees with a full scan of the assertions this snapshot
    // actually holds.
    try testing.expectEqual(
        @as(usize, fan_in + 1),
        after.countRelationships(.{ .target = synthetic.focus }),
    );
    const anchors = [_]Snapshot.RelationshipFilter{
        .{},
        .{ .source = synthetic.focus },
        .{ .target = synthetic.focus },
        .{ .source = synthetic.outgoing[0] },
        .{ .designator = shared_designator },
    };
    try expectParityOverFilters(&after, &anchors);
    try expectParityOverFilters(&before, &anchors);
}

// -- scale proof ------------------------------------------------------------

/// What the indexes should cost, computed from what the snapshot actually
/// holds.
///
/// This is deliberately not a share of resident memory. At any percentage worth
/// setting, a budget that size could never fail — it would still admit an
/// implementation allocating a list header per entity, which is exactly the
/// shape compressed sparse row exists to prevent. A budget that cannot fail is
/// decoration.
fn expectedIndexBytes(snapshot: *const Snapshot) usize {
    var keys: usize = snapshot.entity_positions.len;
    var relationships: usize = 0;
    var entity_targets: usize = 0;
    var designator_targets: usize = 0;
    var designators: std.StringHashMapUnmanaged(void) = .empty;
    defer designators.deinit(testing.allocator);

    for (snapshot.assertions) |assertion| {
        const relationship = assertion.relationship() orelse continue;
        relationships += 1;
        keys = @max(keys, @as(usize, @intFromEnum(relationship.source)) + 1);
        switch (relationship.target) {
            .entity => |id| {
                entity_targets += 1;
                keys = @max(keys, @as(usize, @intFromEnum(id)) + 1);
            },
            .designator => |value| {
                designator_targets += 1;
                designators.put(testing.allocator, value, {}) catch unreachable;
            },
        }
    }

    const u32_size = @sizeOf(u32);
    // Position tables.
    var bytes = (snapshot.entity_positions.len + snapshot.unit_positions.len) * u32_size;
    // Outgoing and incoming, each an offset per key plus one, and a position
    // per relationship it indexes.
    bytes += (keys + 1) * u32_size + relationships * u32_size;
    bytes += (keys + 1) * u32_size + entity_targets * u32_size;
    // The designator map: one entry per distinct designator, one position per
    // designator relationship.
    bytes += designators.count() * (@sizeOf([]const u8) + @sizeOf(u32) * 2 + 1);
    bytes += designator_targets * u32_size;
    return bytes;
}

fn measuredIndexBytes(snapshot: *const Snapshot) usize {
    const tables = (snapshot.entity_positions.len + snapshot.unit_positions.len) * @sizeOf(u32);
    return tables + snapshot.relationship_index.byteSize();
}

/// The work bound, asserted at one size.
///
/// Every number here is exact rather than a ceiling, because the synthetic
/// graph's answers are exact. "Proportional to the neighbourhood" is not a
/// direction of travel to be satisfied by getting smaller; it is `answers`.
fn expectWorkFollowsTheNeighbourhood(synthetic: *const Synthetic, snapshot: *const Snapshot) !void {
    const outgoing = try measure(countAnchoredOutgoing, .{ snapshot, synthetic.focus });
    try testing.expectEqual(@as(usize, fan_out), outgoing.answers);
    try testing.expectEqual(outgoing.answers, outgoing.candidates);

    const incoming = try measure(countAnchoredIncoming, .{ snapshot, synthetic.focus });
    try testing.expectEqual(@as(usize, fan_in), incoming.answers);
    try testing.expectEqual(incoming.answers, incoming.candidates);

    const traversal = try measure(traverseDepth2, .{ snapshot, synthetic.focus, testing.allocator });
    try testing.expectEqual(synthetic.depth2Reach(), traversal.answers);
    try testing.expectEqual(traversal.answers, traversal.candidates);

    // One identity lookup per candidate at most, and each of those is one
    // examined record. Stage 1's term has to stay removed for Stage 2's bound
    // to mean anything.
    try testing.expect(traversal.identity_records <= traversal.candidates);

    // The same assertions under the access path this replaced. Without this the
    // bound above is a number with no claim attached: it has to be a bound that
    // the old path breaks.
    graph_mod.bypass_relationship_index = true;
    defer graph_mod.bypass_relationship_index = false;

    const scanned = try measure(countAnchoredOutgoing, .{ snapshot, synthetic.focus });
    try testing.expectEqual(outgoing.answers, scanned.answers);
    try testing.expectEqual(snapshot.assertions.len, scanned.candidates);
    try testing.expect(scanned.candidates > scanned.answers);

    const scanned_traversal = try measure(traverseDepth2, .{ snapshot, synthetic.focus, testing.allocator });
    try testing.expectEqual(traversal.answers, scanned_traversal.answers);
    // Per frontier step, not once: this is the term that turns a depth-2
    // question into a repository-sized one.
    try testing.expectEqual(
        snapshot.assertions.len * (1 + fan_out),
        scanned_traversal.candidates,
    );
}

fn expectIndexFitsItsOwnShape(snapshot: *const Snapshot) !void {
    const expected = expectedIndexBytes(snapshot);
    const measured = measuredIndexBytes(snapshot);
    try testing.expect(measured <= 2 * expected);
}

test "anchored work follows the neighbourhood and not the repository" {
    // Two sizes, because a bound that holds at one size is a coincidence. The
    // graph grows by a factor of four here and the bound does not move at all.
    for ([_]u32{ 64, 256 }) |units| {
        var synthetic = try build(testing.allocator, .{ .units = units });
        defer synthetic.deinit();
        var snapshot = try synthetic.publish();
        defer snapshot.deinit();

        try expectWorkFollowsTheNeighbourhood(&synthetic, &snapshot);
        try expectIndexFitsItsOwnShape(&snapshot);
    }
}

/// The size the plan asks Stage 2 to be accepted at: past the external Java
/// probe that motivated it.
const external_scale: Spec = .{ .units = 12_500 };

/// Built and run only outside a debug build.
///
/// Debug is what makes this size impractical, not the size itself, and the
/// default lane has to stay quick enough that agents keep running it. The
/// command is named in the progress log: `zig build test-core
/// -Doptimize=ReleaseFast`. The acceptance claim is not lowered to fit the
/// default lane; it is moved to the lane that can carry it.
const run_external_scale = builtin.mode != .Debug;

test "the work bound holds past the scale that motivated it" {
    if (!run_external_scale) return error.SkipZigTest;

    var synthetic = try build(testing.allocator, external_scale);
    defer synthetic.deinit();
    var snapshot = try synthetic.publish();
    defer snapshot.deinit();

    // Past apache/dubbo's 230,753 assertions, which is the point.
    try testing.expect(snapshot.assertions.len > 230_753);

    try expectWorkFollowsTheNeighbourhood(&synthetic, &snapshot);
    try expectIndexFitsItsOwnShape(&snapshot);

    reportHeader(synthetic.spec, &snapshot);
    report("index bytes expected", .{
        .answers = expectedIndexBytes(&snapshot),
        .identity_records = measuredIndexBytes(&snapshot),
        .candidates = 0,
    });
}

test "query cost over the synthetic graph is measured, not assumed" {
    var synthetic = try build(testing.allocator, .{});
    defer synthetic.deinit();
    var snapshot = try synthetic.publish();
    defer snapshot.deinit();
    reportHeader(synthetic.spec, &snapshot);

    const counting = try measure(countCurrentAssertions, .{&snapshot});
    report("countAssertions (current)", counting);
    try testing.expect(counting.answers > 0);

    const outgoing = try measure(countAnchoredOutgoing, .{ &snapshot, synthetic.focus });
    report("relationships (source anchor)", outgoing);
    try testing.expectEqual(@as(usize, fan_out), outgoing.answers);

    const incoming = try measure(countAnchoredIncoming, .{ &snapshot, synthetic.focus });
    report("relationships (target anchor)", incoming);
    try testing.expectEqual(@as(usize, fan_in), incoming.answers);

    const traversal = try measure(traverseDepth2, .{ &snapshot, synthetic.focus, testing.allocator });
    report("depth-2 traversal", traversal);
    try testing.expectEqual(synthetic.depth2Reach(), traversal.answers);
}
