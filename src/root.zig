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

    /// Registers every unit a scan found and analyzes it, and records what the
    /// scan declined so a file that was not ingested is visible rather than
    /// absent.
    ///
    /// This is first-pass ingestion. Reconciling a rescan against an existing
    /// registry — unchanged, changed, added, removed, renamed — is Stage 3 of
    /// [plan 002](../docs/plans/002_repository_scale_ingestion.md) and does not
    /// exist yet; calling this twice on the same index will reject the repeated
    /// paths.
    pub fn addScan(self: *Index, found: source.SourceScan) !void {
        for (found.units) |unit| {
            _ = try self.addUnit(unit.path, unit.language, unit.bytes);
        }
        for (found.diagnostics) |diagnostic| {
            const message = try std.fmt.allocPrint(
                self.graph.gpa,
                "{s}: {s}",
                .{ diagnostic.path, diagnostic.message },
            );
            defer self.graph.gpa.free(message);
            try self.graph.addDiagnostic(
                diagnostic.kind,
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
