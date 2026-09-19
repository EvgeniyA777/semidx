//! The assembled vertical slice: a local semantic index over a set of source
//! units, built and maintained in memory.
//!
//! Everything a consumer can ask is answered from a published `Snapshot`. The
//! frontends and the parser sit behind `Analyzer` and contribute assertions;
//! they are never the source of an answer.

const std = @import("std");
const builtin = @import("builtin");
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

/// Test-only counters for what keeping the graph current costs.
///
/// A dependent that is never reanalyzed is stale, and a dependent reanalyzed on
/// every edit is a scan wearing the word incremental. Both are correct-looking
/// from the outside, so the write path needs numbers the way the query path does
/// (`core.graph.work`). Rounds and reanalyses are kept apart because they are
/// two different costs: rounds measure how far along the dependency chain one
/// change reached, reanalyses how much work that reach turned into.
///
/// Counts accumulate until `reset`, except `propagation_rounds`, which keeps the
/// deepest chain any single batch walked in that window.
///
/// Outside a test build every call here compiles away.
pub const work = struct {
    /// Units reanalyzed by upkeep because something they read changed.
    pub var upkeep_reanalyses: usize = 0;
    /// The most propagation rounds one batch spent.
    pub var propagation_rounds: u32 = 0;
    /// Whether any batch stopped at `dependencies.max_propagation_rounds`.
    pub var propagation_exhausted: bool = false;

    pub fn reset() void {
        upkeep_reanalyses = 0;
        propagation_rounds = 0;
        propagation_exhausted = false;
    }

    inline fn reanalysis() void {
        if (!builtin.is_test) return;
        upkeep_reanalyses += 1;
    }

    inline fn propagation(rounds: u32, exhausted: bool) void {
        if (!builtin.is_test) return;
        if (rounds > propagation_rounds) propagation_rounds = rounds;
        if (exhausted) propagation_exhausted = true;
    }
};

