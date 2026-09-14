//! Deciding what happened to a source tree between one scan and the next.
//!
//! This is a pure function over two sets of unit identity evidence. It touches
//! no filesystem, no graph, and no frontend, which is what lets the awkward
//! cases — a move, a swap, an ambiguous rename — be tested directly instead of
//! through a whole indexing run.
//!
//! The rule, in order:
//!
//! 1. A path present in both scans is the same unit. Path is the strongest
//!    evidence available and it is unambiguous: a scan holds each path once.
//!    Whether the contents changed decides only whether reanalysis is owed.
//! 2. A unit whose path disappeared corresponds to a new unit with identical
//!    content and the same language, and only when exactly one of each exists
//!    for that content. Identical bytes under a new path is an established
//!    correspondence, not a guess.
//! 3. Anything left is a removal or an addition. A file that moved *and*
//!    changed lands here, because nothing establishes that the new unit is the
//!    old one — and inventing that correspondence from similarity is what the
//!    constitution's identity clause forbids presenting as a fact.

const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("semidx_core");
const model = core.model;

const scan_mod = @import("scan.zig");

pub const ScannedUnit = scan_mod.ScannedUnit;

/// A unit the graph already holds, as the evidence a new scan is compared to.
pub const KnownUnit = struct {
    id: model.SourceUnitId,
    identity: model.UnitIdentityEvidence,
};

pub const Match = struct {
    id: model.SourceUnitId,
    /// Index into the scan's units.
    scan_index: u32,
};

pub const Decision = union(enum) {
    /// Same path, same content. Nothing is owed.
    unchanged: Match,
    /// Same path, different content. The unit is reanalyzed.
    changed: Match,
    /// New path, identical content. The unit keeps its identity and everything
    /// inside it, and owes no reanalysis, because nothing it contains moved.
    renamed: Match,
    /// No corresponding unit. Index into the scan's units.
    added: u32,
    /// No corresponding unit in the new scan.
    removed: model.SourceUnitId,

    pub fn preservesIdentity(self: Decision) bool {
        return switch (self) {
            .unchanged, .changed, .renamed => true,
            .added, .removed => false,
        };
    }

    pub fn needsAnalysis(self: Decision) bool {
        return switch (self) {
            .changed, .added => true,
            .unchanged, .renamed, .removed => false,
        };
    }
};

/// A rename that could not be claimed because the content did not identify one
/// unit. Reported rather than guessed: the units involved appear as removals and
/// additions, and a consumer can see why no move was recorded.
pub const AmbiguousRename = struct {
    content: model.ContentId,
    removed_units: u32,
    added_units: u32,
};

pub const Correspondence = struct {
    gpa: Allocator,
    decisions: []const Decision,
    ambiguous: []const AmbiguousRename,

    pub fn deinit(self: *Correspondence) void {
        self.gpa.free(self.decisions);
        self.gpa.free(self.ambiguous);
        self.* = undefined;
    }

    pub fn count(self: Correspondence, tag: std.meta.Tag(Decision)) usize {
        var total: usize = 0;
        for (self.decisions) |decision| {
            if (std.meta.activeTag(decision) == tag) total += 1;
        }
        return total;
    }

    pub fn analysisCount(self: Correspondence) usize {
        var total: usize = 0;
        for (self.decisions) |decision| {
            if (decision.needsAnalysis()) total += 1;
        }
        return total;
    }
};

