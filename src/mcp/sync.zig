//! Idempotent scan/compare/apply/publish coordination shared by `semidx_sync`
//! and its `semidx_refresh` compatibility alias
//! ([ADR 014](../../docs/adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md)
//! D3).
//!
//! An unchanged source-state identity keeps the published snapshot, revision,
//! and entity ids exactly as they are. A changed one reconciles through the
//! same `Index.applyScan`/`publish` path a plain refresh always used, and
//! pairs the newly published snapshot with the identity that produced it.
//! Every failure retains whatever snapshot/identity pair was already
//! published; the caller reports which state remains published and what
//! recovery step, if any, completed.
//!
//! This module knows about the configured root, discovery, `Index`, the
//! published `Snapshot`, and refresh recovery. It renders no tool schema,
//! JSON, or error text — `src/mcp/root.zig` turns its `Outcome` into a result.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;

const semidx = @import("semidx");
const identity = semidx.source.identity;

pub const SourceStateId = identity.SourceStateId;

pub const Error = Allocator.Error || Writer.Error;

/// The server state this coordinator reads and mutates, addressed through
/// pointers so `Server`'s fields stay the single owner of this state: this
/// module coordinates it without taking it over.
pub const Target = struct {
    gpa: Allocator,
    io: Io,
    root: []const u8,
    log: *Writer,
    index: *semidx.Index,
    snapshot: *semidx.Snapshot,
    retired: *?semidx.Index,
    poisoned: *bool,
    rebuilds: *u32,
    last_scan: *semidx.Index.ScanOutcome,
    source_state_id: *SourceStateId,
};

/// What a rebuild-then-reconcile step failed at, and whether the emergency
/// rebuild itself completed.
pub const ReconcileFailure = struct {
    stage: []const u8,
    err: anyerror,
    rebuilt: bool,
};

pub const Changed = struct {
    previous_revision: u64,
    outcome: semidx.Index.ScanOutcome,
    entity_ids_preserved: bool,
};

pub const Outcome = union(enum) {
    /// The observed identity matched the retained one and no recovery was
    /// pending: the published snapshot, revision, and entity ids are
    /// untouched.
    unchanged,
    /// A new snapshot was published.
    changed: Changed,
    /// Discovery itself failed; nothing was touched.
    scan_failed: anyerror,
    /// An earlier call had already failed and the retry rebuild failed again;
    /// nothing was touched this time either.
    rebuild_retry_failed,
    /// Reconciling or publishing the scan failed; see `ReconcileFailure`.
    reconcile_failed: ReconcileFailure,
};

/// Runs one scan/compare/apply/publish cycle against `target`.
pub fn run(target: Target) Error!Outcome {
    var found = semidx.source.discovery.scan(target.gpa, target.io, target.root, .{}) catch |err| {
        return .{ .scan_failed = err };
    };
    defer found.deinit();

    const observed = try identity.calculate(target.gpa, found);

    if (!target.poisoned.* and identity.same(target.source_state_id.*, observed)) {
        return .unchanged;
    }

    if (target.poisoned.* and !try rebuild(target, found)) {
        return .rebuild_retry_failed;
    }

    const previous = target.snapshot.revision;
    const outcome = target.index.applyScan(found) catch |err| return reconcileFailed(target, found, "applying the scan", err);
    const next = target.index.publish() catch |err| return reconcileFailed(target, found, "publishing", err);

    const rebuilt = target.retired.* != null;
    target.snapshot.deinit();
    target.snapshot.* = next;
    if (target.retired.*) |*retired| {
        retired.deinit();
        target.retired.* = null;
    }
    target.last_scan.* = outcome;
    target.source_state_id.* = observed;

    return .{ .changed = .{
        .previous_revision = previous,
        .outcome = outcome,
        .entity_ids_preserved = !rebuilt,
    } };
}

fn reconcileFailed(target: Target, found: semidx.source.SourceScan, stage: []const u8, err: anyerror) Error!Outcome {
    try target.log.print("semidx-mcp: sync: {s} failed: {t}; rebuilding the index\n", .{ stage, err });
    try target.log.flush();
    target.poisoned.* = true;
    const rebuilt = try rebuild(target, found);
    return .{ .reconcile_failed = .{ .stage = stage, .err = err, .rebuilt = rebuilt } };
}

/// Builds a fresh index from `found` above the current index's ids. On
/// success it becomes the index; the index the published snapshot borrows
/// from stays alive until a snapshot of the new one replaces it.
fn rebuild(target: Target, found: semidx.source.SourceScan) Error!bool {
    const floor = target.index.graph.idFloor();
    var fresh = semidx.Index.initAfter(target.gpa, target.root, floor) catch |err| {
        try target.log.print("semidx-mcp: sync: recovery: creating a fresh index failed: {t}\n", .{err});
        try target.log.flush();
        target.poisoned.* = true;
        return false;
    };
    _ = fresh.applyScan(found) catch |err| {
        try target.log.print("semidx-mcp: sync: recovery: indexing the scan into a fresh index failed: {t}\n", .{err});
        try target.log.flush();
        fresh.deinit();
        target.poisoned.* = true;
        return false;
    };
    if (target.retired.* == null) {
        target.retired.* = target.index.*;
    } else {
        target.index.deinit();
    }
    target.index.* = fresh;
    target.poisoned.* = false;
    target.rebuilds.* += 1;
    try target.log.print("semidx-mcp: sync: recovery: rebuilt the index ({d} rebuilds so far)\n", .{target.rebuilds.*});
    try target.log.flush();
    return true;
}