pub const Index = struct {
    graph: Graph,
    analyzer: Analyzer,

    pub fn init(gpa: Allocator, repository_path: []const u8) !Index {
        return initAfter(gpa, repository_path, .{});
    }

    /// An empty index that issues none of the ids an earlier index for the same
    /// consumer issued. See `Graph.IdFloor`.
    pub fn initAfter(gpa: Allocator, repository_path: []const u8, floor: Graph.IdFloor) !Index {
        return .{
            .graph = try Graph.initAfter(gpa, repository_path, floor),
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
        try self.analyzeAdded(unit, upkeep);
        return unit;
    }

    /// Analyzes a unit that was registered in this batch and never analyzed.
    fn analyzeAdded(self: *Index, unit: model.SourceUnitId, upkeep: *Upkeep) !void {
        upkeep.before.clearRetainingCapacity();
        _ = try self.analyzer.indexUnit(&self.graph, unit);
        try upkeep.recordAnalysis(unit);
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
                // An addition has nothing pointing at it yet: a declaration
                // names a unit, and no unit can have named one that did not
                // exist. A move changes no contents, but a unit that found it
                // by path read where it was.
                .changed, .renamed => |match| try seeds.append(gpa, match.id),
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
        // Every addition is registered before anything is analyzed, so a unit
        // that names another by path finds it whatever order the scan lists
        // them in. Analysis order still matters; `Upkeep` accounts for it.
        var added: std.ArrayList(model.SourceUnitId) = .empty;
        defer added.deinit(gpa);
        for (correspondence.decisions) |decision| {
            switch (decision) {
                .added => |scan_index| {
                    const unit = found.units[scan_index];
                    try added.append(gpa, try self.graph.addSourceUnit(unit.path, unit.language, unit.bytes));
                },
                else => {},
            }
        }
        var next_added: usize = 0;
        for (correspondence.decisions) |decision| {
            switch (decision) {
                .unchanged => outcome.unchanged += 1,
                .changed => |match| {
                    const unit = found.units[match.scan_index];
                    _ = try self.editUnit(match.id, unit.bytes, &upkeep);
                    outcome.changed += 1;
                    outcome.analyzed += 1;
                },
                .added => {
                    try self.analyzeAdded(added.items[next_added], &upkeep);
                    next_added += 1;
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

    /// Moves a unit to a new path. Its contents did not change, so it is not
    /// reanalyzed and nothing inside it loses its identity. A unit that found
    /// it by its old path is reanalyzed.
    pub fn renameUnit(
        self: *Index,
        unit: model.SourceUnitId,
        path: []const u8,
    ) !void {
        var upkeep = try Upkeep.begin(self, &.{unit});
        defer upkeep.deinit();
        _ = try self.graph.setSourceUnitPath(unit, path);
        try upkeep.finish(null);
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
/// - A unit it read changed or moved. Its dependency declarations say so, and
///   they are read once, before the batch touches anything. A declaration
///   made during the batch counts too: a unit analyzed before a unit it read
///   was analyzed in the same batch read the provider's earlier state.
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
/// A `Class.method` aspect that changed, and the step it changed at. The
/// class-level aspect has an empty method name.
const ChangedAspect = struct {
    class: []const u8,
    method: []const u8,
    step: u64,
};

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
    /// The Java class shape the same unit exposed, before and after that step.
    /// Kept apart from the package export above because they answer different
    /// questions: a package export changes what a *name* can mean, a class
    /// shape changes what a *call* on a named class can select. Folding a
    /// method edit into the package channel would reanalyze every declarer and
    /// importer of the package for a change none of them can see.
    shape_before: std.ArrayList(frontends.java_members.Aspect),
    shape_after: std.ArrayList(frontends.java_members.Aspect),
    /// `Class.method` aspects whose answer may have changed, and when.
    changed_shapes: std.ArrayList(ChangedAspect),
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
            work.propagation(propagation.rounds, propagation.exhausted);
        }
        return .{
            .index = index,
            .gpa = gpa,
            .step = 0,
            .analyzed_at = .empty,
            .changed_packages = .empty,
            .before = .empty,
            .after = .empty,
            .shape_before = .empty,
            .shape_after = .empty,
            .changed_shapes = .empty,
            .dependents = dependents,
            .exhausted = exhausted,
        };
    }

    fn deinit(self: *Upkeep) void {
        self.analyzed_at.deinit(self.gpa);
        self.changed_packages.deinit(self.gpa);
        self.before.deinit(self.gpa);
        self.after.deinit(self.gpa);
        self.shape_before.deinit(self.gpa);
        self.shape_after.deinit(self.gpa);
        self.changed_shapes.deinit(self.gpa);
        self.gpa.free(self.dependents);
        self.* = undefined;
    }

    /// Reads what `unit` exports, and what shape it exposes, before it changes.
    fn captureBefore(self: *Upkeep, unit: model.SourceUnitId) !void {
        self.before.clearRetainingCapacity();
        try frontends.java_packages.exportsOf(&self.index.graph, unit, self.gpa, &self.before);
        self.shape_before.clearRetainingCapacity();
        try frontends.java_members.aspectsOf(&self.index.graph, unit, self.gpa, &self.shape_before);
    }

    /// The captured unit left the index and exports nothing now.
    fn recordRemoval(self: *Upkeep) !void {
        self.step += 1;
        self.after.clearRetainingCapacity();
        self.shape_after.clearRetainingCapacity();
        try self.markChanges();
    }

    /// `unit` was just analyzed against its own contents.
    fn recordAnalysis(self: *Upkeep, unit: model.SourceUnitId) !void {
        self.step += 1;
        try self.analyzed_at.put(self.gpa, unit, self.step);
        self.after.clearRetainingCapacity();
        try frontends.java_packages.exportsOf(&self.index.graph, unit, self.gpa, &self.after);
        self.shape_after.clearRetainingCapacity();
        try frontends.java_members.aspectsOf(&self.index.graph, unit, self.gpa, &self.shape_after);
        try self.markChanges();
    }

    /// Every package with an export in one of `before` and `after` but not the
    /// other changed at this step.
    fn markChanges(self: *Upkeep) !void {
        try self.markMissing(self.before.items, self.after.items);
        try self.markMissing(self.after.items, self.before.items);
        try self.markShapeMissing(self.shape_before.items, self.shape_after.items);
        try self.markShapeMissing(self.shape_after.items, self.shape_before.items);
    }

    /// Every aspect present on one side and not answered identically on the
    /// other changed at this step. The comparison is over one unit's own
    /// classes and methods, which is work the edit already pays to analyze.
    fn markShapeMissing(
        self: *Upkeep,
        from: []const frontends.java_members.Aspect,
        against: []const frontends.java_members.Aspect,
    ) !void {
        outer: for (from) |candidate| {
            for (against) |other| {
                if (candidate.eql(other)) continue :outer;
            }
            try self.noteChangedAspect(candidate.class, candidate.method);
        }
    }

    fn noteChangedAspect(self: *Upkeep, class: []const u8, method: []const u8) !void {
        for (self.changed_shapes.items) |*existing| {
            if (!std.mem.eql(u8, existing.class, class)) continue;
            if (!std.mem.eql(u8, existing.method, method)) continue;
            existing.step = self.step;
            return;
        }
        try self.changed_shapes.append(self.gpa, .{
            .class = class,
            .method = method,
            .step = self.step,
        });
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
        // A unit analyzed in this batch is covered above only by what it
        // declared before the batch, so its fresh declarations are checked
        // against every provider analyzed after it.
        for (graph.dependencies.declarations.items) |declaration| {
            const read_at = self.analyzed_at.get(declaration.dependent) orelse continue;
            const provided_at = self.analyzed_at.get(declaration.provider) orelse continue;
            if (provided_at <= read_at) continue;
            try appendOwed(self.gpa, &owed, graph, declaration.dependent);
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
            // A unit that imports from the package resolves names against it
            // too, and its import may have resolved to nothing last time, so it
            // has no dependency to propagate along. Imports are not in the
            // graph, so the hint is taken as it stands and the unit decides.
            for (self.index.analyzer.java_packages.importersOf(package)) |unit| {
                if ((self.analyzed_at.get(unit) orelse 0) >= changed_at) continue;
                try appendOwed(self.gpa, &owed, graph, unit);
            }
        }

        // A reader of a changed `Class.method` pair has no dependency to be
        // found by: its call resolved to nothing, so it read nothing. Only the
        // hint reaches it, and only the readers of what actually changed are
        // owed anything — not the package's declarers, not its importers.
        for (self.changed_shapes.items) |changed| {
            const readers = try self.index.analyzer.java_members.readersOf(
                changed.class,
                changed.method,
                self.gpa,
            );
            for (readers) |unit| {
                if ((self.analyzed_at.get(unit) orelse 0) >= changed.step) continue;
                try appendOwed(self.gpa, &owed, graph, unit);
            }
        }

        // Independent of hash-map iteration order.
        std.mem.sort(model.SourceUnitId, owed.items, {}, lessUnit);
        for (owed.items) |unit| {
            _ = try self.index.analyzer.indexUnit(graph, unit);
            work.reanalysis();
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
