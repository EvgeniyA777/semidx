//! The assembled vertical slice: a local semantic index over a set of source
//! units, built and maintained in memory.
//!
//! Everything a consumer can ask is answered from a published `Snapshot`. The
//! frontends and the parser sit behind `Analyzer` and contribute assertions;
//! they are never the source of an answer.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const core = @import("semidx_core");
pub const ts = @import("semidx_tree_sitter");
pub const frontends = @import("semidx_frontends");
pub const source = @import("semidx_source");

pub const model = core.model;
pub const contract = core.contract;
pub const reconcile = core.reconcile;
pub const Graph = core.Graph;
pub const Snapshot = core.Snapshot;
pub const Analyzer = frontends.Analyzer;

/// The language a source unit is presented to analysis as, from its path.
/// Returns null for paths no frontend in this build covers.
///
/// One table, owned by `source/languages`. A second one here would drift.
pub const languageForPath = source.languageForPath;

pub const Index = struct {
    graph: Graph,
    analyzer: Analyzer,

    pub fn init(gpa: Allocator, repository_path: []const u8) !Index {
        return .{
            .graph = try Graph.init(gpa, repository_path),
            .analyzer = Analyzer.init(gpa, Analyzer.default_budget),
        };
    }

    pub fn deinit(self: *Index) void {
        self.analyzer.deinit();
        self.graph.deinit();
        self.* = undefined;
    }

    /// Registers a source unit and analyzes it, then reanalyzes units whose
    /// Java package bindings it changed.
    pub fn addUnit(
        self: *Index,
        path: []const u8,
        language: model.Language,
        bytes: []const u8,
    ) !model.SourceUnitId {
        var upkeep = try Upkeep.begin(self, &.{});
        defer upkeep.deinit();
        const unit = try self.registerUnit(path, language, bytes, &upkeep);
        try upkeep.finish(null);
        return unit;
    }

    fn registerUnit(
        self: *Index,
        path: []const u8,
        language: model.Language,
        bytes: []const u8,
        upkeep: *Upkeep,
    ) !model.SourceUnitId {
        const unit = try self.graph.addSourceUnit(path, language, bytes);
        upkeep.before.clearRetainingCapacity();
        _ = try self.analyzer.indexUnit(&self.graph, unit);
        try upkeep.recordAnalysis(unit);
        return unit;
    }

    /// Applies an edit to one unit and reconciles only that unit's semantic
    /// region against the existing graph, then reanalyzes what read it.
    ///
    /// The two steps are separate revisions on purpose. Ingestion establishes
    /// the unit's new contents first, which marks the unit's existing analysis
    /// stale; analysis then either makes it current again or leaves it stale.
    /// An edit whose analysis fails therefore cannot leave earlier facts
    /// answering questions about source that no longer exists.
    pub fn applyEdit(
        self: *Index,
        unit: model.SourceUnitId,
        bytes: []const u8,
    ) !reconcile.Outcome {
        var upkeep = try Upkeep.begin(self, &.{unit});
        defer upkeep.deinit();
        const outcome = try self.editUnit(unit, bytes, &upkeep);
        try upkeep.finish(null);
        return outcome;
    }

    fn editUnit(
        self: *Index,
        unit: model.SourceUnitId,
        bytes: []const u8,
        upkeep: *Upkeep,
    ) !reconcile.Outcome {
        try upkeep.captureBefore(unit);
        _ = try self.graph.setSourceUnitBytes(unit, bytes);
        const outcome = try self.analyzer.indexUnit(&self.graph, unit);
        try upkeep.recordAnalysis(unit);
        return outcome;
    }

    /// What one scan did to the graph.
    pub const ScanOutcome = struct {
        unchanged: usize = 0,
        changed: usize = 0,
        renamed: usize = 0,
        added: usize = 0,
        removed: usize = 0,
        /// Units a frontend was asked to read. The number that matters: it must
        /// track what changed, not how large the repository is.
        analyzed: usize = 0,
        /// Moves the scan declined to claim because the content did not
        /// identify one unit. Those units appear as removals and additions.
        ambiguous_renames: usize = 0,
        /// Units reanalyzed not because they changed but because something they
        /// had read did, or because the Java package bindings they resolve
        /// names against changed.
        invalidated: usize = 0,
    };

    /// Applies a scan of the source tree to the graph.
    ///
    /// The first scan against an empty index is all additions; every later one
    /// is reconciled against what the index already holds. Only units whose
    /// contents changed are reanalyzed — a move is not a change, and an
    /// untouched file is not re-read.
    ///
    /// Order matters. Removals go first so that a unit renamed onto a path a
    /// departing unit still occupies has somewhere to land.
    pub fn applyScan(self: *Index, found: source.SourceScan) !ScanOutcome {
        const gpa = self.graph.gpa;

        var known_records: std.ArrayList(core.graph.SourceUnitRecord) = .empty;
        defer known_records.deinit(gpa);
        try self.graph.knownUnits(&known_records, gpa);

        var known: std.ArrayList(source.registry.KnownUnit) = .empty;
        defer known.deinit(gpa);
        try known.ensureTotalCapacity(gpa, known_records.items.len);
        for (known_records.items) |record| {
            known.appendAssumeCapacity(.{ .id = record.id, .identity = record.identity() });
        }

        var correspondence = try source.registry.reconcile(gpa, known.items, found.units);
        defer correspondence.deinit();

        var outcome: ScanOutcome = .{ .ambiguous_renames = correspondence.ambiguous.len };

        // Dependency propagation reads the declarations as they stand before
        // the scan: a removal forgets every declaration naming the unit, which
        // is exactly the information needed to find what read it.
        var seeds: std.ArrayList(model.SourceUnitId) = .empty;
        defer seeds.deinit(gpa);
        for (correspondence.decisions) |decision| {
            switch (decision) {
                // A move changes no contents, and an addition has nothing
                // pointing at it yet: a declaration names a unit, and no unit
                // can have named one that did not exist.
                .changed => |match| try seeds.append(gpa, match.id),
                .removed => |id| try seeds.append(gpa, id),
                else => {},
            }
        }
        var upkeep = try Upkeep.begin(self, seeds.items);
        defer upkeep.deinit();

        for (correspondence.decisions) |decision| {
            switch (decision) {
                .removed => |id| {
                    try upkeep.captureBefore(id);
                    try self.graph.removeSourceUnit(id);
                    try upkeep.recordRemoval();
                    outcome.removed += 1;
                },
                else => {},
            }
        }
        for (correspondence.decisions) |decision| {
            switch (decision) {
                .renamed => |match| {
                    _ = try self.graph.setSourceUnitPath(match.id, found.units[match.scan_index].path);
                    outcome.renamed += 1;
                },
                else => {},
            }
        }
        for (correspondence.decisions) |decision| {
            switch (decision) {
                .unchanged => outcome.unchanged += 1,
                .changed => |match| {
                    const unit = found.units[match.scan_index];
                    _ = try self.editUnit(match.id, unit.bytes, &upkeep);
                    outcome.changed += 1;
                    outcome.analyzed += 1;
                },
                .added => |scan_index| {
                    const unit = found.units[scan_index];
                    _ = try self.registerUnit(unit.path, unit.language, unit.bytes, &upkeep);
                    outcome.added += 1;
                    outcome.analyzed += 1;
                },
                else => {},
            }
        }

        try upkeep.finish(&outcome);
        try self.recordScanDiagnostics(found, correspondence);
        return outcome;
    }

    /// Records what the scan declined to ingest and what it declined to decide,
    /// replacing the previous scan's account rather than accumulating beside it.
    fn recordScanDiagnostics(
        self: *Index,
        found: source.SourceScan,
        correspondence: source.registry.Correspondence,
    ) !void {
        const gpa = self.graph.gpa;
        self.graph.dropScanDiagnostics();

        for (found.diagnostics) |diagnostic| {
            const message = try std.fmt.allocPrint(
                gpa,
                "{s}: {s}",
                .{ diagnostic.path, diagnostic.message },
            );
            defer gpa.free(message);
            try self.graph.addDiagnostic(diagnostic.kind, null, core.graph.ingestion, message);
        }

        for (correspondence.ambiguous) |ambiguity| {
            const message = try std.fmt.allocPrint(
                gpa,
                "{d} removed and {d} added source units share identical contents, " ++
                    "so no move could be established between them",
                .{ ambiguity.removed_units, ambiguity.added_units },
            );
            defer gpa.free(message);
            try self.graph.addDiagnostic(
                .unsupported_construct,
                null,
                core.graph.ingestion,
                message,
            );
        }
    }

    /// Moves a unit to a new path. Its contents did not change, so nothing is
    /// reanalyzed and nothing inside it loses its identity.
    pub fn renameUnit(
        self: *Index,
        unit: model.SourceUnitId,
        path: []const u8,
    ) !void {
        _ = try self.graph.setSourceUnitPath(unit, path);
    }

    /// Takes a unit out of the index, removing what it introduced, then
    /// reanalyzes what read it.
    pub fn removeUnit(self: *Index, unit: model.SourceUnitId) !void {
        var upkeep = try Upkeep.begin(self, &.{unit});
        defer upkeep.deinit();
        try upkeep.captureBefore(unit);
        try self.graph.removeSourceUnit(unit);
        try upkeep.recordRemoval();
        try upkeep.finish(null);
    }

    pub fn publish(self: *Index) !Snapshot {
        return self.graph.publish();
    }
};

