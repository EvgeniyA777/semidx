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

pub const model = core.model;
pub const contract = core.contract;
pub const reconcile = core.reconcile;
pub const Graph = core.Graph;
pub const Snapshot = core.Snapshot;
pub const Analyzer = frontends.Analyzer;

/// The language a source unit is presented to analysis as, from its path.
/// Returns null for paths no frontend in this slice covers.
pub fn languageForPath(path: []const u8) ?model.Language {
    if (std.mem.endsWith(u8, path, ".java")) return .java;
    if (std.mem.endsWith(u8, path, ".clj")) return .clojure;
    if (std.mem.endsWith(u8, path, ".cljc")) return .clojure;
    return null;
}

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

    pub fn publish(self: *Index) !Snapshot {
        return self.graph.publish();
    }
};

test {
    _ = core;
    _ = ts;
    _ = frontends;
}