pub fn reconcile(
    gpa: Allocator,
    known: []const KnownUnit,
    units: []const ScannedUnit,
) Allocator.Error!Correspondence {
    var decisions: std.ArrayList(Decision) = .empty;
    errdefer decisions.deinit(gpa);
    var ambiguous: std.ArrayList(AmbiguousRename) = .empty;
    errdefer ambiguous.deinit(gpa);

    // Keyed lookups rather than nested scans: this runs over every unit in a
    // repository on every rescan, and a scan inside a scan is how ingestion
    // becomes quadratic without anyone deciding that it should.
    var by_path: std.StringHashMapUnmanaged(u32) = .empty;
    defer by_path.deinit(gpa);
    try by_path.ensureTotalCapacity(gpa, @intCast(units.len));
    for (units, 0..) |unit, index| {
        by_path.putAssumeCapacity(unit.path, @intCast(index));
    }

    const matched = try gpa.alloc(bool, units.len);
    defer gpa.free(matched);
    @memset(matched, false);

    // Orphans carry their evidence with them. Looking it back up by id would be
    // a scan inside a loop, which is the quadratic shape this module avoids.
    var orphaned: std.ArrayList(KnownUnit) = .empty;
    defer orphaned.deinit(gpa);

    // Pass 1: path correspondence.
    for (known) |unit| {
        const index = by_path.get(unit.identity.path) orelse {
            try orphaned.append(gpa, unit);
            continue;
        };
        matched[index] = true;
        const match: Match = .{ .id = unit.id, .scan_index = index };
        const same = model.sameContent(unit.identity.content, units[index].content) and
            unit.identity.language == units[index].language;
        try decisions.append(gpa, if (same) .{ .unchanged = match } else .{ .changed = match });
    }

    // Pass 2: content correspondence for what the first pass could not place.
    var removed_by_content: std.AutoHashMapUnmanaged(model.ContentId, Candidates) = .empty;
    defer removed_by_content.deinit(gpa);
    for (orphaned.items) |unit| {
        const slot = try removed_by_content.getOrPut(gpa, unit.identity.content);
        if (!slot.found_existing) slot.value_ptr.* = .{};
        slot.value_ptr.observe(.{ .removed = .{
            .id = unit.id,
            .language = unit.identity.language,
        } });
    }

    for (units, 0..) |unit, index| {
        if (matched[index]) continue;
        const slot = removed_by_content.getPtr(unit.content) orelse continue;
        slot.observe(.{ .added = @intCast(index) });
    }

    var resolved_renames: std.AutoHashMapUnmanaged(model.SourceUnitId, u32) = .empty;
    defer resolved_renames.deinit(gpa);

    var entries = removed_by_content.iterator();
    while (entries.next()) |entry| {
        const candidates = entry.value_ptr.*;
        if (candidates.added == 0) continue;
        if (candidates.removed == 1 and candidates.added == 1) {
            const id = candidates.removed_id.?;
            const index = candidates.added_index.?;
            // A rename is only a rename between units of the same language.
            // Identical bytes read as two different languages are two different
            // units, whatever the byte comparison says.
            if (candidates.removed_language.? != units[index].language) continue;
            try resolved_renames.put(gpa, id, index);
            continue;
        }
        try ambiguous.append(gpa, .{
            .content = entry.key_ptr.*,
            .removed_units = candidates.removed,
            .added_units = candidates.added,
        });
    }

    // Pass 3: whatever is left.
    for (orphaned.items) |unit| {
        if (resolved_renames.get(unit.id)) |index| {
            matched[index] = true;
            try decisions.append(gpa, .{ .renamed = .{ .id = unit.id, .scan_index = index } });
        } else {
            try decisions.append(gpa, .{ .removed = unit.id });
        }
    }
    for (units, 0..) |_, index| {
        if (matched[index]) continue;
        try decisions.append(gpa, .{ .added = @intCast(index) });
    }

    return .{
        .gpa = gpa,
        .decisions = try decisions.toOwnedSlice(gpa),
        .ambiguous = try ambiguous.toOwnedSlice(gpa),
    };
}

const Candidates = struct {
    removed: u32 = 0,
    added: u32 = 0,
    removed_id: ?model.SourceUnitId = null,
    removed_language: ?model.Language = null,
    added_index: ?u32 = null,

    const Observation = union(enum) {
        removed: struct { id: model.SourceUnitId, language: model.Language },
        added: u32,
    };

    fn observe(self: *Candidates, observation: Observation) void {
        switch (observation) {
            .removed => |unit| {
                self.removed += 1;
                if (self.removed_id == null) {
                    self.removed_id = unit.id;
                    self.removed_language = unit.language;
                }
            },
            .added => |index| {
                self.added += 1;
                if (self.added_index == null) self.added_index = index;
            },
        }
    }
};

const testing = std.testing;

fn scanned(path: []const u8, language: model.Language, contents: []const u8) ScannedUnit {
    return .{
        .path = path,
        .language = language,
        .bytes = contents,
        .content = model.contentId(contents),
    };
}

fn knownUnit(id: u32, path: []const u8, language: model.Language, contents: []const u8) KnownUnit {
    return .{
        .id = @enumFromInt(id),
        .identity = .{
            .path = path,
            .language = language,
            .content = model.contentId(contents),
        },
    };
}

