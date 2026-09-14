//! Shared semantic core: the model, the graph, the frontend contract, and
//! reconciliation. This module has no parser dependency and no C dependency,
//! which `zig build test-core` proves by building and running it alone.

pub const model = @import("model.zig");
pub const contract = @import("contract.zig");
pub const graph = @import("graph.zig");
pub const reconcile = @import("reconcile.zig");
pub const strings = @import("strings.zig");

pub const Graph = graph.Graph;
pub const Snapshot = graph.Snapshot;

test {
    _ = model;
    _ = contract;
    _ = graph;
    _ = reconcile;
    _ = strings;
}
