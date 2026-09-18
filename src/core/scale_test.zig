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
