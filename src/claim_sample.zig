//! Developer-only measurement command: sample definitions and classify every
//! outgoing claim they make.
//!
//! It exists so that an external measurement can be repeated by someone who has
//! only this repository and a clone of the measured project. Plan 012's numbers
//! came from a script that was written twice and kept neither time, which is the
//! gap [Follow-up 017](../docs/followups/017_plan_012_external_evidence_reproducibility.md)
//! records.
//!
//! It is not a lane and not a conformance check. `zig build test`,
//! `zig build test-mcp`, `zig build dogfood` and `zig build preview-gate` do not
//! build it, and no test asserts against its output.
//!
//! **The sample is reproducible from the seed alone, without this program:**
//!
//!     key  = "<unit path>\n<start line>\n<role>\n<name>"   for every definition
//!     rank = sha256(seed ++ "\n" ++ key), lowercase hex
//!     the sample is the first `size` definitions ordered by (rank, key)
//!
//! No random number generator takes part, so a reimplementation in any language
//! draws the same definitions from the same seed. The seed is compared as bytes.
//!
//! It reads the published snapshot rather than the MCP preview. The preview is a
//! projection of that snapshot, so the claims are the same ones, but a budget
//! can truncate an answer and a measurement should not have to reason about
//! where a page ended.
//!
//! Every unresolved call falls in exactly one reason family. One that matches
//! no family is counted as `unclassified` and its explanation printed, and the
//! report says whether the families sum to the whole. A decomposition whose
//! parts do not sum to its whole has a family missing from it, and that is the
//! failure this makes impossible rather than unlikely.

const std = @import("std");
const semidx = @import("semidx");

const model = semidx.model;

/// One reason family, named by a fragment of the frontend's own explanation.
///
/// Tried in order: a claim takes the first family whose fragment it contains,
/// so a fragment that is a substring of another must come after it. Because the
/// fragments are the frontend's words, rewording a reason in
/// `src/frontends/java.zig` moves its claims to `unclassified`, where they are
/// visible, rather than losing them quietly.
const Family = struct {
    name: []const u8,
    fragment: []const u8,
};

const java_families = [_]Family{
    // Qualified by something that is not a simple name.
    .{ .name = "receiver_not_simple_name", .fragment = "qualified by a receiver this frontend does not resolve" },
    .{ .name = "nested_class_body", .fragment = "class body declared in the method" },
    // A simple name something else claims.
    // A receiver that is a value, since Plan 014 Stage 5. The binding decides
    // the type, and each way that can fail is its own family.
    .{ .name = "value_uncovered_introducer", .fragment = "bound here by a construct this frontend reads no type from" },
    .{ .name = "value_uncovered_type", .fragment = "declared here with a type this frontend does not read" },
    .{ .name = "value_type_unresolved", .fragment = "is not read as a type:" },
    .{ .name = "value_type_shape_not_read", .fragment = "names a type whose current shape this analysis did not read" },
    .{ .name = "value_target_supertypes", .fragment = "declares supertypes this analysis did not read" },
    .{ .name = "value_target_chain_open", .fragment = "declares supertypes and" },
    .{ .name = "value_target_chain_declares", .fragment = "supertype chain declares a method of this name" },
    .{ .name = "value_target_supertypes_unknown", .fragment = "carries no record of whether it declares supertypes, so a method" },
    .{ .name = "value_target_no_method", .fragment = "is declared by the receiver's declared type" },
    .{ .name = "value_target_overloaded", .fragment = "are declared by the receiver's declared type" },
    .{ .name = "value_target_inaccessible", .fragment = "outside the access this frontend resolves through a value receiver" },
    // The family those eleven replace. It reads zero once Stage 5 ships.
    .{ .name = "receiver_bound", .fragment = "is declared here as a binding, so it is read as a value" },
    .{ .name = "on_demand_static_import", .fragment = "imports static members on demand" },
    // The chain declines Plan 014 Stage 3 added, one per condition that can
    // leave a hierarchy open. They come before `enclosing_supertypes` because
    // that family's fragment is a substring of the receiver-side wording: the
    // sentence still says what was being ruled out, and these say why the chain
    // could not rule it out.
    .{ .name = "chain_supertype_unresolved", .fragment = "supertypes and one of them is not resolved" },
    .{ .name = "chain_not_read", .fragment = "supertypes and this analysis did not read what one of them reaches" },
    .{ .name = "chain_ambiguous", .fragment = "supertypes and one of them is ambiguous" },
    .{ .name = "chain_out_of_scope", .fragment = "supertypes and one of them is declared outside this unit's visibility scope" },
    .{ .name = "chain_above_unresolved", .fragment = "supertypes and a supertype somewhere in its chain is not resolved" },
    .{ .name = "chain_not_a_type", .fragment = "supertypes and a supertype somewhere in its chain is not a Java class or interface" },
    .{ .name = "chain_provider_stale", .fragment = "supertypes and a type in its chain is declared in a unit whose analysis is not current" },
    .{ .name = "chain_cycle", .fragment = "supertypes and its declared chain contains a cycle" },
    .{ .name = "chain_too_deep", .fragment = "supertypes and its declared chain is deeper than this analysis walks" },
    .{ .name = "chain_declares_name", .fragment = "supertype chain declares" },
    // The two families the chain declines replace. They read zero once Stage 3
    // ships, and they stay in the table so that is visible rather than assumed.
    .{ .name = "enclosing_supertypes", .fragment = "a field it may inherit" },
    .{ .name = "receiver_reaches_no_class", .fragment = "the receiver is not read as a class" },
    // The receiver is a class; the target is not established.
    .{ .name = "target_supertypes", .fragment = "declares supertypes, so a method of this name it may inherit" },
    .{ .name = "target_supertypes_unknown", .fragment = "carries no record of whether it declares supertypes" },
    .{ .name = "target_shape_not_read", .fragment = "whose current shape this analysis did not read" },
    .{ .name = "target_no_method", .fragment = "declares no method of this name" },
    .{ .name = "target_overloaded", .fragment = "methods of this name, and overloads are not resolved" },
    .{ .name = "target_not_static", .fragment = "is not static, so naming it through the class" },
    .{ .name = "target_static_unrecorded", .fragment = "carries no record of whether it is `static`" },
    .{ .name = "target_inaccessible", .fragment = "outside the access this frontend resolves across classes" },
    // Unqualified invocations, which the static-call rule never touched.
    .{ .name = "unqualified_no_method", .fragment = "no method of this name is declared in the enclosing class" },
    .{ .name = "unqualified_overloaded", .fragment = "methods of this name are declared in the enclosing class" },
    .{ .name = "unqualified_supertypes", .fragment = "a method of this name it may inherit could be the target" },
};

