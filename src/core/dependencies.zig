//! What a unit's analysis depended on beyond its own contents.
//!
//! Scan reconciliation decides reanalysis from one rule: a unit whose own
//! content did not change is not re-read. That rule is exactly right while every
//! assertion is derived from a single unit, and exactly wrong the moment one is
//! not. This module is the override.
//!
//! Nothing declares a dependency today.
//! [ADR 003](../../docs/adr/003_reject_name_match_assertions.md) rejected the
//! cheap way to produce cross-unit facts, and the legitimate way — a frontend
//! applying its language's scoping rules — is waiting on `module` admission. The
//! mechanism is built now anyway, because the rule it overrides is currently
//! unconditional and lives in the registry: adding invalidation after a system
//! has assumed it never needs any is the retrofit the architecture rationale
//! warns about for incrementality generally.
//!
//! What a dependency means here is deliberately coarse: unit A's analysis read
//! something about unit B, so a change to B obliges a re-read of A. A finer rule
//! — invalidate only when a particular name changes — is a refinement of the
//! same record, not a different design.

const std = @import("std");
const Allocator = std.mem.Allocator;

const model = @import("model.zig");

pub const SourceUnitId = model.SourceUnitId;

pub const Declaration = struct {
    /// The unit whose analysis reached outside itself.
    dependent: SourceUnitId,
    /// The unit it read.
    provider: SourceUnitId,
    /// Why, in the producer's own words. Not interpreted; recorded so that a
    /// consumer can see what a reanalysis was owed to, and so a later finer
    /// rule has something to sharpen.
    reason: []const u8,
};

/// A local guard. A dependency cycle cannot make reanalysis loop forever, but a
/// pathological graph could still make one edit reach everything; this bounds
/// how far a single change is allowed to propagate before the rest is reported
/// rather than pursued.
pub const max_propagation_rounds: u32 = 64;

