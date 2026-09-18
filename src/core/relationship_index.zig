//! Derived adjacency over one published snapshot's assertion array.
//!
//! This index establishes nothing. Every bucket holds positions into the
//! snapshot's own assertions, it is rebuildable from them with nothing lost,
//! and no query result exists only here. It makes a recorded claim findable; a
//! claim is still made somewhere else, by a producer, with its own resolution.
//!
//! It is compressed sparse row rather than a map of lists, which is not a
//! micro-optimization. One allocation per index instead of one per key keeps
//! the memory proportional to the relationships that exist, and filling it in a
//! forward pass over the assertion array means bucket contents come out in
//! snapshot order by construction — so the order a consumer observes is
//! preserved by how the index is built rather than by a sort nobody would
//! notice going wrong.

const std = @import("std");
const Allocator = std.mem.Allocator;

const model = @import("model.zig");

/// Positions into the snapshot's assertion array, grouped by a dense key.
pub const Adjacency = struct {
    /// `keys + 1` entries: bucket `k` is `positions[offsets[k]..offsets[k + 1]]`.
    offsets: []u32,
    positions: []u32,

    pub const empty: Adjacency = .{ .offsets = &.{}, .positions = &.{} };

    /// The candidates for one key, in snapshot assertion order.
    ///
    /// A key the index does not hold is empty, not a reason to look elsewhere:
    /// nothing in the assertion array carries that key either.
    pub fn bucket(self: Adjacency, key: usize) []const u32 {
        if (self.offsets.len == 0 or key + 1 >= self.offsets.len) return &.{};
        return self.positions[self.offsets[key]..self.offsets[key + 1]];
    }

    pub fn deinit(self: *Adjacency, gpa: Allocator) void {
        gpa.free(self.offsets);
        gpa.free(self.positions);
        self.* = .empty;
    }

    pub fn byteSize(self: Adjacency) usize {
        return (self.offsets.len + self.positions.len) * @sizeOf(u32);
    }
};

/// Where one designator's candidates sit in the shared position array.
const Span = struct { start: u32, len: u32 };

/// Positions grouped by designator.
///
/// A hash map rather than a dense table, because designators are strings and
/// strings have no dense key space. The keys are the snapshot's own interned
/// designators, borrowed exactly like every other string a snapshot holds.
pub const DesignatorAdjacency = struct {
    spans: std.StringHashMapUnmanaged(Span),
    positions: []u32,

    pub const empty: DesignatorAdjacency = .{ .spans = .empty, .positions = &.{} };

    pub fn bucket(self: DesignatorAdjacency, designator: []const u8) []const u32 {
        const span = self.spans.get(designator) orelse return &.{};
        return self.positions[span.start .. span.start + span.len];
    }

    pub fn deinit(self: *DesignatorAdjacency, gpa: Allocator) void {
        self.spans.deinit(gpa);
        gpa.free(self.positions);
        self.* = .empty;
    }

    pub fn byteSize(self: DesignatorAdjacency) usize {
        // The map's own table, plus the shared position array. Approximate for
        // the hash map, exact for the positions.
        const entry = @sizeOf([]const u8) + @sizeOf(Span) + 1;
        return self.spans.capacity() * entry + self.positions.len * @sizeOf(u32);
    }
};

/// The three anchors a relationship query can be answered from.
///
/// `incoming` and `designator` are disjoint by construction and stay disjoint,
/// because a relationship target is either an entity or a designator and never
/// both. That is why neither index has to know about the other's filter.
pub const RelationshipIndex = struct {
    outgoing: Adjacency,
    incoming: Adjacency,
    designator: DesignatorAdjacency,

    pub const empty: RelationshipIndex = .{
        .outgoing = .empty,
        .incoming = .empty,
        .designator = .empty,
    };

    pub fn deinit(self: *RelationshipIndex, gpa: Allocator) void {
        self.outgoing.deinit(gpa);
        self.incoming.deinit(gpa);
        self.designator.deinit(gpa);
        self.* = .empty;
    }

    pub fn byteSize(self: RelationshipIndex) usize {
        return self.outgoing.byteSize() + self.incoming.byteSize() + self.designator.byteSize();
    }

    /// Builds every index in two passes over the assertion array.
    ///
    /// `live_entity_ids` is the id space the snapshot's live entities occupy.
    /// The key space is widened past it when an assertion names a higher id,
    /// which is not defensive padding: a claim that reached into another unit
    /// can outlive its target, and such a claim stays in the snapshot naming an
    /// entity that is no longer live. A query anchored on that id found it
    /// before this index existed, so it has to find it now.
    pub fn build(
        gpa: Allocator,
        assertions: []const model.Assertion,
        live_entity_ids: usize,
    ) Allocator.Error!RelationshipIndex {
        var self: RelationshipIndex = .empty;
        errdefer self.deinit(gpa);

        const keys = keySpace(assertions, live_entity_ids);
        self.outgoing = try buildAdjacency(gpa, assertions, keys, sourceKey);
        self.incoming = try buildAdjacency(gpa, assertions, keys, targetKey);
        self.designator = try buildDesignators(gpa, assertions);
        return self;
    }
};

