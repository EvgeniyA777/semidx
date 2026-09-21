//! Developer-only measurement command: what a designator holds today, and what
//! the index keyed on it is shaped like.
//!
//! [Plan 013](../docs/plans/013_unresolved_mentions_from_the_callee_anchor.md)
//! changes what a designator is, so its Stage 0 has to record what one is
//! before the change and its Stage 4 the same numbers after. Neither the
//! inspection command (`semidx-dev`) nor the claim sampler
//! (`semidx-claim-sample`) reports the index shape or the written form of a
//! designator, which is why this exists beside them.
//!
//! It is not a lane and not a conformance check. `zig build test`,
//! `zig build test-mcp`, `zig build dogfood` and `zig build preview-gate` do not
//! build it, and no test asserts against its output.
//!
//! **The report is reproducible without this program.** It indexes the root,
//! publishes one snapshot, and counts:
//!
//!   * every unresolved relationship whose target is a designator, grouped by
//!     the language of its source entity, its relationship kind, and the shape
//!     of the designator text;
//!   * how many of those claims are **reachable from a definition's name**: a
//!     live definition in the indexed root carries that designator's name, in
//!     the claim's own language, so asking that definition by name finds the
//!     claim. This is the question Plan 013 exists to change the answer to;
//!     the number is over the same claims either way, so a run before and a
//!     run after are comparable.
//!   * the designator index: how many distinct keys it holds, how many
//!     positions they bucket, what it costs, and its largest buckets.
//!
//! Since [ADR 010](../docs/adr/010_designator_is_a_structured_name.md) a
//! designator is a name and an optional qualifier, so the shape below is the
//! shape of the **name** it holds, and the qualifier is counted separately. A
//! run of the same report before that change measured the one string a
//! designator was then, which is what makes the two comparable: the column that
//! held expression text is the column that must empty.
//!
//! A designator's shape is decided by its own bytes, in three categories:
//!
//!   * `simple_name` — every byte is a name byte in the source entity's
//!     language and the first is not a digit;
//!   * `qualified_name` — not simple, but the language's qualifier separator
//!     splits it into two or more simple names (`Foo.bar`, `str/join`);
//!   * `expression` — anything else, which is source text that is not a name
//!     (`foo.bar(a, b)`).
//!
//! The name bytes are the language's own: Java adds `$`, Zig adds nothing past
//! `_`, and Clojure admits the symbol constituents a name may carry. The
//! separator is `.` for Java and Zig and `/` for Clojure. The categories are a
//! measurement's vocabulary, not the model's: the graph stores one string today,
//! and this command only says what that string looks like.

const std = @import("std");
const semidx = @import("semidx");

const model = semidx.model;

const Shape = enum {
    simple_name,
    qualified_name,
    expression,

    pub fn tag(self: Shape) []const u8 {
        return @tagName(self);
    }
};

fn separatorFor(language: model.Language) u8 {
    return switch (language) {
        .java, .zig => '.',
        .clojure => '/',
    };
}

/// Whether `byte` may occur inside a name in `language`.
///
/// Every byte at or above 0x80 counts as a name byte: all three languages admit
/// non-ASCII identifiers, and decoding UTF-8 here would answer a question no
/// count in this report asks.
fn nameByte(language: model.Language, byte: u8) bool {
    if (byte >= 0x80) return true;
    return switch (language) {
        .java => std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '$',
        .zig => std.ascii.isAlphanumeric(byte) or byte == '_',
        // A Clojure symbol carries more than an identifier does, and `.` is one
        // of them: `str/join` is qualified by `/`, while `clojure.string` is a
        // single name.
        .clojure => std.ascii.isAlphanumeric(byte) or switch (byte) {
            '_', '$', '-', '+', '*', '!', '?', '<', '>', '=', '&', '%', '\'', '.', ':', '#' => true,
            else => false,
        },
    };
}

fn isSimpleName(language: model.Language, text: []const u8) bool {
    if (text.len == 0) return false;
    if (std.ascii.isDigit(text[0])) return false;
    for (text) |byte| {
        if (!nameByte(language, byte)) return false;
    }
    return true;
}

fn shapeOf(language: model.Language, text: []const u8) Shape {
    if (isSimpleName(language, text)) return .simple_name;
    var segments: usize = 0;
    var parts = std.mem.splitScalar(u8, text, separatorFor(language));
    while (parts.next()) |segment| {
        if (!isSimpleName(language, segment)) return .expression;
        segments += 1;
    }
    return if (segments >= 2) .qualified_name else .expression;
}

/// One designator key of the index, with the size of the bucket it holds.
const Bucket = struct {
    key: []const u8,
    positions: usize,
    /// The language of the first assertion in the bucket, which is what the
    /// key's shape is judged in. A key shared by two languages is reported
    /// under the first one the snapshot recorded.
    language: ?model.Language,
    /// How many live definitions carry this exact name, in any language. A
    /// designator-anchored query is only interesting where a definition of that
    /// name exists to anchor it.
    definitions: usize,
};

