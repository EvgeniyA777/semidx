//! Zig frontend.
//!
//! Coverage starts narrow on purpose: it grows only where the grammar exposes a
//! construct with exact evidence. Everything outside it is reported as
//! unsupported rather than approximated, and Zig's own vocabulary stays in
//! extension payloads.

const std = @import("std");

const core = @import("semidx_core");
const ts = @import("semidx_tree_sitter");

const model = core.model;
const contract = core.contract;

pub const grammar: ts.Grammar = .zig;

pub const version = std.fmt.comptimePrint("plan-004+ts-abi{d}", .{ts.runtime_abi_version});

pub const capabilities: contract.Capabilities = .{
    .language = .zig,
    .producer = .{ .name = "frontend.zig", .version = version },
    .entity_roles = &.{},
    .relationship_kinds = &.{},
    .coverage_note = "no Zig construct is covered yet; every top-level " ++
        "declaration is reported as unsupported",
};

/// The most distinct uncovered top-level node kinds reported one by one. The
/// rest are still reported, as one count.
const max_reported_kinds: usize = 16;

/// Counts uncovered top-level constructs by node kind, so a unit full of
/// imports yields one diagnostic per kind rather than one per line.
const Uncovered = struct {
    const Entry = struct { kind: []const u8, count: u32 };

    entries: [max_reported_kinds]Entry = undefined,
    len: usize = 0,
    overflow: u32 = 0,

    fn note(self: *Uncovered, kind: []const u8) void {
        for (self.entries[0..self.len]) |*entry| {
            if (std.mem.eql(u8, entry.kind, kind)) {
                entry.count += 1;
                return;
            }
        }
        if (self.len == max_reported_kinds) {
            self.overflow += 1;
            return;
        }
        self.entries[self.len] = .{ .kind = kind, .count = 1 };
        self.len += 1;
    }

    fn report(self: *const Uncovered, builder: *contract.BatchBuilder) !void {
        for (self.entries[0..self.len]) |entry| {
            try builder.addDiagnostic(.unsupported_construct, try builder.print(
                "{d} top-level `{s}` outside this frontend's coverage",
                .{ entry.count, entry.kind },
            ));
        }
        if (self.overflow > 0) {
            try builder.addDiagnostic(.unsupported_construct, try builder.print(
                "{d} further top-level constructs of other kinds outside this frontend's coverage",
                .{self.overflow},
            ));
        }
    }
};

pub fn analyze(
    builder: *contract.BatchBuilder,
    input: contract.FrontendInput,
    tree: ts.Tree,
) !void {
    const root = tree.root();
    if (root.hasError()) {
        try builder.addDiagnostic(
            .analysis_failed,
            "the source unit does not parse cleanly, so no Zig assertions were derived from it",
        );
        return;
    }
    _ = input;

    var uncovered: Uncovered = .{};
    var constructs: usize = 0;
    var members = root.namedChildren();
    while (members.next()) |member| {
        const kind = member.kind();
        if (isComment(kind)) continue;
        constructs += 1;
        uncovered.note(kind);
    }

    try uncovered.report(builder);
    if (constructs == 0) {
        try builder.addDiagnostic(
            .confirmed_absence,
            "the source unit parsed and declares nothing at top level",
        );
    }
}

fn isComment(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "comment");
}
