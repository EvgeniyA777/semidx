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
        "and the symbols their bodies designate; a symbol resolves to the unit's " ++
        "one definition of that name only where no parameter, duplicate " ++
        "declaration, or form that could be a binding macro may give it another " ++
        "meaning",
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
    /// Names the definition's parameter vector binds, at any destructuring
    /// depth.
    params: []const []const u8,
    /// False for a multi-arity `defn`, whose per-arity parameters are not read,
    /// so no name in its body can be ruled out as a parameter.
    body_known: bool,
};

/// What a symbol in a definition body can be resolved against.
const UnitNames = struct {
    defs: []const DefInfo,
    /// The name of every top-level `def`-like form, covered or not, so a
    /// `defmacro` or a second `defn` of a name is not skipped over to reach a
    /// covered definition.
    declared: []const []const u8,
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

    var declared: std.ArrayList([]const u8) = .empty;
    defer declared.deinit(gpa);
    {
        var candidates = root.namedChildren();
        while (candidates.next()) |form| {
            if (!std.mem.eql(u8, form.kind(), "list_lit")) continue;
            const head = headSymbol(form, source) orelse continue;
            if (!std.mem.startsWith(u8, head, "def")) continue;
            const name_node = valueAt(form, 1) orelse continue;
            if (!std.mem.eql(u8, name_node.kind(), "sym_lit")) continue;
            try declared.append(gpa, name_node.text(source));
        }
    }

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

        const body = bodyStart(form, role);
        var params: std.ArrayList([]const u8) = .empty;
        if (body.params) |vector| try collectSymbols(builder, source, vector, &params, 0);
        try defs.append(gpa, .{
            .index = index,
            .name = name,
            .role = role,
            .node = form,
            .params = params.items,
            .body_known = !std.mem.eql(u8, role, "defn") or body.params != null,
        });
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

        const names: UnitNames = .{ .defs = defs.items, .declared = declared.items };
        var body_index = bodyStart(def.node, def.role).index;
        while (valueAt(def.node, body_index)) |form| : (body_index += 1) {
            try walkForm(builder, source, def, form, names, true, 0);
        }
    }
}

fn definitionRole(head: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, head, "def")) return "def";
    if (std.mem.eql(u8, head, "defn")) return "defn";
    if (std.mem.eql(u8, head, "defn-")) return "defn";
    return null;
}

const BodyStart = struct {
    index: u32,
    /// The `defn`'s parameter vector, when it has a single one.
    params: ?ts.Node,
};

/// Where a definition's body begins. A `defn`'s parameter vector introduces
/// bindings rather than designating anything, so it is not walked.
fn bodyStart(node: ts.Node, role: []const u8) BodyStart {
    if (!std.mem.eql(u8, role, "defn")) return .{ .index = 2, .params = null };
    var index: u32 = 2;
    while (valueAt(node, index)) |value| : (index += 1) {
        if (std.mem.eql(u8, value.kind(), "vec_lit")) return .{ .index = index + 1, .params = value };
    }
    return .{ .index = 2, .params = null };
}

/// Every symbol inside a parameter vector, at any depth: destructuring binds
/// names inside nested vectors and maps.
fn collectSymbols(
    builder: *contract.BatchBuilder,
    source: []const u8,
    node: ts.Node,
    out: *std.ArrayList([]const u8),
    depth: u32,
) !void {
    if (depth >= max_depth) return;
    if (std.mem.eql(u8, node.kind(), "sym_lit")) {
        try out.append(builder.allocator(), try builder.dupe(node.text(source)));
        return;
    }
    var children = node.namedChildren();
    while (children.next()) |child| try collectSymbols(builder, source, child, out, depth + 1);
}