fn familiesFor(language: model.Language) []const Family {
    return switch (language) {
        .java => &java_families,
        // No other frontend has had its reasons decomposed yet. Its claims all
        // land in `unclassified` with their explanations printed, which is the
        // honest answer and a readable starting point for writing the families.
        .clojure, .zig => &.{},
    };
}

/// One definition, reduced to what the sample key is built from.
const Definition = struct {
    id: model.EntityId,
    path: []const u8,
    line: u32,
    role: []const u8,
    name: []const u8,
    /// `sha256(seed ++ "\n" ++ key)` as lowercase hex.
    rank: [64]u8,
    key: []const u8,
};

fn rankOf(seed: []const u8, key: []const u8) [64]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(seed);
    hash.update("\n");
    hash.update(key);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hash.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

fn lessByRank(_: void, a: Definition, b: Definition) bool {
    return switch (std.mem.order(u8, &a.rank, &b.rank)) {
        .lt => true,
        .gt => false,
        .eq => std.mem.order(u8, a.key, b.key) == .lt,
    };
}

fn classify(families: []const Family, explanation: []const u8) ?usize {
    for (families, 0..) |family, at| {
        if (std.mem.indexOf(u8, explanation, family.fragment) != null) return at;
    }
    return null;
}

fn languageFromTag(tag: []const u8) ?model.Language {
    for (std.enums.values(model.Language)) |language| {
        if (std.mem.eql(u8, language.tag(), tag)) return language;
    }
    return null;
}

const Options = struct {
    root: []const u8 = "",
    seed: []const u8 = "20260918",
    size: usize = 1200,
    language: model.Language = .java,
};

const usage =
    \\usage: semidx-claim-sample --root <dir> [--seed <string>] [--size <n>] [--language <java|clojure|zig>]
    \\
    \\Indexes <dir>, draws a reproducible sample of its definitions, and reports
    \\what their outgoing claims say. See the header of src/claim_sample.zig for
    \\the sampling rule, which does not depend on this program.
    \\
;

