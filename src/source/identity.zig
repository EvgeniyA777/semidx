//! A deterministic identity over what one complete source discovery scan saw.
//!
//! Named `semidx-source-state-v1` ([ADR 014](../../docs/adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md)
//! D2). It identifies source discovery input — scan policy, unit paths,
//! languages, and content, and scan diagnostics — never graph semantics, and it
//! never replaces `Snapshot.revision`, which keeps its own process-local
//! ordering meaning. Two processes scanning the same visible source state under
//! the same policy compute the same identity; any visible path, byte,
//! language, diagnostic, or policy difference changes it.
//!
//! This module knows about scan policy, normalized units, content digests, and
//! scan diagnostics. It must never learn about graph revisions, MCP, cursors,
//! or filesystem handles.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;

const scan_mod = @import("scan.zig");

/// The versioned encoding this module implements. Bumping it is a breaking
/// change to every previously computed identity.
pub const version_marker = "semidx-source-state-v1";

/// A source-state identity: 32 raw bytes, rendered at the MCP boundary as 64
/// lowercase hex characters (`hex_len`, `toHex`, `fromHex`). Internal
/// comparison stays over these fixed-size bytes.
pub const SourceStateId = [32]u8;

pub const hex_len = 64;

/// Computes the identity of a complete `SourceScan`.
///
/// This sorts its own scratch copies of `scan.units`, `scan.diagnostics`, and
/// `scan.excluded_directories` before hashing, so the identity does not depend
/// on the order the scan happened to hold them in — a scan produced by
/// `discovery.scan` is already sorted, but a hand-built scan (tests, or a
/// future producer) need not be for this function to agree with another one
/// over the same visible source state.
pub fn calculate(gpa: Allocator, scan: scan_mod.SourceScan) Allocator.Error!SourceStateId {
    const units = try gpa.dupe(scan_mod.ScannedUnit, scan.units);
    defer gpa.free(units);
    std.mem.sort(scan_mod.ScannedUnit, units, {}, lessUnitByPath);

    const diagnostics = try gpa.dupe(scan_mod.ScanDiagnostic, scan.diagnostics);
    defer gpa.free(diagnostics);
    std.mem.sort(scan_mod.ScanDiagnostic, diagnostics, {}, lessDiagnosticCanonical);

    const excluded_directories = try gpa.dupe([]const u8, scan.excluded_directories);
    defer gpa.free(excluded_directories);
    std.mem.sort([]const u8, excluded_directories, {}, lessBytes);

    var hasher = Sha256.init(.{});
    writeString(&hasher, version_marker);

    writeU64(&hasher, scan.budgets.max_file_bytes);
    writeU32(&hasher, scan.budgets.max_units);
    writeU32(&hasher, scan.budgets.max_depth);

    writeU32(&hasher, @intCast(excluded_directories.len));
    for (excluded_directories) |name| writeString(&hasher, name);

    writeU32(&hasher, @intCast(units.len));
    for (units) |scanned_unit| {
        writeString(&hasher, scanned_unit.path);
        writeString(&hasher, scanned_unit.language.tag());
        hasher.update(&scanned_unit.content);
    }

    writeU32(&hasher, @intCast(diagnostics.len));
    for (diagnostics) |diagnostic| {
        writeString(&hasher, @tagName(diagnostic.kind));
        writeString(&hasher, diagnostic.path);
        writeString(&hasher, diagnostic.message);
    }

    var out: SourceStateId = undefined;
    hasher.final(&out);
    return out;
}

pub fn same(a: SourceStateId, b: SourceStateId) bool {
    return std.mem.eql(u8, &a, &b);
}

/// Renders an identity as 64 lowercase hex characters, the only form crossing
/// the MCP boundary.
pub fn toHex(id: SourceStateId) [hex_len]u8 {
    var out: [hex_len]u8 = undefined;
    const digits = "0123456789abcdef";
    for (id, 0..) |byte, i| {
        out[i * 2] = digits[byte >> 4];
        out[i * 2 + 1] = digits[byte & 0x0f];
    }
    return out;
}

pub const ParseError = error{ WrongLength, InvalidHexDigit };

/// Parses a rendered identity. Only lowercase hex is accepted — the encoding
/// this module renders is always lowercase, so an uppercase or mixed-case
/// string was not produced here and is refused rather than normalized.
pub fn fromHex(text: []const u8) ParseError!SourceStateId {
    if (text.len != hex_len) return error.WrongLength;
    var out: SourceStateId = undefined;
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        const hi = hexDigit(text[i * 2]) orelse return error.InvalidHexDigit;
        const lo = hexDigit(text[i * 2 + 1]) orelse return error.InvalidHexDigit;
        out[i] = (hi << 4) | lo;
    }
    return out;
}

fn hexDigit(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        else => null,
    };
}

fn lessUnitByPath(_: void, a: scan_mod.ScannedUnit, b: scan_mod.ScannedUnit) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

