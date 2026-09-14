//! Zig frontend.
//!
//! Coverage starts narrow on purpose: it grows only where the grammar exposes a
//! construct with exact evidence. Everything outside it is reported as
//! unsupported rather than approximated, and Zig's own vocabulary stays in
//! extension payloads.
//!
//! Covered today:
//!
//! - a named top-level `fn` declaration, as a `function` definition; and
//! - a top-level `const` whose value is written directly as a `struct`,
//!   `enum`, `union`, or `opaque` expression, as a `container` definition.
//!
//! Not covered: other top-level constants and variables (imports, aliases,
//! values), tests, `comptime` blocks, `usingnamespace`, and everything declared
//! inside a container. A container's members are Zig declarations in their own
//! namespace, and nothing here resolves that namespace.

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
    .entity_roles = &.{ "function", "container" },
    .relationship_kinds = &.{.defines},
    .coverage_note = "named top-level `fn` declarations and top-level `const` " ++
        "declarations bound directly to a struct, enum, union, or opaque " ++
        "expression; members of containers and every other declaration are unsupported",
};

/// The most distinct uncovered constructs reported one by one. The rest are
/// still reported, as one count.
const max_reported_kinds: usize = 16;

/// Where an uncovered construct was found.
const Placement = enum { top_level, container_member };

/// Counts uncovered constructs by node kind and placement, so a unit full of
/// imports yields one diagnostic per kind rather than one per line.
const Uncovered = struct {
    const Entry = struct { kind: []const u8, placement: Placement, count: u32 };

    entries: [max_reported_kinds]Entry = undefined,
    len: usize = 0,
    overflow: u32 = 0,

    fn note(self: *Uncovered, kind: []const u8, placement: Placement) void {
        for (self.entries[0..self.len]) |*entry| {
            if (entry.placement == placement and std.mem.eql(u8, entry.kind, kind)) {
                entry.count += 1;
                return;
            }
        }
        if (self.len == max_reported_kinds) {
            self.overflow += 1;
            return;
        }
        self.entries[self.len] = .{ .kind = kind, .placement = placement, .count = 1 };
        self.len += 1;
    }

    fn report(self: *const Uncovered, builder: *contract.BatchBuilder) !void {
        for (self.entries[0..self.len]) |entry| {
            try builder.addDiagnostic(.unsupported_construct, switch (entry.placement) {
                .top_level => try builder.print(
                    "{d} top-level `{s}` outside this frontend's coverage",
                    .{ entry.count, entry.kind },
                ),
                .container_member => try builder.print(
                    "{d} `{s}` declared inside a top-level container, outside this frontend's coverage",
                    .{ entry.count, entry.kind },
                ),
            });
        }
        if (self.overflow > 0) {
            try builder.addDiagnostic(.unsupported_construct, try builder.print(
                "{d} further constructs of other kinds outside this frontend's coverage",
                .{self.overflow},
            ));
        }
    }
};

const container_kinds = [_]struct { node: []const u8, label: []const u8 }{
    .{ .node = "struct_declaration", .label = "struct" },
    .{ .node = "enum_declaration", .label = "enum" },
    .{ .node = "union_declaration", .label = "union" },
    .{ .node = "opaque_declaration", .label = "opaque" },
};

/// A top-level `const` whose value is a container expression, read token by
/// token so the name and the value are the ones the grammar places there.
const ContainerDeclaration = struct {
    name: ts.Node,
    value: ts.Node,
    label: []const u8,
};