fn decisionFor(found: Correspondence, id: u32) ?Decision {
    const wanted: model.SourceUnitId = @enumFromInt(id);
    for (found.decisions) |decision| {
        const matches = switch (decision) {
            .unchanged, .changed, .renamed => |match| match.id == wanted,
            .removed => |removed| removed == wanted,
            .added => false,
        };
        if (matches) return decision;
    }
    return null;
}

test "a first scan against an empty registry is all additions" {
    const units = [_]ScannedUnit{
        scanned("A.java", .java, "class A {}"),
        scanned("b.clj", .clojure, "(ns b)"),
    };
    var found = try reconcile(testing.allocator, &.{}, &units);
    defer found.deinit();

    try testing.expectEqual(@as(usize, 2), found.count(.added));
    try testing.expectEqual(@as(usize, 2), found.analysisCount());
}

test "an unchanged tree decides nothing and owes no analysis" {
    const known = [_]KnownUnit{
        knownUnit(0, "A.java", .java, "class A {}"),
        knownUnit(1, "b.clj", .clojure, "(ns b)"),
    };
    const units = [_]ScannedUnit{
        scanned("A.java", .java, "class A {}"),
        scanned("b.clj", .clojure, "(ns b)"),
    };
    var found = try reconcile(testing.allocator, &known, &units);
    defer found.deinit();

    try testing.expectEqual(@as(usize, 2), found.count(.unchanged));
    try testing.expectEqual(@as(usize, 0), found.analysisCount());
    for (found.decisions) |decision| try testing.expect(decision.preservesIdentity());
}

test "same path with different contents is one changed unit" {
    const known = [_]KnownUnit{knownUnit(0, "A.java", .java, "class A {}")};
    const units = [_]ScannedUnit{scanned("A.java", .java, "class A { void f() {} }")};

    var found = try reconcile(testing.allocator, &known, &units);
    defer found.deinit();

    try testing.expectEqual(@as(usize, 1), found.decisions.len);
    try testing.expectEqual(@as(usize, 1), found.count(.changed));
    try testing.expectEqual(@as(usize, 1), found.analysisCount());
    try testing.expect(found.decisions[0].preservesIdentity());
}

test "identical content under a new path is a rename that owes no analysis" {
    const known = [_]KnownUnit{knownUnit(7, "old/A.java", .java, "class A {}")};
    const units = [_]ScannedUnit{scanned("new/A.java", .java, "class A {}")};

    var found = try reconcile(testing.allocator, &known, &units);
    defer found.deinit();

    try testing.expectEqual(@as(usize, 1), found.decisions.len);
    const decision = decisionFor(found, 7).?;
    try testing.expectEqual(@as(u32, 0), decision.renamed.scan_index);
    try testing.expect(decision.preservesIdentity());
    // Nothing inside the unit moved, so nothing needs re-reading.
    try testing.expectEqual(@as(usize, 0), found.analysisCount());
}

test "a file that moved and changed is a removal and an addition" {
    const known = [_]KnownUnit{knownUnit(7, "old/A.java", .java, "class A {}")};
    const units = [_]ScannedUnit{scanned("new/A.java", .java, "class A { void f() {} }")};

    var found = try reconcile(testing.allocator, &known, &units);
    defer found.deinit();

    // Nothing establishes that the new unit is the old one. Claiming a rename
    // from similarity is the guess the identity rules forbid presenting as
    // established, so the break is reported as a break.
    try testing.expectEqual(@as(usize, 1), found.count(.removed));
    try testing.expectEqual(@as(usize, 1), found.count(.added));
    try testing.expectEqual(@as(usize, 0), found.count(.renamed));
    try testing.expectEqual(@as(usize, 0), found.ambiguous.len);
}

test "a path swap is two content changes, not two renames" {
    const known = [_]KnownUnit{
        knownUnit(0, "A.java", .java, "class A {}"),
        knownUnit(1, "B.java", .java, "class B {}"),
    };
    const units = [_]ScannedUnit{
        scanned("A.java", .java, "class B {}"),
        scanned("B.java", .java, "class A {}"),
    };

    var found = try reconcile(testing.allocator, &known, &units);
    defer found.deinit();

    // Path correspondence wins, so both units stay where they are and both are
    // reanalyzed. No rename is claimed, and therefore no rename has to be
    // applied through a path another unit still occupies.
    try testing.expectEqual(@as(usize, 2), found.count(.changed));
    try testing.expectEqual(@as(usize, 0), found.count(.renamed));
    try testing.expectEqual(@as(usize, 2), found.analysisCount());
}

