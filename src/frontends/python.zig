//! Python frontend.
//!
//! A minimal slice ([ADR 015](../../docs/adr/015_add_minimal_python_frontend.md)):
//! it grows only where the grammar exposes a construct with exact evidence, and
//! everything outside it is reported rather than approximated. Python's own
//! vocabulary stays in extension payloads.
//!
//! Covered today:
//!
//! - a `def` or `async def` statement directly in the module, decorated or
//!   not, as a `function` definition;
//! - a `class` statement directly in the module, decorated or not, as a `class`
//!   definition; and
//! - a `def` or `async def` statement directly in such a class's body, as a
//!   `method` definition whose identity carries the class's name.
//!
//! Not covered: every other module-level statement (imports, assignments,
//! expression statements, `if` blocks and the definitions inside them), every
//! other class body statement (attributes, nested classes), and the bodies of
//! covered definitions, which are not yet analyzed for calls. Docstrings,
//! `pass`, and comments carry nothing to claim and are skipped silently.

const std = @import("std");

const core = @import("semidx_core");
const ts = @import("semidx_tree_sitter");

const model = core.model;
const contract = core.contract;

pub const grammar: ts.Grammar = .python;

pub const version = std.fmt.comptimePrint("plan-018+ts-abi{d}", .{ts.runtime_abi_version});

pub const capabilities: contract.Capabilities = .{
    .language = .python,
    .producer = .{ .name = "frontend.python", .version = version },
    .entity_roles = &.{ "function", "class", "method" },
    .relationship_kinds = &.{.defines},
    .coverage_note = "`def`, `async def`, and `class` statements directly in " ++
        "the module, decorated or not, and `def` and `async def` statements " ++
        "directly in those classes' bodies; the bodies of those definitions " ++
        "are not analyzed, and every other module-level and class-level " ++
        "statement is unsupported",
};

/// The most distinct uncovered constructs reported one by one. The rest are
/// still reported, as one count.
const max_reported_kinds: usize = 16;

/// Where an uncovered construct was found.
const Placement = enum { top_level, class_member };

/// Counts uncovered constructs by node kind and placement, so a module full of
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
                    "{d} module-level `{s}` outside this frontend's coverage",
                    .{ entry.count, entry.kind },
                ),
                .class_member => try builder.print(
                    "{d} `{s}` in the body of a top-level class, outside this frontend's coverage",
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

/// A `def` or `class` statement, read through any decorators in front of it.
const Statement = struct {
    /// The whole statement, decorators included: the evidence for the claim.
    outer: ts.Node,
    /// The `function_definition` or `class_definition` itself.
    definition: ts.Node,
    decorated: bool,
    is_class: bool,
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
            "the source unit does not parse cleanly, so no Python assertions were derived from it",
        );
        return;
    }

    // Entities are scoped to the unit, not to where the unit currently sits.
    const scope: model.Scope = .{ .unit = input.unit.id };

    var uncovered: Uncovered = .{};
    var definitions: usize = 0;
    var bodies: usize = 0;

    var statements = root.namedChildren();
    while (statements.next()) |node| {
        if (carriesNothing(node)) continue;
        const statement = statementOf(node) orelse {
            uncovered.note(node.kind(), .top_level);
            continue;
        };
        const name_node = statement.definition.childByFieldName("name") orelse {
            uncovered.note(statement.definition.kind(), .top_level);
            continue;
        };
        const name = try builder.dupe(name_node.text(source));
        const index = try addDefinition(
            builder,
            scope,
            statement,
            name,
            if (statement.is_class) "class" else "function",
            &.{},
            if (statement.is_class)
                "`class` statement directly in the module of the analyzed source unit"
            else
                "`def` statement directly in the module of the analyzed source unit",
        );
        try builder.addRelationship(.{
            .kind = .defines,
            .source = .unit_container,
            .target = .{ .local = index },
            .evidence = evidenceOf(builder, statement.outer, name),
            .resolution = .{ .fact = .{
                .method = "declared directly in the module of this source unit",
            } },
        });
        definitions += 1;

        if (!statement.is_class) {
            bodies += 1;
            continue;
        }

        const path = try builder.dupeSlice(&.{name});
        const body = statement.definition.childByFieldName("body") orelse continue;
        var members = body.namedChildren();
        while (members.next()) |member_node| {
            if (carriesNothing(member_node)) continue;
            const member = statementOf(member_node) orelse {
                uncovered.note(member_node.kind(), .class_member);
                continue;
            };
            if (member.is_class) {
                uncovered.note(member.definition.kind(), .class_member);
                continue;
            }
            const member_name_node = member.definition.childByFieldName("name") orelse {
                uncovered.note(member.definition.kind(), .class_member);
                continue;
            };
            const member_name = try builder.dupe(member_name_node.text(source));
            const member_index = try addDefinition(
                builder,
                scope,
                member,
                member_name,
                "method",
                path,
                "`def` statement directly in the body of a top-level class in the analyzed source unit",
            );
            try builder.addRelationship(.{
                .kind = .defines,
                .source = .{ .entity = index },
                .target = .{ .local = member_index },
                .evidence = evidenceOf(builder, member.outer, member_name),
                .resolution = .{ .fact = .{
                    .method = "declared directly in the body of this top-level class",
                } },
            });
            definitions += 1;
            bodies += 1;
        }
    }

    try uncovered.report(builder);
    if (bodies > 0) {
        try builder.addDiagnostic(.unsupported_construct, try builder.print(
            "{d} function and method bodies were not analyzed for calls",
            .{bodies},
        ));
    }
    if (definitions == 0) {
        try builder.addDiagnostic(
            .confirmed_absence,
            "the source unit parsed and declares no module-level function or class",
        );
    }
}

