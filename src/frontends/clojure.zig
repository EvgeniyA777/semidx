//! Fixture-scoped Clojure frontend.
//!
//! The grammar is deliberately shallow: every form is a list, and what a form
//! means is the frontend's interpretation, not the parser's. That makes this
//! the useful second language family for the slice — namespaces, vars, and
//! forms must stay Clojure's own vocabulary in extension payloads while the
//! shared core still answers what exists and what refers to what.

const std = @import("std");

const core = @import("semidx_core");
const ts = @import("semidx_tree_sitter");

const model = core.model;
const contract = core.contract;

pub const grammar: ts.Grammar = .clojure;

pub const version = std.fmt.comptimePrint("slice-001+ts-abi{d}", .{ts.runtime_abi_version});

pub const capabilities: contract.Capabilities = .{
    .language = .clojure,
    .producer = .{ .name = "frontend.clojure", .version = version },
    .entity_roles = &.{ "namespace", "def", "defn" },
    .relationship_kinds = &.{ .defines, .references, .calls },
    .coverage_note = "a single `ns` form, top-level `def` and `defn` forms, " ++
        "and the symbols their bodies designate",
};

/// Guards against unbounded recursion on pathological input. Exceeding it is
/// reported as an unsupported construct, never as an absence of references.
const max_depth: u32 = 64;

/// The number of values a single form may carry before this frontend stops
/// reading it. Forms are small; a larger one is reported, not truncated
/// silently.
const max_values: u32 = 4096;

const DefInfo = struct {
    index: u32,
    name: []const u8,
    role: []const u8,
    node: ts.Node,
};

/// Iterates the named children of a form that carry values, dropping comments
/// and reader metadata.
const ValueIterator = struct {
    children: ts.Node.NamedChildIterator,

    fn next(self: *ValueIterator) ?ts.Node {
        while (self.children.next()) |child| {
            const kind = child.kind();
            if (std.mem.indexOf(u8, kind, "comment") != null) continue;
            if (std.mem.indexOf(u8, kind, "meta") != null) continue;
            return child;
        }
        return null;
    }
};

fn values(node: ts.Node) ValueIterator {
    return .{ .children = node.namedChildren() };
}

fn valueAt(node: ts.Node, position: u32) ?ts.Node {
    var iterator = values(node);
    var index: u32 = 0;
    while (iterator.next()) |value| : (index += 1) {
        if (index == position) return value;
    }
    return null;
}