/// Keeps cross-unit facts current across one batch of source changes: a single
/// edit, addition, or removal, or a whole scan.
///
/// Two things can make a unit's analysis out of date without its own contents
/// changing, and each has its own mechanism:
///
/// - A unit it read changed. Its dependency declarations say so, and they are
///   read once, before the batch touches anything.
/// - The set of top-level classes its Java package exports changed. No
///   declaration can say so, because a name that was unresolved read no
///   provider — the provider did not exist yet. So each step that removes or
///   analyzes a unit compares that unit's exports before and after, and a
///   package whose exports changed owes its other Java units a reanalysis.
///
/// Order within a batch matters and is tracked: a unit analyzed before a later
/// step changed its package saw the old bindings and is read again, while a
/// unit analyzed after the last change already saw the final ones and is not.
/// Reanalysis cannot change exports — they depend only on a unit's own
/// contents — so one round settles the batch.
const Upkeep = struct {
    index: *Index,
    gpa: Allocator,
    /// Counts removals and own-content analyses, in the order they happen.
    step: u64,
    /// The step at which each unit was last analyzed in this batch.
    analyzed_at: std.AutoHashMapUnmanaged(model.SourceUnitId, u64),
    /// The latest step that changed each package's exports. Keys are borrowed
    /// from the graph's interned strings.
    changed_packages: std.StringHashMapUnmanaged(u64),
    /// The unit being changed, before and after the step.
    before: std.ArrayList(frontends.java_packages.Export),
    after: std.ArrayList(frontends.java_packages.Export),
    /// Units owed reanalysis because a unit they read is changing.
    dependents: []const model.SourceUnitId,
    exhausted: bool,

    fn begin(index: *Index, seeds: []const model.SourceUnitId) !Upkeep {
        const gpa = index.graph.gpa;
        var dependents: []const model.SourceUnitId = &.{};
        var exhausted = false;
        if (seeds.len != 0 and index.graph.dependencies.count() != 0) {
            const propagation = try index.graph.dependencies.propagate(gpa, seeds);
            dependents = propagation.affected;
            exhausted = propagation.exhausted;
        }
        return .{
            .index = index,
            .gpa = gpa,
            .step = 0,
            .analyzed_at = .empty,
            .changed_packages = .empty,
            .before = .empty,
            .after = .empty,
            .dependents = dependents,
            .exhausted = exhausted,
        };
    }

    fn deinit(self: *Upkeep) void {
        self.analyzed_at.deinit(self.gpa);
        self.changed_packages.deinit(self.gpa);
        self.before.deinit(self.gpa);
        self.after.deinit(self.gpa);
        self.gpa.free(self.dependents);
        self.* = undefined;
    }

    /// Reads what `unit` exports before it is changed.
    fn captureBefore(self: *Upkeep, unit: model.SourceUnitId) !void {
        self.before.clearRetainingCapacity();
        try frontends.java_packages.exportsOf(&self.index.graph, unit, self.gpa, &self.before);
    }

    /// The captured unit left the index and exports nothing now.
    fn recordRemoval(self: *Upkeep) !void {
        self.step += 1;
        self.after.clearRetainingCapacity();
        try self.markChanges();
    }

    /// `unit` was just analyzed against its own contents.
    fn recordAnalysis(self: *Upkeep, unit: model.SourceUnitId) !void {
        self.step += 1;
        try self.analyzed_at.put(self.gpa, unit, self.step);
        self.after.clearRetainingCapacity();
        try frontends.java_packages.exportsOf(&self.index.graph, unit, self.gpa, &self.after);
        try self.markChanges();
    }

    /// Every package with an export in one of `before` and `after` but not the
    /// other changed at this step.
    fn markChanges(self: *Upkeep) !void {
        try self.markMissing(self.before.items, self.after.items);
        try self.markMissing(self.after.items, self.before.items);
    }

    fn markMissing(
        self: *Upkeep,
        from: []const frontends.java_packages.Export,
        against: []const frontends.java_packages.Export,
    ) !void {
        outer: for (from) |candidate| {
            for (against) |other| {
                if (candidate.eql(other)) continue :outer;
            }
            try self.changed_packages.put(self.gpa, candidate.package, self.step);
        }
    }

    /// Reanalyzes every unit the batch left out of date, each once.
    fn finish(self: *Upkeep, outcome: ?*Index.ScanOutcome) !void {
        const graph = &self.index.graph;
        var owed: std.ArrayList(model.SourceUnitId) = .empty;
        defer owed.deinit(self.gpa);

        for (self.dependents) |unit| {
            if (self.analyzed_at.contains(unit)) continue;
            try appendOwed(self.gpa, &owed, graph, unit);
        }

        var exports: std.ArrayList(frontends.java_packages.Export) = .empty;
        defer exports.deinit(self.gpa);
        var packages = self.changed_packages.iterator();
        while (packages.next()) |entry| {
            const package = entry.key_ptr.*;
            const changed_at = entry.value_ptr.*;
            for (self.index.analyzer.java_packages.candidates(package)) |unit| {
                if ((self.analyzed_at.get(unit) orelse 0) >= changed_at) continue;
                // Only a unit that currently declares classes in the package
                // resolves names against it. A hinted unit that moved away or
                // can no longer be analyzed is not owed anything here.
                exports.clearRetainingCapacity();
                try frontends.java_packages.exportsOf(graph, unit, self.gpa, &exports);
                for (exports.items) |declared| {
                    if (!std.mem.eql(u8, declared.package, package)) continue;
                    try appendOwed(self.gpa, &owed, graph, unit);
                    break;
                }
            }
        }

        // Independent of hash-map iteration order.
        std.mem.sort(model.SourceUnitId, owed.items, {}, lessUnit);
        for (owed.items) |unit| {
            _ = try self.index.analyzer.indexUnit(graph, unit);
            if (outcome) |counts| {
                counts.invalidated += 1;
                counts.analyzed += 1;
            }
        }

        if (self.exhausted) {
            try graph.addDiagnostic(
                .analysis_unavailable,
                null,
                core.graph.ingestion,
                "invalidation stopped at its propagation budget; units further " ++
                    "along the dependency chain were not reanalyzed",
            );
        }
    }

    fn appendOwed(
        gpa: Allocator,
        owed: *std.ArrayList(model.SourceUnitId),
        graph: *Graph,
        unit: model.SourceUnitId,
    ) !void {
        const record = graph.unit(unit) orelse return;
        if (!record.isLive()) return;
        if (std.mem.indexOfScalar(model.SourceUnitId, owed.items, unit) != null) return;
        try owed.append(gpa, unit);
    }

    fn lessUnit(_: void, a: model.SourceUnitId, b: model.SourceUnitId) bool {
        return @intFromEnum(a) < @intFromEnum(b);
    }
};

test {
    _ = core;
    _ = ts;
    _ = frontends;
    _ = source;
}