/// Path, then kind, then message: the current discovery-facing comparator
/// (path then message) is insufficient once two diagnostics of different kinds
/// share both a path and a message.
fn lessDiagnosticCanonical(_: void, a: scan_mod.ScanDiagnostic, b: scan_mod.ScanDiagnostic) bool {
    if (!std.mem.eql(u8, a.path, b.path)) return std.mem.lessThan(u8, a.path, b.path);
    const a_kind = @tagName(a.kind);
    const b_kind = @tagName(b.kind);
    if (!std.mem.eql(u8, a_kind, b_kind)) return std.mem.lessThan(u8, a_kind, b_kind);
    return std.mem.lessThan(u8, a.message, b.message);
}

fn lessBytes(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn writeU32(hasher: *Sha256, value: u32) void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .big);
    hasher.update(&buf);
}

fn writeU64(hasher: *Sha256, value: u64) void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .big);
    hasher.update(&buf);
}

/// A length-prefixed byte string: a `u32` big-endian length, then the bytes.
/// Length prefixes before every variable-length string are what make the
/// encoding unambiguous — two adjacent fields can never be split at the wrong
/// boundary.
fn writeString(hasher: *Sha256, bytes: []const u8) void {
    writeU32(hasher, @intCast(bytes.len));
    hasher.update(bytes);
}

const testing = std.testing;
const model = @import("semidx_core").model;

fn unit(path: []const u8, language: model.Language, bytes: []const u8) scan_mod.ScannedUnit {
    return .{ .path = path, .language = language, .bytes = bytes, .content = scan_mod.contentId(bytes) };
}

fn scanWith(
    units: []const scan_mod.ScannedUnit,
    diagnostics: []const scan_mod.ScanDiagnostic,
    excluded_directories: []const []const u8,
) scan_mod.SourceScan {
    return .{
        .arena = std.heap.ArenaAllocator.init(testing.failing_allocator),
        .root = "test-root",
        .units = units,
        .diagnostics = diagnostics,
        .budgets = .{},
        .excluded_directories = excluded_directories,
    };
}

/// Pinned outputs of `semidx-source-state-v1` over two of the fixed vectors
/// `fixtures/working_copy_sync/identity_vectors.md` names (empty, one-unit).
/// Computed once from this implementation and committed so a change to field
/// order, endianness, or any other encoding detail — not just a change that
/// happens to make two computed values disagree with each other — fails a
/// test, per the plan's requirement to commit fixed vectors rather than only
/// prove internal equality/inequality.
const pinned_empty_vector = "e1d2baed93cfae204c909e54278de4148edb11165535d14dd34ab584ac9a786c";
const pinned_one_unit_vector = "88f8644312e4fdd0d08f6a6b27bc12e5e618915542fb49d9bb538f94abcf44b2";

test "the encoding matches its pinned fixed vectors" {
    const empty = try calculate(testing.allocator, scanWith(&.{}, &.{}, &.{}));
    try testing.expectEqualStrings(pinned_empty_vector, &toHex(empty));

    const one = [_]scan_mod.ScannedUnit{unit("a.zig", .zig, "pub fn a() void {}\n")};
    const one_unit_id = try calculate(testing.allocator, scanWith(&one, &.{}, &.{}));
    try testing.expectEqualStrings(pinned_one_unit_vector, &toHex(one_unit_id));
}

test "the empty scan has a stable identity distinct from a one-unit scan" {
    const empty = try calculate(testing.allocator, scanWith(&.{}, &.{}, &.{}));
    const empty_again = try calculate(testing.allocator, scanWith(&.{}, &.{}, &.{}));
    try testing.expect(same(empty, empty_again));

    const one = [_]scan_mod.ScannedUnit{unit("a.zig", .zig, "pub fn a() void {}\n")};
    const one_unit_id = try calculate(testing.allocator, scanWith(&one, &.{}, &.{}));
    try testing.expect(!same(empty, one_unit_id));
}

test "reordering units and diagnostics does not change the identity" {
    const a = unit("a.zig", .zig, "pub fn a() void {}\n");
    const b = unit("b.zig", .zig, "pub fn b() void {}\n");
    const c = unit("c.clj", .clojure, "(ns c)\n");
    const diag_x = scan_mod.ScanDiagnostic{ .kind = .unsupported_construct, .path = "a.zig", .message = "x" };
    const diag_y = scan_mod.ScanDiagnostic{ .kind = .analysis_failed, .path = "a.zig", .message = "x" };

    const forward = try calculate(testing.allocator, scanWith(&.{ a, b, c }, &.{ diag_x, diag_y }, &.{ "b_dir", "a_dir" }));
    const reversed = try calculate(testing.allocator, scanWith(&.{ c, b, a }, &.{ diag_y, diag_x }, &.{ "a_dir", "b_dir" }));
    try testing.expect(same(forward, reversed));
}

test "a byte change in one unit changes the identity" {
    const original = [_]scan_mod.ScannedUnit{unit("a.zig", .zig, "pub fn a() void {}\n")};
    const edited = [_]scan_mod.ScannedUnit{unit("a.zig", .zig, "pub fn a() void { return; }\n")};

    const before = try calculate(testing.allocator, scanWith(&original, &.{}, &.{}));
    const after = try calculate(testing.allocator, scanWith(&edited, &.{}, &.{}));
    try testing.expect(!same(before, after));
}

