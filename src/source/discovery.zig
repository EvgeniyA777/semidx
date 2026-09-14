//! Walking a source tree to find source units.
//!
//! This is the only filesystem in the ingestion path. The shared core never
//! learns that files, directories, extensions, or symbolic links exist, which
//! `zig build test-core -Dgrammars-dir=/nonexistent` keeps proving.
//!
//! The walk is deliberately conservative: it does not follow symbolic links, it
//! enters no directory on the exclusion list, and every file it declines for a
//! reason other than policy is reported.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const core = @import("semidx_core");
const model = core.model;

const languages = @import("languages.zig");
const scan_mod = @import("scan.zig");

pub const SourceScan = scan_mod.SourceScan;
pub const ScannedUnit = scan_mod.ScannedUnit;
pub const ScanDiagnostic = scan_mod.ScanDiagnostic;
pub const Budgets = scan_mod.Budgets;
pub const Options = scan_mod.Options;

pub const Error = error{
    /// The root could not be opened. Source ingestion must establish a root for
    /// a successful index; failing to is an error, not an empty repository.
    RootUnavailable,
} || Allocator.Error;

/// Walks `root` and returns everything it found and everything it declined.
pub fn scan(
    gpa: Allocator,
    io: Io,
    root: []const u8,
    options: Options,
) Error!SourceScan {
    var root_dir = Io.Dir.cwd().openDir(io, root, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch return error.RootUnavailable;
    defer root_dir.close(io);

    return scanDir(gpa, io, root_dir, root, options);
}

/// Walks an already-open root. `root_label` is recorded as the scan's root and
/// is not resolved against anything, so a caller that already holds a handle
/// does not have to describe it as a path the walk could reopen.
pub fn scanDir(
    gpa: Allocator,
    io: Io,
    root_dir: Io.Dir,
    root_label: []const u8,
    options: Options,
) Error!SourceScan {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();

    var walk: Walk = .{
        .gpa = gpa,
        .io = io,
        .arena = arena.allocator(),
        .options = options,
        .units = .empty,
        .diagnostics = .empty,
        .path = .empty,
        .units_exhausted = false,
    };
    defer walk.deinit();

    try walk.descend(root_dir, 0);

    // Every allocation happens before the struct literal. `arena` is moved into
    // the result by value, so a field initializer that allocates after the
    // `.arena` field is copied would allocate into a state the result never
    // sees, and leak it.
    const units = try arena.allocator().dupe(ScannedUnit, walk.units.items);
    const diagnostics = try arena.allocator().dupe(ScanDiagnostic, walk.diagnostics.items);
    const owned_root = try arena.allocator().dupe(u8, root_label);
    std.mem.sort(ScannedUnit, units, {}, lessByPath);
    std.mem.sort(ScanDiagnostic, diagnostics, {}, lessDiagnosticByPath);

    return .{
        .arena = arena,
        .root = owned_root,
        .units = units,
        .diagnostics = diagnostics,
        .budgets = options.budgets,
    };
}

fn lessByPath(_: void, a: ScannedUnit, b: ScannedUnit) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

fn lessDiagnosticByPath(_: void, a: ScanDiagnostic, b: ScanDiagnostic) bool {
    if (std.mem.eql(u8, a.path, b.path)) return std.mem.lessThan(u8, a.message, b.message);
    return std.mem.lessThan(u8, a.path, b.path);
}

const Walk = struct {
    gpa: Allocator,
    io: Io,
    /// Everything a scan hands back is owned by the scan's arena.
    arena: Allocator,
    options: Options,
    units: std.ArrayList(ScannedUnit),
    diagnostics: std.ArrayList(ScanDiagnostic),
    /// The root-relative path of the directory currently being walked.
    path: std.ArrayList(u8),
    units_exhausted: bool,

    fn deinit(self: *Walk) void {
        self.units.deinit(self.gpa);
        self.diagnostics.deinit(self.gpa);
        self.path.deinit(self.gpa);
    }

    fn descend(self: *Walk, dir: Io.Dir, depth: u32) Allocator.Error!void {
        var iterator = dir.iterate();
        while (iterator.next(self.io) catch |err| {
            try self.report(
                .analysis_failed,
                self.path.items,
                "this directory could not be read: {t}",
                .{err},
            );
            return;
        }) |entry| {
            switch (entry.kind) {
                .directory => try self.enterDirectory(dir, entry.name, depth),
                .file => try self.takeFile(dir, entry.name),
                .sym_link => try self.report(
                    .unsupported_construct,
                    try self.childPath(entry.name),
                    "symbolic links are not followed, so this entry was not ingested",
                    .{},
                ),
                else => {},
            }
        }
    }

    fn enterDirectory(self: *Walk, parent: Io.Dir, name: []const u8, depth: u32) Allocator.Error!void {
        for (self.options.excluded_directories) |excluded| {
            // Exclusion is policy, not degradation: an excluded directory is not
            // a thing the index failed to read, so it produces no diagnostic.
            if (std.mem.eql(u8, name, excluded)) return;
        }

        if (depth + 1 > self.options.budgets.max_depth) {
            try self.report(
                .analysis_unavailable,
                try self.childPath(name),
                "the tree is deeper than the {d}-level scan budget, so this directory was not entered",
                .{self.options.budgets.max_depth},
            );
            return;
        }

        var child = parent.openDir(self.io, name, .{
            .iterate = true,
            .follow_symlinks = false,
        }) catch |err| {
            try self.report(
                .analysis_unavailable,
                try self.childPath(name),
                "this directory could not be opened: {t}",
                .{err},
            );
            return;
        };
        defer child.close(self.io);

        const restore = self.path.items.len;
        defer self.path.shrinkRetainingCapacity(restore);
        try self.pushSegment(name);

        try self.descend(child, depth + 1);
    }

    fn takeFile(self: *Walk, dir: Io.Dir, name: []const u8) Allocator.Error!void {
        // A file no frontend covers is not a source unit. That is not a
        // degradation and does not need saying.
        const language = languages.forPath(name) orelse return;
        const path = try self.childPath(name);

        if (self.units.items.len >= self.options.budgets.max_units) {
            if (!self.units_exhausted) {
                self.units_exhausted = true;
                try self.report(
                    .analysis_unavailable,
                    path,
                    "the scan reached its {d}-unit budget; this and any later unit were not ingested",
                    .{self.options.budgets.max_units},
                );
            }
            return;
        }

        const limit = Io.Limit.limited(self.options.budgets.max_file_bytes);
        const bytes = dir.readFileAlloc(self.io, name, self.arena, limit) catch |err| switch (err) {
            error.StreamTooLong => {
                try self.report(
                    .analysis_unavailable,
                    path,
                    "this file is at or above the {d}-byte scan budget, so it was not ingested",
                    .{self.options.budgets.max_file_bytes},
                );
                return;
            },
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try self.report(
                    .analysis_unavailable,
                    path,
                    "this file could not be read: {t}",
                    .{err},
                );
                return;
            },
        };

        try self.units.append(self.gpa, .{
            .path = path,
            .language = language,
            .bytes = bytes,
            .content = scan_mod.contentId(bytes),
        });
    }

    /// The root-relative path of a child of the directory being walked.
    fn childPath(self: *Walk, name: []const u8) Allocator.Error![]const u8 {
        if (self.path.items.len == 0) return self.arena.dupe(u8, name);
        return std.fmt.allocPrint(self.arena, "{s}/{s}", .{ self.path.items, name });
    }

    fn pushSegment(self: *Walk, name: []const u8) Allocator.Error!void {
        if (self.path.items.len != 0) try self.path.append(self.gpa, '/');
        try self.path.appendSlice(self.gpa, name);
    }

    fn report(
        self: *Walk,
        kind: model.DiagnosticKind,
        path: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) Allocator.Error!void {
        try self.diagnostics.append(self.gpa, .{
            .kind = kind,
            .path = try self.arena.dupe(u8, path),
            .message = try std.fmt.allocPrint(self.arena, fmt, args),
        });
    }
};

