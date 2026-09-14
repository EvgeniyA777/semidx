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

    /// Registers a source unit and analyzes it.
    pub fn addUnit(
        self: *Index,
        path: []const u8,
        language: model.Language,
        bytes: []const u8,
    ) !model.SourceUnitId {
        const unit = try self.graph.addSourceUnit(path, language, bytes);
        _ = try self.analyzer.indexUnit(&self.graph, unit);
        return unit;
    }

    /// Applies an edit to one unit and reconciles only that unit's semantic
    /// region against the existing graph.
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
        _ = try self.graph.setSourceUnitBytes(unit, bytes);
        return self.analyzer.indexUnit(&self.graph, unit);
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

        for (correspondence.decisions) |decision| {
            switch (decision) {
                .removed => |id| {
                    try self.graph.removeSourceUnit(id);
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
                    _ = try self.applyEdit(match.id, unit.bytes);
                    outcome.changed += 1;
                    outcome.analyzed += 1;
                },
                .added => |scan_index| {
                    const unit = found.units[scan_index];
                    _ = try self.addUnit(unit.path, unit.language, unit.bytes);
                    outcome.added += 1;
                    outcome.analyzed += 1;
                },
                else => {},
            }
        }

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

    /// Takes a unit out of the index, removing what it introduced.
    pub fn removeUnit(self: *Index, unit: model.SourceUnitId) !void {
        try self.graph.removeSourceUnit(unit);
    }

    pub fn publish(self: *Index) !Snapshot {
        return self.graph.publish();
    }
};

test {
    _ = core;
    _ = ts;
    _ = frontends;
    _ = source;
}
