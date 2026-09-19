//! Developer-only inspection command.
//!
//! It indexes the source files named on the command line and prints a summary
//! of the resulting graph. Its output is not a contract: no test asserts
//! against it, and no consumer should parse it. It exists so that the slice can
//! be run against real files without a test harness, and to show that indexing
//! and querying need no service, no daemon, and no network.

const std = @import("std");
const semidx = @import("semidx");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buffer);
    const out = &stdout.interface;

    var index = try semidx.Index.init(gpa, ".");
    defer index.deinit();

    var arguments = init.minimal.args.iterate();
    defer arguments.deinit();
    _ = arguments.skip();

    var indexed: usize = 0;
    while (arguments.next()) |path| {
        // A directory is walked; anything else is treated as one source file.
        // Opening it is the test, because asking the filesystem what something
        // is and then acting on the answer is two answers.
        if (std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true, .follow_symlinks = false })) |dir| {
            var root = dir;
            defer root.close(io);
            var found = semidx.source.discovery.scanDir(gpa, io, root, path, .{}) catch |err| {
                try out.print("skipped {s}: {t}\n", .{ path, err });
                continue;
            };
            defer found.deinit();
            _ = try index.applyScan(found);
            indexed += found.units.len;
            continue;
        } else |_| {}

        const language = semidx.languageForPath(path) orelse {
            try out.print("skipped {s}: no frontend in this build covers it\n", .{path});
            continue;
        };
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(16 << 20)) catch |err| {
            try out.print("skipped {s}: {t}\n", .{ path, err });
            continue;
        };
        defer gpa.free(bytes);
        _ = try index.addUnit(path, language, bytes);
        indexed += 1;
    }

    if (indexed == 0) {
        try out.print("usage: semidx-dev <source file or directory>...\n", .{});
        try out.flush();
        return;
    }

    var snapshot = try index.publish();
    defer snapshot.deinit();

    try printSummary(out, &snapshot);
    try out.flush();
}

fn printSummary(out: *std.Io.Writer, snapshot: *const semidx.Snapshot) !void {
    try out.print("revision {d}\n", .{snapshot.revision});
    try out.print("  repositories {d}\n", .{snapshot.countEntities(.{ .kind = .repository })});
    try out.print("  files        {d}\n", .{snapshot.countEntities(.{ .kind = .file })});
    try out.print("  definitions  {d}\n", .{snapshot.countEntities(.{ .kind = .definition })});
    try out.print("  assertions   {d} recorded\n", .{snapshot.assertions.len});
    try out.print("    facts       {d}\n", .{snapshot.countAssertions(.{ .resolution = .fact })});
    try out.print("    unresolved  {d}\n", .{snapshot.countUnresolvedAssertions()});
    try out.print("    approximate {d}\n", .{snapshot.countApproximateAssertions()});
    try out.print("    stale       {d}\n", .{snapshot.countAssertions(.{ .freshness = .stale })});

    try out.print("\nsource units\n", .{});
    for (snapshot.units) |unit| {
        try out.print("  {s} {s} ({s})\n", .{
            @tagName(unit.analysis()),
            unit.path,
            @tagName(unit.language),
        });
    }

    try out.print("\ndefinitions\n", .{});
    for (snapshot.entities) |entity| {
        if (entity.kind != .definition) continue;
        try out.print("  [{d}] {s} {s} {s}", .{
            @intFromEnum(entity.id),
            @tagName(entity.identity.language.?),
            entity.identity.role,
            entity.identity.name orelse "<anonymous>",
        });
        if (entity.evidence) |evidence| {
            // The path comes from the unit registry, not from identity
            // evidence, which no longer carries one.
            const path = if (snapshot.unit(evidence.unit)) |unit| unit.path else "<unknown unit>";
            try out.print("  ({s}:{d})", .{ path, evidence.range.start_row + 1 });
        }
        try out.print("\n", .{});
    }

    try out.print("\nunresolved targets\n", .{});
    var unresolved = snapshot.relationships(.{ .resolution = .unresolved });
    while (unresolved.next()) |assertion| {
        const relationship = assertion.claim.relationship;
        switch (relationship.target) {
            .designator => |name| try out.print("  {s} -> {s} ({s})\n", .{
                @tagName(relationship.kind),
                name,
                assertion.resolution.unresolved.explanation,
            }),
            .entity => {},
        }
    }

    if (snapshot.diagnostics.len > 0) {
        try out.print("\ndiagnostics\n", .{});
        for (snapshot.diagnostics) |diagnostic| {
            try out.print("  {s}: {s}\n", .{ @tagName(diagnostic.kind), diagnostic.message });
        }
    }
}