const testing = std.testing;
const test_io = testing.io;

const Tree = struct {
    tmp: testing.TmpDir,

    fn init() Tree {
        return .{ .tmp = testing.tmpDir(.{ .iterate = true }) };
    }

    fn deinit(self: *Tree) void {
        self.tmp.cleanup();
    }

    fn file(self: *Tree, path: []const u8, bytes: []const u8) !void {
        if (std.fs.path.dirname(path)) |parent| {
            try self.tmp.dir.createDirPath(test_io, parent);
        }
        try self.tmp.dir.writeFile(test_io, .{ .sub_path = path, .data = bytes });
    }

    fn directory(self: *Tree, path: []const u8) !void {
        try self.tmp.dir.createDirPath(test_io, path);
    }

    fn scan(self: *Tree, options: Options) !SourceScan {
        return scanDir(testing.allocator, test_io, self.tmp.dir, "test-root", options);
    }
};

test "a scan finds the covered units and nothing else" {
    var tree = Tree.init();
    defer tree.deinit();

    try tree.file("Greeter.java", "class Greeter {}\n");
    try tree.file("demo/greeter.clj", "(ns demo.greeter)\n");
    try tree.file("demo/notes.md", "not a source unit\n");
    try tree.file("demo/Greeter.java.bak", "class Stale {}\n");
    try tree.file(".git/Config.java", "class Config {}\n");
    try tree.file("zig-out/Built.java", "class Built {}\n");

    var found = try tree.scan(.{});
    defer found.deinit();

    try testing.expectEqual(@as(usize, 2), found.units.len);

    // Sorted by path, so unit order does not inherit directory iteration order.
    try testing.expectEqualStrings("Greeter.java", found.units[0].path);
    try testing.expectEqualStrings("demo/greeter.clj", found.units[1].path);
    try testing.expectEqual(model.Language.java, found.units[0].language);
    try testing.expectEqual(model.Language.clojure, found.units[1].language);
    try testing.expectEqualStrings("class Greeter {}\n", found.units[0].bytes);
    try testing.expect(!scan_mod.sameContent(found.units[0].content, found.units[1].content));
    try testing.expectEqualStrings("test-root", found.root);

    // A file no frontend covers, and a directory on the exclusion list, are
    // policy rather than degradation. Neither produces a diagnostic.
    try testing.expectEqual(@as(usize, 0), found.diagnostics.len);
    try testing.expect(found.unitByPath("demo/notes.md") == null);
    try testing.expect(found.unitByPath(".git/Config.java") == null);
    try testing.expect(found.unitByPath("zig-out/Built.java") == null);
}