pub const Dependencies = struct {
    gpa: Allocator,
    declarations: std.ArrayList(Declaration),

    pub const empty: Dependencies = .{ .gpa = undefined, .declarations = .empty };

    pub fn init(gpa: Allocator) Dependencies {
        return .{ .gpa = gpa, .declarations = .empty };
    }

    pub fn deinit(self: *Dependencies) void {
        self.declarations.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn declare(self: *Dependencies, declaration: Declaration) Allocator.Error!void {
        if (declaration.dependent == declaration.provider) return;
        try self.declarations.append(self.gpa, declaration);
    }

    /// Withdraws everything one unit declared. Its analysis is about to be
    /// re-run, and what the previous run depended on is not evidence about what
    /// this one will.
    pub fn clearDependent(self: *Dependencies, dependent: SourceUnitId) void {
        var write: usize = 0;
        for (self.declarations.items) |declaration| {
            if (declaration.dependent == dependent) continue;
            self.declarations.items[write] = declaration;
            write += 1;
        }
        self.declarations.shrinkRetainingCapacity(write);
    }

    /// Withdraws everything mentioning a unit, in either direction. Used when a
    /// unit leaves the index: a declaration naming a unit that no longer exists
    /// is not a dependency, it is a dangling record.
    pub fn forget(self: *Dependencies, unit: SourceUnitId) void {
        var write: usize = 0;
        for (self.declarations.items) |declaration| {
            if (declaration.dependent == unit or declaration.provider == unit) continue;
            self.declarations.items[write] = declaration;
            write += 1;
        }
        self.declarations.shrinkRetainingCapacity(write);
    }

    pub fn count(self: Dependencies) usize {
        return self.declarations.items.len;
    }

    pub const Propagation = struct {
        /// Units that must be reanalyzed because something they read changed.
        /// Never includes a unit that was already going to be reanalyzed.
        affected: []const SourceUnitId,
        /// True when propagation stopped at `max_propagation_rounds` with more
        /// to do. The units found so far are still correct to reanalyze; the
        /// caller reports that the answer is incomplete rather than pretending
        /// it is not.
        exhausted: bool,
    };

    /// Units obliged to be reanalyzed by a change to `changed`, transitively.
    ///
    /// `changed` is both the seed and the exclusion set: a unit already being
    /// reanalyzed is not owed a second pass.
    pub fn propagate(
        self: Dependencies,
        gpa: Allocator,
        changed: []const SourceUnitId,
    ) Allocator.Error!Propagation {
        var seen: std.AutoHashMapUnmanaged(SourceUnitId, void) = .empty;
        defer seen.deinit(gpa);
        for (changed) |seed| try seen.put(gpa, seed, {});

        var affected: std.ArrayList(SourceUnitId) = .empty;
        errdefer affected.deinit(gpa);

        var frontier: std.ArrayList(SourceUnitId) = .empty;
        defer frontier.deinit(gpa);
        try frontier.appendSlice(gpa, changed);

        var rounds: u32 = 0;
        while (frontier.items.len != 0) {
            if (rounds >= max_propagation_rounds) {
                return .{
                    .affected = try affected.toOwnedSlice(gpa),
                    .exhausted = true,
                };
            }
            rounds += 1;

            var next: std.ArrayList(SourceUnitId) = .empty;
            defer next.deinit(gpa);

            for (self.declarations.items) |declaration| {
                if (!contains(frontier.items, declaration.provider)) continue;
                if (seen.contains(declaration.dependent)) continue;
                try seen.put(gpa, declaration.dependent, {});
                try affected.append(gpa, declaration.dependent);
                try next.append(gpa, declaration.dependent);
            }

            frontier.clearRetainingCapacity();
            try frontier.appendSlice(gpa, next.items);
        }

        return .{ .affected = try affected.toOwnedSlice(gpa), .exhausted = false };
    }
};

fn contains(haystack: []const SourceUnitId, needle: SourceUnitId) bool {
    for (haystack) |item| {
        if (item == needle) return true;
    }
    return false;
}

const testing = std.testing;

fn id(value: u32) SourceUnitId {
    return @enumFromInt(value);
}

fn declare(deps: *Dependencies, dependent: u32, provider: u32) !void {
    try deps.declare(.{
        .dependent = id(dependent),
        .provider = id(provider),
        .reason = "test dependency",
    });
}

test "a change with no declared dependency affects nothing" {
    var deps = Dependencies.init(testing.allocator);
    defer deps.deinit();

    const result = try deps.propagate(testing.allocator, &.{id(0)});
    defer testing.allocator.free(result.affected);
    try testing.expectEqual(@as(usize, 0), result.affected.len);
    try testing.expect(!result.exhausted);
}

test "a change reaches what declared a dependency on it" {
    var deps = Dependencies.init(testing.allocator);
    defer deps.deinit();
    try declare(&deps, 1, 0);
    try declare(&deps, 2, 0);

    const result = try deps.propagate(testing.allocator, &.{id(0)});
    defer testing.allocator.free(result.affected);
    try testing.expectEqual(@as(usize, 2), result.affected.len);
    try testing.expect(contains(result.affected, id(1)));
    try testing.expect(contains(result.affected, id(2)));
}

test "a change does not reach what it does not provide for" {
    var deps = Dependencies.init(testing.allocator);
    defer deps.deinit();
    try declare(&deps, 1, 0);

    // Unit 1 reads unit 0, not the other way round. Changing 1 owes 0 nothing.
    const result = try deps.propagate(testing.allocator, &.{id(1)});
    defer testing.allocator.free(result.affected);
    try testing.expectEqual(@as(usize, 0), result.affected.len);
}

test "dependencies propagate transitively" {
    var deps = Dependencies.init(testing.allocator);
    defer deps.deinit();
    try declare(&deps, 1, 0);
    try declare(&deps, 2, 1);
    try declare(&deps, 3, 2);

    const result = try deps.propagate(testing.allocator, &.{id(0)});
    defer testing.allocator.free(result.affected);
    try testing.expectEqual(@as(usize, 3), result.affected.len);
}

test "a unit already being reanalyzed is not owed a second pass" {
    var deps = Dependencies.init(testing.allocator);
    defer deps.deinit();
    try declare(&deps, 1, 0);

    const result = try deps.propagate(testing.allocator, &.{ id(0), id(1) });
    defer testing.allocator.free(result.affected);
    try testing.expectEqual(@as(usize, 0), result.affected.len);
}

test "a dependency cycle terminates and reports each unit once" {
    var deps = Dependencies.init(testing.allocator);
    defer deps.deinit();
    try declare(&deps, 1, 0);
    try declare(&deps, 0, 1);

    const result = try deps.propagate(testing.allocator, &.{id(0)});
    defer testing.allocator.free(result.affected);
    try testing.expectEqual(@as(usize, 1), result.affected.len);
    try testing.expectEqual(id(1), result.affected[0]);
    try testing.expect(!result.exhausted);
}

test "a unit cannot declare a dependency on itself" {
    var deps = Dependencies.init(testing.allocator);
    defer deps.deinit();
    try declare(&deps, 0, 0);
    try testing.expectEqual(@as(usize, 0), deps.count());
}

test "reanalysis withdraws what the previous run depended on" {
    var deps = Dependencies.init(testing.allocator);
    defer deps.deinit();
    try declare(&deps, 1, 0);
    try declare(&deps, 2, 0);

    deps.clearDependent(id(1));
    try testing.expectEqual(@as(usize, 1), deps.count());

    const result = try deps.propagate(testing.allocator, &.{id(0)});
    defer testing.allocator.free(result.affected);
    try testing.expectEqual(@as(usize, 1), result.affected.len);
    try testing.expectEqual(id(2), result.affected[0]);
}

test "a departing unit leaves no dangling declarations" {
    var deps = Dependencies.init(testing.allocator);
    defer deps.deinit();
    try declare(&deps, 1, 0);
    try declare(&deps, 0, 2);
    try declare(&deps, 3, 4);

    deps.forget(id(0));
    try testing.expectEqual(@as(usize, 1), deps.count());
    try testing.expectEqual(id(3), deps.declarations.items[0].dependent);
}

test "propagation that runs out of rounds says so" {
    var deps = Dependencies.init(testing.allocator);
    defer deps.deinit();
    // A chain longer than the round budget.
    var index: u32 = 0;
    while (index < max_propagation_rounds + 5) : (index += 1) {
        try declare(&deps, index + 1, index);
    }

    const result = try deps.propagate(testing.allocator, &.{id(0)});
    defer testing.allocator.free(result.affected);
    try testing.expect(result.exhausted);
    try testing.expectEqual(@as(usize, max_propagation_rounds), result.affected.len);
}