/// Special forms that bind no names and cannot be redefined, so the forms
/// under them are evaluated as written.
fn bindsNothing(head: []const u8) bool {
    return std.mem.eql(u8, head, "do") or std.mem.eql(u8, head, "if");
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

/// `known` is whether every form enclosing `node` inside the body is one this
/// frontend knows binds no names: a call of the unit's own definition, `do`,
/// `if`, a collection literal, or an application whose head is not a symbol
/// (only a symbol can name a macro). Under any other form, such as `let`, `fn`,
/// or a macro from another namespace, a symbol may be a local binding.
fn walkForm(
    builder: *contract.BatchBuilder,
    source: []const u8,
    def: DefInfo,
    node: ts.Node,
    names: UnitNames,
    known: bool,
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
        _ = try emitDesignation(builder, source, def, node, names, .references, known);
        return;
    }

    if (std.mem.eql(u8, kind, "list_lit")) {
        var iterator = values(node);
        var position: u32 = 0;
        var inner = known;
        while (iterator.next()) |value| : (position += 1) {
            if (position == 0 and std.mem.eql(u8, value.kind(), "sym_lit")) {
                // Head position invokes; every other symbol only designates.
                const head_is_fact = try emitDesignation(builder, source, def, value, names, .calls, known);
                inner = known and (head_is_fact or bindsNothing(value.text(source)));
                continue;
            }
            try walkForm(builder, source, def, value, names, inner, depth + 1);
        }
        return;
    }

    if (std.mem.eql(u8, kind, "vec_lit") or
        std.mem.eql(u8, kind, "map_lit") or
        std.mem.eql(u8, kind, "set_lit"))
    {
        var children = node.namedChildren();
        while (children.next()) |child| {
            try walkForm(builder, source, def, child, names, known, depth + 1);
        }
    }
}

fn emitDesignation(
    builder: *contract.BatchBuilder,
    source: []const u8,
    def: DefInfo,
    node: ts.Node,
    names: UnitNames,
    kind: model.RelationshipKind,
    known: bool,
) !bool {
    const name = try builder.dupe(node.text(source));
    if (name.len == 0) return false;
    const resolved = decideSymbol(def, names, name, known);

    try builder.addRelationship(.{
        .kind = kind,
        .source = .{ .entity = def.index },
        .target = if (resolved.index) |index| .{ .local = index } else .{ .designator = designatorOf(name) },
        .evidence = evidenceOf(builder, node, name),
        .resolution = if (resolved.index != null)
            .{ .fact = .{
                .method = "symbol naming the unit's one definition of that name, where nothing may bind it locally",
            } }
        else
            .{ .unresolved = .{ .missing = .target_entity, .explanation = resolved.unresolved } },
    });
    return resolved.index != null;
}

/// The parts of a symbol this frontend could not resolve.
///
/// A Clojure symbol writes its scope in front of a `/`, and that scope is a
/// namespace or a namespace alias — never a value expression — so `str/join` is
/// recorded as the name `join` qualified by `str`. The slash is taken as a
/// separator only when names stand on both sides of it, which leaves the symbol
/// `/` itself, and anything shaped like it, a name.
///
/// No substring of a name is re-read anywhere else: this is the producer saying
/// what it read, once ([ADR 010](../../docs/adr/010_designator_is_a_structured_name.md)).
fn designatorOf(symbol: []const u8) model.Designator {
    const cut = std.mem.indexOfScalar(u8, symbol, '/') orelse return .{ .name = symbol };
    if (cut == 0 or cut + 1 == symbol.len) return .{ .name = symbol };
    return .{ .name = symbol[cut + 1 ..], .qualifier = symbol[0..cut] };
}

const SymbolDecision = struct {
    index: ?u32,
    unresolved: []const u8 = "",
};

/// A symbol names a same-unit definition only when nothing else can give it
/// meaning. Clojure binds names through parameters, special forms, and macros;
/// macros may bind with any syntax, so every form this frontend does not know
/// to bind nothing leaves the names under it unresolved. Incomplete, never a
/// guess.
fn decideSymbol(def: DefInfo, names: UnitNames, name: []const u8, known: bool) SymbolDecision {
    var declarations: usize = 0;
    for (names.declared) |declared| {
        if (std.mem.eql(u8, declared, name)) declarations += 1;
    }
    if (declarations == 0) return .{ .index = null, .unresolved = "the symbol names nothing defined in the analyzed source unit" };
    for (def.params) |param| {
        if (std.mem.eql(u8, param, name)) return .{ .index = null, .unresolved = "a parameter of the enclosing definition binds this name" };
    }
    if (!def.body_known) return .{ .index = null, .unresolved = "the enclosing definition has several arities, " ++
        "whose parameters this frontend does not read" };
    if (!known) return .{ .index = null, .unresolved = "the symbol is inside a form this frontend cannot rule out " ++
        "as a macro that binds the name locally" };
    if (declarations > 1) return .{ .index = null, .unresolved = "the source unit declares this name more than once" };
    for (names.defs) |candidate| {
        if (std.mem.eql(u8, candidate.name, name)) return .{ .index = candidate.index };
    }
    return .{ .index = null, .unresolved = "the name is declared by a top-level form outside this frontend's coverage" };
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