test "a scan finds zig units and skips zig build outputs" {
    var tree = Tree.init();
    defer tree.deinit();

    try tree.file("build.zig", "pub fn build() void {}\n");
    try tree.file("src/root.zig", "fn main() void {}\n");
    try tree.file("build.zig.zon", ".{}\n");
    try tree.file(".zig-cache/o/generated.zig", "fn cached() void {}\n");
    try tree.file("zig-out/lib/installed.zig", "fn installed() void {}\n");

    var found = try tree.scan(.{});
    defer found.deinit();

    try testing.expectEqual(@as(usize, 2), found.units.len);
    try testing.expectEqualStrings("build.zig", found.units[0].path);
    try testing.expectEqualStrings("src/root.zig", found.units[1].path);
    for (found.units) |unit| try testing.expectEqual(model.Language.zig, unit.language);
    try testing.expectEqual(@as(usize, 0), found.diagnostics.len);
}

test "a scan of the same tree twice is identical" {
    var tree = Tree.init();
    defer tree.deinit();
    try tree.file("a/One.java", "class One {}\n");
    try tree.file("b/Two.java", "class Two {}\n");
    try tree.file("c/three.clj", "(ns three)\n");

    var first = try tree.scan(.{});
    defer first.deinit();
    var second = try tree.scan(.{});
    defer second.deinit();

    try testing.expectEqual(first.units.len, second.units.len);
    for (first.units, second.units) |a, b| {
        try testing.expectEqualStrings(a.path, b.path);
        try testing.expect(scan_mod.sameContent(a.content, b.content));
    }
}