test "a path change with identical bytes changes the identity" {
    const at_a = [_]scan_mod.ScannedUnit{unit("a.zig", .zig, "pub fn a() void {}\n")};
    const at_renamed = [_]scan_mod.ScannedUnit{unit("renamed.zig", .zig, "pub fn a() void {}\n")};

    const before = try calculate(testing.allocator, scanWith(&at_a, &.{}, &.{}));
    const after = try calculate(testing.allocator, scanWith(&at_renamed, &.{}, &.{}));
    try testing.expect(!same(before, after));
}

test "a language change with identical path and bytes changes the identity" {
    const as_zig = [_]scan_mod.ScannedUnit{unit("a.txt", .zig, "same bytes")};
    const as_clojure = [_]scan_mod.ScannedUnit{unit("a.txt", .clojure, "same bytes")};

    const before = try calculate(testing.allocator, scanWith(&as_zig, &.{}, &.{}));
    const after = try calculate(testing.allocator, scanWith(&as_clojure, &.{}, &.{}));
    try testing.expect(!same(before, after));
}

test "an added diagnostic changes the identity even with unchanged units" {
    const units = [_]scan_mod.ScannedUnit{unit("a.zig", .zig, "pub fn a() void {}\n")};
    const diag = [_]scan_mod.ScanDiagnostic{.{ .kind = .unsupported_construct, .path = "a.zig", .message = "note" }};

    const before = try calculate(testing.allocator, scanWith(&units, &.{}, &.{}));
    const after = try calculate(testing.allocator, scanWith(&units, &diag, &.{}));
    try testing.expect(!same(before, after));
}

test "two diagnostics sharing a path and message but not a kind are both counted and ordered by kind" {
    const units = [_]scan_mod.ScannedUnit{unit("a.zig", .zig, "pub fn a() void {}\n")};
    const one_kind = [_]scan_mod.ScanDiagnostic{.{ .kind = .analysis_failed, .path = "a.zig", .message = "same" }};
    const other_kind = [_]scan_mod.ScanDiagnostic{.{ .kind = .unsupported_construct, .path = "a.zig", .message = "same" }};

    const a_id = try calculate(testing.allocator, scanWith(&units, &one_kind, &.{}));
    const b_id = try calculate(testing.allocator, scanWith(&units, &other_kind, &.{}));
    try testing.expect(!same(a_id, b_id));
}

test "a changed exclusion policy with unchanged units and diagnostics changes the identity" {
    const units = [_]scan_mod.ScannedUnit{unit("a.zig", .zig, "pub fn a() void {}\n")};

    const before = try calculate(testing.allocator, scanWith(&units, &.{}, &.{"node_modules"}));
    const after = try calculate(testing.allocator, scanWith(&units, &.{}, &.{ "node_modules", "vendor" }));
    try testing.expect(!same(before, after));
}

test "a changed budget with unchanged units, diagnostics, and exclusions changes the identity" {
    const units = [_]scan_mod.ScannedUnit{unit("a.zig", .zig, "pub fn a() void {}\n")};

    var base = scanWith(&units, &.{}, &.{});
    const before = try calculate(testing.allocator, base);
    base.budgets.max_depth += 1;
    const after = try calculate(testing.allocator, base);
    try testing.expect(!same(before, after));
}

test "hex rendering and parsing round-trip, and rejects the wrong shape" {
    const units = [_]scan_mod.ScannedUnit{unit("a.zig", .zig, "pub fn a() void {}\n")};
    const id = try calculate(testing.allocator, scanWith(&units, &.{}, &.{}));

    const rendered = toHex(id);
    try testing.expectEqual(@as(usize, hex_len), rendered.len);
    const parsed = try fromHex(&rendered);
    try testing.expect(same(id, parsed));

    try testing.expectError(error.WrongLength, fromHex(rendered[0 .. hex_len - 1]));
    var uppercase = rendered;
    uppercase[0] = std.ascii.toUpper(uppercase[0]);
    if (uppercase[0] != rendered[0]) try testing.expectError(error.InvalidHexDigit, fromHex(&uppercase));
}

test "two independently built equivalent scans over the same tree match" {
    const testing_io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing_io, "pkg");
    try tmp.dir.writeFile(testing_io, .{ .sub_path = "a.zig", .data = "pub fn a() void {}\n" });
    try tmp.dir.writeFile(testing_io, .{ .sub_path = "pkg/b.zig", .data = "pub fn b() void {}\n" });

    const discovery = @import("discovery.zig");
    var first = try discovery.scanDir(testing.allocator, testing_io, tmp.dir, "root", .{});
    defer first.deinit();
    var second = try discovery.scanDir(testing.allocator, testing_io, tmp.dir, "root", .{});
    defer second.deinit();

    const first_id = try calculate(testing.allocator, first);
    const second_id = try calculate(testing.allocator, second);
    try testing.expect(same(first_id, second_id));
}