fn keySpace(assertions: []const model.Assertion, live_entity_ids: usize) usize {
    var highest: usize = live_entity_ids;
    for (assertions) |assertion| {
        const relationship = assertion.relationship() orelse continue;
        highest = @max(highest, @as(usize, @intFromEnum(relationship.source)) + 1);
        switch (relationship.target) {
            .entity => |id| highest = @max(highest, @as(usize, @intFromEnum(id)) + 1),
            .designator => {},
        }
    }
    return highest;
}

fn sourceKey(relationship: model.RelationshipClaim) ?usize {
    return @intFromEnum(relationship.source);
}

fn targetKey(relationship: model.RelationshipClaim) ?usize {
    return switch (relationship.target) {
        .entity => |id| @intFromEnum(id),
        .designator => null,
    };
}

fn buildAdjacency(
    gpa: Allocator,
    assertions: []const model.Assertion,
    keys: usize,
    comptime keyOf: fn (model.RelationshipClaim) ?usize,
) Allocator.Error!Adjacency {
    if (keys == 0) return .empty;

    const offsets = try gpa.alloc(u32, keys + 1);
    errdefer gpa.free(offsets);
    @memset(offsets, 0);

    // Pass one counts per key, recorded in the slot *after* it, so the running
    // sum below turns counts into start offsets without a second array.
    var total: u32 = 0;
    for (assertions) |assertion| {
        const relationship = assertion.relationship() orelse continue;
        const key = keyOf(relationship) orelse continue;
        offsets[key + 1] += 1;
        total += 1;
    }
    for (1..offsets.len) |key| offsets[key] += offsets[key - 1];

    const positions = try gpa.alloc(u32, total);
    errdefer gpa.free(positions);

    // Pass two fills. Forward over the assertion array, so each bucket comes
    // out in snapshot assertion order — which is the order a consumer already
    // observes, preserved by construction rather than restored by a sort.
    const cursor = try gpa.alloc(u32, keys);
    defer gpa.free(cursor);
    @memcpy(cursor, offsets[0..keys]);

    for (assertions, 0..) |assertion, position| {
        const relationship = assertion.relationship() orelse continue;
        const key = keyOf(relationship) orelse continue;
        positions[cursor[key]] = @intCast(position);
        cursor[key] += 1;
    }

    return .{ .offsets = offsets, .positions = positions };
}

fn buildDesignators(
    gpa: Allocator,
    assertions: []const model.Assertion,
) Allocator.Error!DesignatorAdjacency {
    var self: DesignatorAdjacency = .empty;
    errdefer self.deinit(gpa);

    for (assertions) |assertion| {
        const relationship = assertion.relationship() orelse continue;
        const designator = switch (relationship.target) {
            .designator => |value| value,
            .entity => continue,
        };
        const found = try self.spans.getOrPut(gpa, designator);
        if (!found.found_existing) found.value_ptr.* = .{ .start = 0, .len = 0 };
        found.value_ptr.len += 1;
    }

    var total: u32 = 0;
    var counted = self.spans.valueIterator();
    while (counted.next()) |span| {
        span.start = total;
        total += span.len;
        span.len = 0;
    }

    self.positions = try gpa.alloc(u32, total);
    for (assertions, 0..) |assertion, position| {
        const relationship = assertion.relationship() orelse continue;
        const designator = switch (relationship.target) {
            .designator => |value| value,
            .entity => continue,
        };
        const span = self.spans.getPtr(designator).?;
        self.positions[span.start + span.len] = @intCast(position);
        span.len += 1;
    }
    return self;
}
