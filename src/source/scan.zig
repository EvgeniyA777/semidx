//! What one pass over a source tree found.
//!
//! A scan is a value. Discovery produces one by walking a filesystem, and a
//! test can build one by hand — which is how the registry that consumes scans
//! stays testable without touching a disk.

const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("semidx_core");
const model = core.model;

/// A source unit's content identity.
///
/// SHA-256 rather than a fast 64-bit hash on purpose. This value decides "this
/// unit did not change, do not reanalyze it" and "this is the same unit under a
/// new path". A collision there is not a slow answer, it is a wrong graph with
/// a heuristic wearing the face of a fact.
pub const ContentId = [32]u8;

pub fn contentId(bytes: []const u8) ContentId {
    var out: ContentId = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &out, .{});
    return out;
}

pub fn sameContent(a: ContentId, b: ContentId) bool {
    return std.mem.eql(u8, &a, &b);
}

pub const ScannedUnit = struct {
    /// Root-relative and `/`-separated, whatever the host separator is.
    path: []const u8,
    language: model.Language,
    bytes: []const u8,
    content: ContentId,
};

/// Something discovery declined to ingest, and why.
///
/// Every exclusion that is not policy produces one of these. A file that is too
/// large, a tree that is too deep, a symbolic link, or a scan that hit its unit
/// ceiling is reported; it is never dropped in silence, because a silently
/// dropped file is indistinguishable from a repository that does not contain it.
pub const ScanDiagnostic = struct {
    kind: model.DiagnosticKind,
    /// Root-relative path of whatever was declined.
    path: []const u8,
    message: []const u8,
};

/// Local limits that keep a walk from running away on pathological input.
///
/// They are not a performance target. They exist so that a symlink farm, a
/// generated directory, or a multi-gigabyte blob fails as a named limit instead
/// of as an unbounded read.
pub const Budgets = struct {
    /// A file at or above this size is reported rather than ingested.
    max_file_bytes: u64 = 4 << 20,
    /// The most units one scan will collect.
    max_units: u32 = 20_000,
    /// How deep below the root the walk will descend.
    max_depth: u32 = 64,
};

/// Directory names the walk does not enter.
///
/// An explicit list rather than "skip anything starting with a dot": `.git` must
/// be skipped and `.github` must not be, and only a list can say so. Ignore-file
/// parsing is deliberately not implemented here.
pub const default_excluded_directories = [_][]const u8{
    ".git",
    ".zig-cache",
    "zig-out",
    ".cache",
    ".cpcache",
    "node_modules",
    "target",
    ".tree-sitter-grammars",
    ".jdtls-toolchain",
    ".lsp-toolchain",
    ".scip-toolchain",
    ".scip-java-toolchain",
};

pub const Options = struct {
    budgets: Budgets = .{},
    excluded_directories: []const []const u8 = &default_excluded_directories,
};

pub const SourceScan = struct {
    arena: std.heap.ArenaAllocator,
    /// The root this scan was taken under, as it was given.
    root: []const u8,
    /// Sorted by path. Directory iteration order is a filesystem detail, and
    /// letting it through would make unit identity allocation, and every test
    /// over a scan, depend on it.
    units: []const ScannedUnit,
    diagnostics: []const ScanDiagnostic,
    budgets: Budgets,

    pub fn deinit(self: *SourceScan) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn unitByPath(self: SourceScan, path: []const u8) ?ScannedUnit {
        for (self.units) |unit| {
            if (std.mem.eql(u8, unit.path, path)) return unit;
        }
        return null;
    }

    pub fn countDiagnostics(self: SourceScan, kind: model.DiagnosticKind) usize {
        var count: usize = 0;
        for (self.diagnostics) |diagnostic| {
            if (diagnostic.kind == kind) count += 1;
        }
        return count;
    }

    pub fn findDiagnostic(self: SourceScan, path: []const u8) ?ScanDiagnostic {
        for (self.diagnostics) |diagnostic| {
            if (std.mem.eql(u8, diagnostic.path, path)) return diagnostic;
        }
        return null;
    }
};

const testing = std.testing;

test "content identity distinguishes contents and ignores nothing" {
    const a = contentId("class A {}");
    const b = contentId("class B {}");
    try testing.expect(!sameContent(a, b));
    try testing.expect(sameContent(a, contentId("class A {}")));
    try testing.expect(!sameContent(contentId(""), contentId(" ")));
}