fn largerBucket(_: void, a: Bucket, b: Bucket) bool {
    if (a.positions != b.positions) return a.positions > b.positions;
    return std.mem.order(u8, a.key, b.key) == .lt;
}

const Options = struct {
    root: []const u8 = "",
    top: usize = 20,
};

const usage =
    \\usage: semidx-designator-shape --root <dir> [--top <n>]
    \\
    \\Indexes <dir> and reports what its unresolved designators hold and how the
    \\designator index buckets them. See the header of src/designator_shape.zig
    \\for the categories, which do not depend on this program.
    \\
;

fn parseOptions(arguments: anytype) !Options {
    var options: Options = .{};
    while (arguments.next()) |argument| {
        if (std.mem.eql(u8, argument, "--root")) {
            options.root = arguments.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, argument, "--top")) {
            const value = arguments.next() orelse return error.MissingValue;
            options.top = std.fmt.parseInt(usize, value, 10) catch return error.BadTop;
        } else {
            return error.UnknownArgument;
        }
    }
    if (options.root.len == 0) return error.MissingRoot;
    return options;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buffer);
    const out = &stdout.interface;

    var arguments = init.minimal.args.iterate();
    defer arguments.deinit();
    _ = arguments.skip();
    const options = parseOptions(&arguments) catch |err| {
        try out.print("{s}\n{t}\n", .{ usage, err });
        try out.flush();
        return err;
    };

    var index = try semidx.Index.init(gpa, options.root);
    defer index.deinit();

    var root = try std.Io.Dir.cwd().openDir(io, options.root, .{ .iterate = true, .follow_symlinks = false });
    defer root.close(io);
    var found = try semidx.source.discovery.scanDir(gpa, io, root, options.root, .{});
    defer found.deinit();
    const scanned = try index.applyScan(found);

    var snapshot = try index.publish();
    defer snapshot.deinit();

    const languages = std.enums.values(model.Language);
    const kinds = std.enums.values(model.RelationshipKind);
    const shapes = std.enums.values(Shape);

    // [language][kind][shape], plus one row for claims whose source entity the
    // snapshot no longer holds, which are counted apart rather than guessed at.
    var counts = [_][4][3]usize{[_][3]usize{[_]usize{0} ** 3} ** 4} ** 3;
    // [language][kind]: claims carrying a qualifier, and claims whose producer
    // could read no name at all.
    var qualified = [_][4]usize{[_]usize{0} ** 4} ** 3;
    var nameless = [_][4]usize{[_]usize{0} ** 4} ** 3;
    var reachable = [_][4]usize{[_]usize{0} ** 4} ** 3;
    var sourceless: usize = 0;
    var designator_claims: usize = 0;

    // Every name a live definition carries, per language. One pass over the
    // entities, so the reachability question costs a lookup per claim instead
    // of a scan per claim.
    var defined: std.StringHashMapUnmanaged([3]bool) = .empty;
    defer defined.deinit(gpa);
    var definitions = snapshot.entitiesMatching(.{ .kind = .definition });
    while (definitions.next()) |definition| {
        const name = definition.identity.name orelse continue;
        const language = definition.identity.language orelse continue;
        const slot = try defined.getOrPut(gpa, name);
        if (!slot.found_existing) slot.value_ptr.* = .{ false, false, false };
        slot.value_ptr.*[@intFromEnum(language)] = true;
    }

    for (snapshot.assertions) |assertion| {
        if (assertion.resolution.category() != .unresolved) continue;
        const relationship = assertion.relationship() orelse continue;
        const designator = switch (relationship.target) {
            .designator => |text| text,
            .entity => continue,
        };
        designator_claims += 1;
        const source = snapshot.entityById(relationship.source) orelse {
            sourceless += 1;
            continue;
        };
        const language = source.identity.language orelse {
            sourceless += 1;
            continue;
        };
        const shape = shapeOf(language, designator.name);
        counts[@intFromEnum(language)][@intFromEnum(relationship.kind)][@intFromEnum(shape)] += 1;
        if (designator.qualifier != null) qualified[@intFromEnum(language)][@intFromEnum(relationship.kind)] += 1;
        if (defined.get(designator.name)) |carriers| {
            if (carriers[@intFromEnum(language)]) {
                reachable[@intFromEnum(language)][@intFromEnum(relationship.kind)] += 1;
            }
        }
        if (designator.name.len == 0) nameless[@intFromEnum(language)][@intFromEnum(relationship.kind)] += 1;
    }

    try out.print("root:        {s}\n", .{options.root});
    try out.print("units:       {d} indexed\n", .{scanned.added + scanned.unchanged + scanned.changed});
    try out.print("revision:    {d}\n\n", .{snapshot.revision});

    try out.print("definitions  {d}\n", .{snapshot.countEntities(.{ .kind = .definition })});
    try out.print("assertions   {d} recorded\n", .{snapshot.assertions.len});
    try out.print("  facts       {d}\n", .{snapshot.countAssertions(.{ .resolution = .fact })});
    try out.print("  unresolved  {d}\n", .{snapshot.countUnresolvedAssertions()});
    try out.print("  approximate {d}\n", .{snapshot.countApproximateAssertions()});
    try out.print("  stale       {d}\n", .{snapshot.countAssertions(.{ .freshness = .stale })});
    try out.print("diagnostics  {d}\n\n", .{snapshot.diagnostics.len});

    try out.print("Unresolved claims with a designator target: {d}\n\n", .{designator_claims});
    try out.print("{s:<9} {s:<12} {s:>12} {s:>16} {s:>12} {s:>14} {s:>9} {s:>10}\n", .{
        "language",
        "kind",
        "simple_name",
        "qualified_name",
        "expression",
        "with_qualifier",
        "nameless",
        "reachable",
    });
    for (languages) |language| {
        for (kinds) |kind| {
            const row = counts[@intFromEnum(language)][@intFromEnum(kind)];
            var total: usize = 0;
            for (row) |count| total += count;
            if (total == 0) continue;
            try out.print("{s:<9} {s:<12} {d:>12} {d:>16} {d:>12} {d:>14} {d:>9} {d:>10}\n", .{
                language.tag(),
                @tagName(kind),
                row[@intFromEnum(Shape.simple_name)],
                row[@intFromEnum(Shape.qualified_name)],
                row[@intFromEnum(Shape.expression)],
                qualified[@intFromEnum(language)][@intFromEnum(kind)],
                nameless[@intFromEnum(language)][@intFromEnum(kind)],
                reachable[@intFromEnum(language)][@intFromEnum(kind)],
            });
        }
    }
    if (sourceless != 0) {
        try out.print(
            "\n{d} of them name no source entity this snapshot holds, so no language " ++
                "decides their shape and they are in no row above.\n",
            .{sourceless},
        );
    }

    const adjacency = snapshot.relationship_index.designator;
    try out.print("\nDesignator index\n", .{});
    try out.print("  distinct keys     {d}\n", .{adjacency.spans.count()});
    try out.print("  bucketed positions {d}\n", .{adjacency.positions.len});
    try out.print("  byteSize          {d}\n", .{adjacency.byteSize()});

    var buckets: std.ArrayList(Bucket) = .empty;
    defer buckets.deinit(gpa);
    try buckets.ensureTotalCapacity(gpa, adjacency.spans.count());

    var keys_by_shape = [_]usize{0} ** 3;
    var keys_without_language: usize = 0;

    var entries = adjacency.spans.iterator();
    while (entries.next()) |entry| {
        const key = entry.key_ptr.*;
        const positions = adjacency.bucket(key);
        var language: ?model.Language = null;
        if (positions.len != 0) {
            const first = snapshot.assertions[positions[0]];
            if (first.relationship()) |relationship| {
                if (snapshot.entityById(relationship.source)) |source| {
                    language = source.identity.language;
                }
            }
        }
        if (language) |known| {
            keys_by_shape[@intFromEnum(shapeOf(known, key))] += 1;
        } else {
            keys_without_language += 1;
        }
        buckets.appendAssumeCapacity(.{
            .key = key,
            .positions = positions.len,
            .language = language,
            .definitions = 0,
        });
    }

    try out.print("\n  Keys by shape, in the language of the first claim in each bucket\n", .{});
    for (shapes) |shape| {
        try out.print("    {s:<16} {d}\n", .{ shape.tag(), keys_by_shape[@intFromEnum(shape)] });
    }
    if (keys_without_language != 0) {
        try out.print("    {s:<16} {d}\n", .{ "no language", keys_without_language });
    }

    std.mem.sort(Bucket, buckets.items, {}, largerBucket);
    const shown = buckets.items[0..@min(options.top, buckets.items.len)];
    // Counted for the shown buckets only: a definition lookup walks the entity
    // array, and doing it for every key would make this report quadratic.
    for (shown) |*bucket| {
        bucket.definitions = snapshot.countEntities(.{ .kind = .definition, .name = bucket.key });
    }

    try out.print("\n  The {d} largest buckets\n", .{shown.len});
    try out.print("    {s:>10} {s:>12} {s:<9} {s:<16} {s}\n", .{
        "positions",
        "definitions",
        "language",
        "shape",
        "key",
    });
    for (shown) |bucket| {
        const language = bucket.language;
        try out.print("    {d:>10} {d:>12} {s:<9} {s:<16} {s}\n", .{
            bucket.positions,
            bucket.definitions,
            if (language) |known| known.tag() else "-",
            if (language) |known| shapeOf(known, bucket.key).tag() else "-",
            bucket.key,
        });
    }

    try out.flush();
}