test "a file at the size budget is reported, not dropped" {
    var tree = Tree.init();
    defer tree.deinit();
    try tree.file("Small.java", "class S {}\n");
    try tree.file("Large.java", "class L { /* padding padding padding padding */ }\n");

    var found = try tree.scan(.{ .budgets = .{ .max_file_bytes = 20 } });
    defer found.deinit();

    try testing.expectEqual(@as(usize, 1), found.units.len);
    try testing.expectEqualStrings("Small.java", found.units[0].path);

    const diagnostic = found.findDiagnostic("Large.java").?;
    try testing.expectEqual(model.DiagnosticKind.analysis_unavailable, diagnostic.kind);
    try testing.expect(std.mem.indexOf(u8, diagnostic.message, "20-byte") != null);
}

test "reaching the unit budget is reported once" {
    var tree = Tree.init();
    defer tree.deinit();
    try tree.file("One.java", "class One {}\n");
    try tree.file("Two.java", "class Two {}\n");
    try tree.file("Three.java", "class Three {}\n");

    var found = try tree.scan(.{ .budgets = .{ .max_units = 1 } });
    defer found.deinit();

    try testing.expectEqual(@as(usize, 1), found.units.len);
    try testing.expectEqual(@as(usize, 1), found.countDiagnostics(.analysis_unavailable));
    try testing.expect(std.mem.indexOf(
        u8,
        found.diagnostics[0].message,
        "1-unit budget",
    ) != null);
}

test "a tree deeper than the depth budget is reported at the boundary" {
    var tree = Tree.init();
    defer tree.deinit();
    try tree.file("Top.java", "class Top {}\n");
    try tree.file("one/Mid.java", "class Mid {}\n");
    try tree.file("one/two/Deep.java", "class Deep {}\n");

    var found = try tree.scan(.{ .budgets = .{ .max_depth = 1 } });
    defer found.deinit();

    try testing.expectEqual(@as(usize, 2), found.units.len);
    try testing.expectEqualStrings("Top.java", found.units[0].path);
    try testing.expectEqualStrings("one/Mid.java", found.units[1].path);

    const diagnostic = found.findDiagnostic("one/two").?;
    try testing.expectEqual(model.DiagnosticKind.analysis_unavailable, diagnostic.kind);
    try testing.expect(std.mem.indexOf(u8, diagnostic.message, "1-level") != null);
}

test "a symbolic link is reported and never followed" {
    var tree = Tree.init();
    defer tree.deinit();
    try tree.file("Greeter.java", "class Greeter {}\n");
    try tree.directory("inside");
    try tree.file("inside/Nested.java", "class Nested {}\n");

    // A link to the directory that contains it. Following links at all would
    // make this walk non-terminating; not following them makes it a report.
    tree.tmp.dir.symLink(test_io, ".", "loop", .{ .is_directory = true }) catch |err| switch (err) {
        error.AccessDenied, error.Unexpected => return error.SkipZigTest,
        else => return err,
    };
    try tree.tmp.dir.symLink(test_io, "../outside.java", "escape.java", .{});

    var found = try tree.scan(.{});
    defer found.deinit();

    // The walk terminated, and found exactly the real files.
    try testing.expectEqual(@as(usize, 2), found.units.len);
    try testing.expectEqualStrings("Greeter.java", found.units[0].path);
    try testing.expectEqualStrings("inside/Nested.java", found.units[1].path);

    // Both links are visible as declined entries rather than as absences.
    try testing.expectEqual(@as(usize, 2), found.countDiagnostics(.unsupported_construct));
    const escape = found.findDiagnostic("escape.java").?;
    try testing.expect(std.mem.indexOf(u8, escape.message, "not followed") != null);
    try testing.expect(found.findDiagnostic("loop") != null);
}

test "an unreadable root is an error, not an empty repository" {
    try testing.expectError(error.RootUnavailable, scan(
        testing.allocator,
        test_io,
        "this-path-does-not-exist-anywhere",
        .{},
    ));
}

test "an empty tree scans to no units and no diagnostics" {
    var tree = Tree.init();
    defer tree.deinit();

    var found = try tree.scan(.{});
    defer found.deinit();
    try testing.expectEqual(@as(usize, 0), found.units.len);
    try testing.expectEqual(@as(usize, 0), found.diagnostics.len);
}