fn valueCount(node: ts.Node) u32 {
    var iterator = values(node);
    var count: u32 = 0;
    while (iterator.next()) |_| count += 1;
    return count;
}

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
            "the source unit does not parse cleanly, so no Clojure assertions were derived from it",
        );
        return;
    }

    const gpa = builder.gpa;
    // Entities are scoped to the unit, not to where the unit currently sits.
    const scope: model.Scope = .{ .unit = input.unit.id };

    // The namespace is resolved first so that a definition's containment does
    // not depend on the order forms happen to appear in.
    var namespace_name: []const u8 = "";
    var namespace_node: ?ts.Node = null;
    {
        var forms = root.namedChildren();
        while (forms.next()) |form| {
            if (!std.mem.eql(u8, form.kind(), "list_lit")) continue;
            const head = headSymbol(form, source) orelse continue;
            if (!std.mem.eql(u8, head, "ns")) continue;
            const name_node = valueAt(form, 1) orelse continue;
            namespace_name = try builder.dupe(name_node.text(source));
            namespace_node = form;
            break;
        }
    }

    var namespace_index: ?u32 = null;
    if (namespace_node) |form| {
        namespace_index = try builder.addEntity(.{
            .kind = .definition,
            .identity = .{
                .scope = scope,
                .language = .clojure,
                .role = "namespace",
                .name = namespace_name,
                .signature = null,
                .container_path = &.{},
            },
            .evidence = evidenceOf(builder, form, namespace_name),
            .extension = .{
                .namespace = "clojure",
                .labels = try builder.labels(&.{
                    .{ .key = "clojure.form", .value = "ns" },
                    .{ .key = "clojure.namespace", .value = namespace_name },
                }),
            },
            .resolution = .{ .fact = .{
                .method = "`ns` form in the analyzed source unit",
            } },
        });
    } else {
        try builder.addDiagnostic(
            .confirmed_absence,
            "the source unit parsed and declares no `ns` form",
        );
    }

    var defs: std.ArrayList(DefInfo) = .empty;
    defer defs.deinit(gpa);

    const container_path = if (namespace_index != null)
        try builder.dupeSlice(&.{namespace_name})
    else
        &.{};

    // Pass 1: definitions.
    var forms = root.namedChildren();
    while (forms.next()) |form| {
        const kind = form.kind();
        if (std.mem.eql(u8, kind, "comment")) continue;
        if (!std.mem.eql(u8, kind, "list_lit")) {
            try builder.addDiagnostic(.unsupported_construct, try builder.print(
                "a top-level `{s}` is outside this frontend's coverage",
                .{kind},
            ));
            continue;
        }

        if (valueCount(form) >= max_values) {
            try builder.addDiagnostic(
                .unsupported_construct,
                "a form with more values than this frontend reads was not analyzed",
            );
            continue;
        }

        const head = headSymbol(form, source) orelse {
            try builder.addDiagnostic(
                .unsupported_construct,
                "a top-level form whose head is not a symbol is outside this frontend's coverage",
            );
            continue;
        };

        if (std.mem.eql(u8, head, "ns")) continue;

        const role = definitionRole(head) orelse {
            try builder.addDiagnostic(.unsupported_construct, try builder.print(
                "the top-level form `({s} ...)` is outside this frontend's coverage",
                .{head},
            ));
            continue;
        };

        const name_node = valueAt(form, 1) orelse {
            try builder.addDiagnostic(.unsupported_construct, try builder.print(
                "a `{s}` form without a name is outside this frontend's coverage",
                .{head},
            ));
            continue;
        };
        const name = try builder.dupe(name_node.text(source));
        const signature = try definitionSignature(builder, form, role, name);

        const index = try builder.addEntity(.{
            .kind = .definition,
            .identity = .{
                .scope = scope,
                .language = .clojure,
                .role = role,
                .name = name,
                .signature = signature,
                .container_path = container_path,
            },
            .evidence = evidenceOf(builder, form, name),
            .extension = .{
                .namespace = "clojure",
                .labels = try builder.labels(&.{
                    .{ .key = "clojure.form", .value = head },
                    .{ .key = "clojure.namespace", .value = namespace_name },
                    .{ .key = "clojure.var", .value = "true" },
                }),
            },
            .resolution = .{ .fact = .{
                .method = "top-level definition form in the analyzed source unit",
            } },
        });

        try defs.append(gpa, .{ .index = index, .name = name, .role = role, .node = form });
    }

    if (defs.items.len == 0) {
        try builder.addDiagnostic(
            .confirmed_absence,
            "the source unit parsed and declares no `def` or `defn` form",
        );
    }

    // Pass 2: relationships.
    if (namespace_index) |index| {
        try builder.addRelationship(.{
            .kind = .defines,
            .source = .unit_container,
            .target = .{ .local = index },
            .evidence = evidenceOf(builder, namespace_node.?, namespace_name),
            .resolution = .{ .fact = .{
                .method = "declared directly in this source unit",
            } },
        });
    }

    for (defs.items) |def| {
        try builder.addRelationship(.{
            .kind = .defines,
            .source = if (namespace_index) |index|
                .{ .entity = index }
            else
                .unit_container,
            .target = .{ .local = def.index },
            .evidence = evidenceOf(builder, def.node, def.name),
            .resolution = .{ .fact = .{
                .method = if (namespace_index != null)
                    "declared directly in this namespace"
                else
                    "declared directly in this source unit",
            } },
        });

        var body_index = bodyStart(def.node, def.role);
        while (valueAt(def.node, body_index)) |form| : (body_index += 1) {
            try walkForm(builder, source, def, form, defs.items, 0);
        }
    }
}