pub fn analyze(
    builder: *contract.BatchBuilder,
    input: contract.FrontendInput,
    tree: ts.Tree,
) !void {
    const source = input.unit.bytes;
    const root = tree.root();
    if (root.hasError()) {
        try builder.addDiagnostic(
            .analysis_failed,
            "the source unit does not parse cleanly, so no Zig assertions were derived from it",
        );
        return;
    }

    // Entities are scoped to the unit, not to where the unit currently sits.
    const scope: model.Scope = .{ .unit = input.unit.id };

    var uncovered: Uncovered = .{};
    var definitions: usize = 0;

    var members = root.namedChildren();
    while (members.next()) |member| {
        const kind = member.kind();
        if (isComment(kind)) continue;

        if (std.mem.eql(u8, kind, "function_declaration")) {
            const name_node = member.childByFieldName("name") orelse {
                uncovered.note(kind, .top_level);
                continue;
            };
            const name = try builder.dupe(name_node.text(source));
            const index = try addDefinition(builder, scope, member, name, "function", &.{
                .{ .key = "zig.construct", .value = "function" },
            }, "named top-level `fn` declaration in the analyzed source unit");
            try addDefines(builder, member, name, index);
            definitions += 1;
            continue;
        }

        if (std.mem.eql(u8, kind, "variable_declaration")) {
            const declaration = containerDeclaration(member) orelse {
                uncovered.note(kind, .top_level);
                continue;
            };
            const name = try builder.dupe(declaration.name.text(source));
            const index = try addDefinition(builder, scope, member, name, "container", &.{
                .{ .key = "zig.construct", .value = "container" },
                .{ .key = "zig.container", .value = declaration.label },
            }, "top-level `const` bound directly to a container expression in the analyzed source unit");
            try addDefines(builder, member, name, index);
            definitions += 1;

            var inner = declaration.value.namedChildren();
            while (inner.next()) |inner_member| {
                if (isComment(inner_member.kind())) continue;
                uncovered.note(inner_member.kind(), .container_member);
            }
            continue;
        }

        uncovered.note(kind, .top_level);
    }

    try uncovered.report(builder);
    if (definitions == 0) {
        try builder.addDiagnostic(
            .confirmed_absence,
            "the source unit parsed and declares no top-level function or container",
        );
    }
}

fn addDefinition(
    builder: *contract.BatchBuilder,
    scope: model.Scope,
    node: ts.Node,
    name: []const u8,
    role: []const u8,
    labels: []const model.ExtensionLabel,
    method: []const u8,
) !u32 {
    return builder.addEntity(.{
        .kind = .definition,
        .identity = .{
            .scope = scope,
            .language = .zig,
            .role = role,
            .name = name,
            // Zig has no overloading: a name is unique among the declarations
            // of one container, so a parameter edit is not a new definition.
            .signature = null,
            .container_path = &.{},
        },
        .evidence = evidenceOf(builder, node, name),
        .extension = .{
            .namespace = "zig",
            .labels = try builder.labels(labels),
        },
        .resolution = .{ .fact = .{ .method = method } },
    });
}

fn addDefines(builder: *contract.BatchBuilder, node: ts.Node, name: []const u8, index: u32) !void {
    try builder.addRelationship(.{
        .kind = .defines,
        .source = .unit_container,
        .target = .{ .local = index },
        .evidence = evidenceOf(builder, node, name),
        .resolution = .{ .fact = .{
            .method = "declared directly at the top level of this source unit",
        } },
    });
}

/// Reads `[pub] const <identifier> [: type] = <container expression>;` from
/// the declaration's tokens in order. Returns null for anything else: `var`,
/// `extern` declarations without a value, and values that only evaluate to a
/// container (a call, an `if`, an alias) are not declarations of one.
fn containerDeclaration(node: ts.Node) ?ContainerDeclaration {
    var is_const = false;
    var name: ?ts.Node = null;
    var after_equals = false;

    const count = node.childCount();
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const token = node.childAt(index) orelse continue;
        const kind = token.kind();
        if (isComment(kind)) continue;

        if (after_equals) {
            // The first node after `=` is the whole value expression.
            if (!token.isNamed()) return null;
            const label = containerLabel(kind) orelse return null;
            if (!is_const) return null;
            return .{ .name = name orelse return null, .value = token, .label = label };
        }

        if (!token.isNamed()) {
            if (std.mem.eql(u8, kind, "const")) {
                is_const = true;
            } else if (std.mem.eql(u8, kind, "=")) {
                after_equals = true;
            }
            continue;
        }
        if (name == null and std.mem.eql(u8, kind, "identifier")) name = token;
    }
    return null;
}

fn containerLabel(kind: []const u8) ?[]const u8 {
    for (container_kinds) |entry| {
        if (std.mem.eql(u8, entry.node, kind)) return entry.label;
    }
    return null;
}

fn isComment(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "comment");
}

fn evidenceOf(
    builder: *contract.BatchBuilder,
    node: ts.Node,
    text: []const u8,
) model.SourceEvidence {
    const range = node.range();
    return .{
        .unit = builder.unit,
        .range = .{
            .start_byte = range.start_byte,
            .end_byte = range.end_byte,
            .start_row = range.start_row,
            .start_column = range.start_column,
            .end_row = range.end_row,
            .end_column = range.end_column,
        },
        .text = text,
    };
}