test "a rename is not claimed when the content does not identify one unit" {
    const known = [_]KnownUnit{knownUnit(0, "old/A.java", .java, "class A {}")};
    const units = [_]ScannedUnit{
        scanned("one/A.java", .java, "class A {}"),
        scanned("two/A.java", .java, "class A {}"),
    };

    var found = try reconcile(testing.allocator, &known, &units);
    defer found.deinit();

    try testing.expectEqual(@as(usize, 0), found.count(.renamed));
    try testing.expectEqual(@as(usize, 1), found.count(.removed));
    try testing.expectEqual(@as(usize, 2), found.count(.added));

    // The ambiguity is reported rather than resolved by picking one.
    try testing.expectEqual(@as(usize, 1), found.ambiguous.len);
    try testing.expectEqual(@as(u32, 1), found.ambiguous[0].removed_units);
    try testing.expectEqual(@as(u32, 2), found.ambiguous[0].added_units);
}

test "identical bytes in two languages are not the same unit" {
    const known = [_]KnownUnit{knownUnit(0, "a.clj", .clojure, ";; shared\n")};
    const units = [_]ScannedUnit{scanned("A.java", .java, ";; shared\n")};

    var found = try reconcile(testing.allocator, &known, &units);
    defer found.deinit();

    try testing.expectEqual(@as(usize, 0), found.count(.renamed));
    try testing.expectEqual(@as(usize, 1), found.count(.removed));
    try testing.expectEqual(@as(usize, 1), found.count(.added));
}

test "a deletion beside an unrelated addition stays two separate decisions" {
    const known = [_]KnownUnit{
        knownUnit(0, "Keep.java", .java, "class Keep {}"),
        knownUnit(1, "Gone.java", .java, "class Gone {}"),
    };
    const units = [_]ScannedUnit{
        scanned("Keep.java", .java, "class Keep {}"),
        scanned("New.java", .java, "class New {}"),
    };

    var found = try reconcile(testing.allocator, &known, &units);
    defer found.deinit();

    try testing.expectEqual(@as(usize, 1), found.count(.unchanged));
    try testing.expectEqual(@as(usize, 1), found.count(.removed));
    try testing.expectEqual(@as(usize, 1), found.count(.added));
    try testing.expectEqual(@as(usize, 1), found.analysisCount());
    try testing.expectEqual(Decision.removed, std.meta.activeTag(decisionFor(found, 1).?));
}

test "a rename resolves beside unrelated churn" {
    const known = [_]KnownUnit{
        knownUnit(0, "Keep.java", .java, "class Keep {}"),
        knownUnit(1, "old/Moved.java", .java, "class Moved {}"),
        knownUnit(2, "Gone.java", .java, "class Gone {}"),
    };
    const units = [_]ScannedUnit{
        scanned("Keep.java", .java, "class Keep {}"),
        scanned("new/Moved.java", .java, "class Moved {}"),
        scanned("Fresh.java", .java, "class Fresh {}"),
    };

    var found = try reconcile(testing.allocator, &known, &units);
    defer found.deinit();

    try testing.expectEqual(@as(usize, 1), found.count(.unchanged));
    try testing.expectEqual(@as(usize, 1), found.count(.renamed));
    try testing.expectEqual(@as(usize, 1), found.count(.removed));
    try testing.expectEqual(@as(usize, 1), found.count(.added));
    try testing.expectEqual(@as(usize, 1), found.analysisCount());
    try testing.expectEqual(@as(usize, 0), found.ambiguous.len);
}

test "an emptied tree removes everything and analyzes nothing" {
    const known = [_]KnownUnit{
        knownUnit(0, "A.java", .java, "class A {}"),
        knownUnit(1, "b.clj", .clojure, "(ns b)"),
    };
    var found = try reconcile(testing.allocator, &known, &.{});
    defer found.deinit();

    try testing.expectEqual(@as(usize, 2), found.count(.removed));
    try testing.expectEqual(@as(usize, 0), found.analysisCount());
}