fn definitionRole(head: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, head, "def")) return "def";
    if (std.mem.eql(u8, head, "defn")) return "defn";
    if (std.mem.eql(u8, head, "defn-")) return "defn";
    return null;
}

/// Where a definition's body begins. A `defn`'s parameter vector introduces
/// bindings rather than designating anything, so it is not walked.
fn bodyStart(node: ts.Node, role: []const u8) u32 {
    if (!std.mem.eql(u8, role, "defn")) return 2;
    var index: u32 = 2;
    while (valueAt(node, index)) |value| : (index += 1) {
        if (std.mem.eql(u8, value.kind(), "vec_lit")) return index + 1;
    }
    return 2;
}

fn definitionSignature(
    builder: *contract.BatchBuilder,
    node: ts.Node,
    role: []const u8,
    name: []const u8,
) !?[]const u8 {
    if (!std.mem.eql(u8, role, "defn")) return null;
    var index: u32 = 2;
    while (valueAt(node, index)) |value| : (index += 1) {
        if (!std.mem.eql(u8, value.kind(), "vec_lit")) continue;
        return try builder.print("{s}/{d}", .{ name, value.namedChildCount() });
    }
    return null;
}

fn walkForm(
    builder: *contract.BatchBuilder,
    source: []const u8,
    def: DefInfo,
    node: ts.Node,
    defs: []const DefInfo,
    depth: u32,
) !void {
    if (depth >= max_depth) {
        try builder.addDiagnostic(
            .unsupported_construct,
            "a form nested deeper than this frontend traverses was not analyzed for references",
        );
        return;
    }

    const kind = node.kind();

    if (std.mem.eql(u8, kind, "sym_lit")) {
        try emitDesignation(builder, source, def, node, defs, .references);
        return;
    }

    if (std.mem.eql(u8, kind, "list_lit")) {
        var iterator = values(node);
        var position: u32 = 0;
        while (iterator.next()) |value| : (position += 1) {
            if (position == 0 and std.mem.eql(u8, value.kind(), "sym_lit")) {
                // Head position invokes; every other symbol only designates.
                try emitDesignation(builder, source, def, value, defs, .calls);
                continue;
            }
            try walkForm(builder, source, def, value, defs, depth + 1);
        }
        return;
    }

    if (std.mem.eql(u8, kind, "vec_lit") or
        std.mem.eql(u8, kind, "map_lit") or
        std.mem.eql(u8, kind, "set_lit"))
    {
        var children = node.namedChildren();
        while (children.next()) |child| {
            try walkForm(builder, source, def, child, defs, depth + 1);
        }
    }
}

fn emitDesignation(
    builder: *contract.BatchBuilder,
    source: []const u8,
    def: DefInfo,
    node: ts.Node,
    defs: []const DefInfo,
    kind: model.RelationshipKind,
) !void {
    const name = try builder.dupe(node.text(source));
    if (name.len == 0) return;
    const resolved = findDef(defs, name);

    try builder.addRelationship(.{
        .kind = kind,
        .source = .{ .entity = def.index },
        .target = if (resolved) |index| .{ .local = index } else .{ .designator = name },
        .evidence = evidenceOf(builder, node, name),
        .resolution = if (resolved != null)
            .{ .fact = .{
                .method = "symbol naming a definition in the analyzed source unit",
            } }
        else
            .{ .unresolved = .{
                .missing = .target_entity,
                .explanation = "the symbol names nothing defined in the analyzed source unit",
            } },
    });
}

fn findDef(defs: []const DefInfo, name: []const u8) ?u32 {
    for (defs) |def| {
        if (std.mem.eql(u8, def.name, name)) return def.index;
    }
    return null;
}

fn headSymbol(node: ts.Node, source: []const u8) ?[]const u8 {
    const head = valueAt(node, 0) orelse return null;
    if (!std.mem.eql(u8, head.kind(), "sym_lit")) return null;
    return head.text(source);
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