/// A comment, `pass`, or docstring: statements with no binding, no call, and no
/// definition, so skipping them withholds nothing.
fn carriesNothing(node: ts.Node) bool {
    const kind = node.kind();
    if (std.mem.eql(u8, kind, "comment")) return true;
    if (std.mem.eql(u8, kind, "pass_statement")) return true;
    if (!std.mem.eql(u8, kind, "expression_statement")) return false;
    if (node.namedChildCount() != 1) return false;
    const value = node.namedChild(0).?.kind();
    return std.mem.eql(u8, value, "string") or std.mem.eql(u8, value, "concatenated_string");
}

/// Reads a `def` or `class` statement, through its decorators when it has any.
/// Null for every other statement.
fn statementOf(node: ts.Node) ?Statement {
    var definition = node;
    var decorated = false;
    if (std.mem.eql(u8, node.kind(), "decorated_definition")) {
        definition = node.childByFieldName("definition") orelse return null;
        decorated = true;
    }
    const kind = definition.kind();
    if (std.mem.eql(u8, kind, "function_definition")) {
        return .{ .outer = node, .definition = definition, .decorated = decorated, .is_class = false };
    }
    if (std.mem.eql(u8, kind, "class_definition")) {
        return .{ .outer = node, .definition = definition, .decorated = decorated, .is_class = true };
    }
    return null;
}

/// Whether a `def` is written `async def`: the keyword is the statement's first
/// token.
fn isAsync(definition: ts.Node) bool {
    const first = definition.childAt(0) orelse return false;
    return !first.isNamed() and std.mem.eql(u8, first.kind(), "async");
}

fn addDefinition(
    builder: *contract.BatchBuilder,
    scope: model.Scope,
    statement: Statement,
    name: []const u8,
    role: []const u8,
    container_path: []const []const u8,
    method: []const u8,
) !u32 {
    var labels: [3]model.ExtensionLabel = undefined;
    var count: usize = 0;
    labels[count] = .{ .key = "python.construct", .value = if (statement.is_class) "class" else "function" };
    count += 1;
    if (!statement.is_class and isAsync(statement.definition)) {
        labels[count] = .{ .key = "python.async", .value = "true" };
        count += 1;
    }
    if (statement.decorated) {
        labels[count] = .{ .key = "python.decorated", .value = "true" };
        count += 1;
    }

    return builder.addEntity(.{
        .kind = .definition,
        .identity = .{
            .scope = scope,
            .language = .python,
            .role = role,
            .name = name,
            // Python has no overloading: a parameter edit is not a new
            // definition.
            .signature = null,
            .container_path = container_path,
        },
        .evidence = evidenceOf(builder, statement.outer, name),
        .extension = .{
            .namespace = "python",
            .labels = try builder.labels(labels[0..count]),
        },
        .resolution = .{ .fact = .{ .method = method } },
    });
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