fn parseOptions(arguments: anytype) !Options {
    var options: Options = .{};
    while (arguments.next()) |argument| {
        if (std.mem.eql(u8, argument, "--root")) {
            options.root = arguments.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, argument, "--seed")) {
            options.seed = arguments.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, argument, "--size")) {
            const value = arguments.next() orelse return error.MissingValue;
            options.size = std.fmt.parseInt(usize, value, 10) catch return error.BadSize;
        } else if (std.mem.eql(u8, argument, "--language")) {
            const value = arguments.next() orelse return error.MissingValue;
            options.language = languageFromTag(value) orelse return error.UnknownLanguage;
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

    var population: std.ArrayList(Definition) = .empty;
    defer {
        for (population.items) |definition| gpa.free(definition.key);
        population.deinit(gpa);
    }

    var entities = snapshot.entitiesMatching(.{ .kind = .definition, .language = options.language });
    while (entities.next()) |entity| {
        const evidence = entity.evidence orelse continue;
        const unit = snapshot.unit(evidence.unit) orelse continue;
        const role = entity.identity.role;
        const name = entity.identity.name orelse continue;
        const key = try std.fmt.allocPrint(gpa, "{s}\n{d}\n{s}\n{s}", .{
            unit.path,
            evidence.range.start_row,
            role,
            name,
        });
        errdefer gpa.free(key);
        try population.append(gpa, .{
            .id = entity.id,
            .path = unit.path,
            .line = evidence.range.start_row,
            .role = role,
            .name = name,
            .rank = rankOf(options.seed, key),
            .key = key,
        });
    }

    if (population.items.len == 0) {
        try out.print("no {s} definitions under {s}\n", .{ options.language.tag(), options.root });
        try out.flush();
        return error.EmptyPopulation;
    }

    std.mem.sort(Definition, population.items, {}, lessByRank);
    const sampled = population.items[0..@min(options.size, population.items.len)];

    const kinds = std.enums.values(model.RelationshipKind);
    const categories = std.enums.values(model.ResolutionCategory);
    var totals = [_][3]usize{[_]usize{0} ** 3} ** 8;

    const families = familiesFor(options.language);
    var family_counts = try gpa.alloc(usize, families.len);
    defer gpa.free(family_counts);
    @memset(family_counts, 0);

    var unclassified: std.StringHashMapUnmanaged(usize) = .empty;
    defer unclassified.deinit(gpa);

    var claims: usize = 0;
    for (sampled) |definition| {
        var outgoing = snapshot.relationships(.{ .source = definition.id });
        while (outgoing.next()) |claim| {
            claims += 1;
            const kind = @intFromEnum(claim.claim.relationship.kind);
            const category = @intFromEnum(claim.resolution.category());
            totals[kind][category] += 1;
            if (claim.claim.relationship.kind != .calls) continue;
            const explanation = switch (claim.resolution) {
                .unresolved => |unresolved| unresolved.explanation,
                else => continue,
            };
            if (classify(families, explanation)) |at| {
                family_counts[at] += 1;
            } else {
                const slot = try unclassified.getOrPut(gpa, explanation);
                if (!slot.found_existing) slot.value_ptr.* = 0;
                slot.value_ptr.* += 1;
            }
        }
    }

    try out.print("root:        {s}\n", .{options.root});
    try out.print("language:    {s}\n", .{options.language.tag()});
    try out.print("seed:        {s}\n", .{options.seed});
    try out.print("units:       {d} indexed\n", .{scanned.added + scanned.unchanged + scanned.changed});
    try out.print("population:  {d} definitions\n", .{population.items.len});
    try out.print("sample:      {d} definitions\n", .{sampled.len});
    try out.print("revision:    {d}\n\n", .{snapshot.revision});

    try out.print("Sampled outgoing claims: {d}\n\n", .{claims});
    try out.print("{s:<14} {s:<12} {s:>8}\n", .{ "kind", "resolution", "count" });
    for (kinds) |kind| {
        for (categories) |category| {
            const count = totals[@intFromEnum(kind)][@intFromEnum(category)];
            if (count == 0) continue;
            try out.print("{s:<14} {s:<12} {d:>8}\n", .{ @tagName(kind), @tagName(category), count });
        }
    }

    const unresolved_calls = totals[@intFromEnum(model.RelationshipKind.calls)][@intFromEnum(model.ResolutionCategory.unresolved)];
    try out.print("\nUnresolved `calls` by reason family: {d}\n\n", .{unresolved_calls});
    try out.print("{s:<28} {s:>8}\n", .{ "family", "count" });
    var counted: usize = 0;
    for (families, family_counts) |family, count| {
        counted += count;
        try out.print("{s:<28} {d:>8}\n", .{ family.name, count });
    }
    var unclassified_total: usize = 0;
    var missed = unclassified.iterator();
    while (missed.next()) |entry| unclassified_total += entry.value_ptr.*;
    counted += unclassified_total;
    try out.print("{s:<28} {d:>8}\n", .{ "unclassified", unclassified_total });

    if (counted == unresolved_calls) {
        try out.print("\nThe families sum to the whole: {d} = {d}.\n", .{ counted, unresolved_calls });
    } else {
        try out.print("\nMISMATCH: families sum to {d}, unresolved calls are {d}.\n", .{ counted, unresolved_calls });
    }

    if (unclassified.count() != 0) {
        try out.print("\nExplanations no family matched:\n", .{});
        // Sorted by explanation so two runs print the same order: a hash map's
        // iteration order is not part of a measurement.
        var explanations: std.ArrayList([]const u8) = .empty;
        defer explanations.deinit(gpa);
        var keys = unclassified.keyIterator();
        while (keys.next()) |key| try explanations.append(gpa, key.*);
        std.mem.sort([]const u8, explanations.items, {}, lessByText);
        for (explanations.items) |explanation| {
            try out.print("  {d:>6}  {s}\n", .{ unclassified.get(explanation).?, explanation });
        }
    }

    try out.flush();
    if (counted != unresolved_calls) return error.DecompositionIncomplete;
}

fn lessByText(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}
