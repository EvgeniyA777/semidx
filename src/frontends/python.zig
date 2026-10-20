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
//!   `method` definition whose identity carries the class's name; and
//! - inside the body of every covered function and method, every call: a bare
//!   callee `name(...)` is a `CALLS` fact only when Python's scoping leaves the
//!   name one possible meaning, an undecorated covered definition of the same
//!   unit. Every other call is unresolved with its reason.
//!
//! Bindings are over-approximated on purpose. Any binding of a name anywhere
//! in the enclosing covered definition, nested scopes included, makes the name
//! local; any second module-level binding, `global` declaration, or `:=` of it
//! anywhere in the unit makes it ambiguous. An extra binding can only leave a
//! call unresolved, never resolve one wrongly. Every walk uses an explicit
//! stack rather than a depth limit, because a binding deep inside an expression
//! still binds for the whole scope and must never be missed.
//!
//! Not covered: every other module-level statement (imports, assignments,
//! expression statements, `if` blocks and the definitions inside them), every
//! other class body statement (attributes, nested classes), classes nested in
//! covered bodies, and the decorators, defaults, and base classes of covered
//! definitions, which run at module level. Docstrings, `pass`, and comments
//! carry nothing to claim and are skipped silently.

const std = @import("std");
const Allocator = std.mem.Allocator;

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
    .relationship_kinds = &.{ .defines, .calls },
    .coverage_note = "`def`, `async def`, and `class` statements directly in " ++
        "the module, decorated or not, and `def` and `async def` statements " ++
        "directly in those classes' bodies; calls in those definitions' " ++
        "bodies, where a bare callee name resolves only when no binding in " ++
        "the enclosing definition, no `import *`, and no other module-level " ++
        "binding, `global`, or `:=` of the name exists and its one " ++
        "module-level binding is an undecorated covered definition; every " ++
        "other callee stays unresolved, and every other module-level and " ++
        "class-level statement is unsupported",
};

/// The most distinct uncovered constructs reported one by one. The rest are
/// still reported, as one count.
const max_reported_kinds: usize = 16;

/// Where an uncovered construct was found.
const Placement = enum { top_level, class_member, function_body };

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
                .function_body => try builder.print(
                    "{d} `{s}` inside a function or method body, whose calls were not analyzed",
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

/// What one module-level binding of a name binds it to.
const Binding = union(enum) {
    /// A covered `def` or `class` without decorators: its batch index.
    definition: u32,
    /// A covered `def` or `class` with decorators, which decide the value.
    decorated,
    /// Any other binding form.
    other,
};

const ModuleBinding = struct {
    name: []const u8,
    binding: Binding,
};

/// What a bare name in a covered body can be resolved against.
const ModuleScope = struct {
    source: []const u8,
    /// One entry per binding occurrence, not per name: a name bound twice
    /// appears twice.
    bindings: []const ModuleBinding,
    /// A `from ... import *`, which can bind any module-level name.
    wildcard: bool,
};

/// A covered function or method whose body is walked for calls.
const Body = struct {
    index: u32,
    definition: ts.Node,
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

    const gpa = builder.gpa;
    var uncovered: Uncovered = .{};
    var definitions: usize = 0;

    var bindings: std.ArrayList(ModuleBinding) = .empty;
    defer bindings.deinit(gpa);
    var bodies: std.ArrayList(Body) = .empty;
    defer bodies.deinit(gpa);
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(gpa);

    var statements = root.namedChildren();
    while (statements.next()) |node| {
        if (carriesNothing(node)) continue;
        const statement = statementOf(node) orelse {
            uncovered.note(node.kind(), .top_level);
            // An uncovered statement still binds names at module level, and
            // every one of them counts against a covered definition's.
            names.clearRetainingCapacity();
            try collectBindings(gpa, source, node, .module, &names);
            for (names.items) |name| try bindings.append(gpa, .{ .name = name, .binding = .other });
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
        try bindings.append(gpa, .{
            .name = name,
            .binding = if (statement.decorated) .decorated else .{ .definition = index },
        });

        if (!statement.is_class) {
            try bodies.append(gpa, .{ .index = index, .definition = statement.definition });
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
            try bodies.append(gpa, .{ .index = member_index, .definition = member.definition });
        }
    }

    // `global` and `:=` bind a module-level name from inside any scope, and
    // `import *` binds names nobody wrote, so the whole unit is read for them.
    const wildcard = try collectUnitWideBindings(gpa, source, root, &names);
    for (names.items) |name| try bindings.append(gpa, .{ .name = name, .binding = .other });

    const module: ModuleScope = .{
        .source = source,
        .bindings = bindings.items,
        .wildcard = wildcard,
    };
    var locals: std.ArrayList([]const u8) = .empty;
    defer locals.deinit(gpa);
    for (bodies.items) |body| {
        locals.clearRetainingCapacity();
        try collectBindings(gpa, source, body.definition, .definition, &locals);
        try walkCalls(builder, module, body, locals.items, &uncovered);
    }

    try uncovered.report(builder);
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

/// Which scope a binding walk reads.
const Region = enum {
    /// A module-level statement: nested `def`, `class`, and `lambda` bodies
    /// are other scopes, so only their names are read.
    module,
    /// A covered definition: everything under it, nested scopes included, so
    /// that a name bound anywhere inside counts as local everywhere inside.
    definition,
};

/// Appends every name `node` binds in `region`. Over-approximates: a name that
/// may not be a binding is still appended, because one too many can only leave
/// a call unresolved.
///
/// In the module region, `global` and `:=` are left to
/// `collectUnitWideBindings`, which reads them everywhere, so no occurrence is
/// counted twice.
fn collectBindings(
    gpa: Allocator,
    source: []const u8,
    node: ts.Node,
    region: Region,
    out: *std.ArrayList([]const u8),
) !void {
    var stack: std.ArrayList(ts.Node) = .empty;
    defer stack.deinit(gpa);
    try stack.append(gpa, node);

    while (stack.pop()) |current| {
        const kind = current.kind();
        const is_root = current.startByte() == node.startByte() and current.endByte() == node.endByte();

        if (std.mem.eql(u8, kind, "function_definition") or std.mem.eql(u8, kind, "class_definition")) {
            // A covered definition's own name is a module-level binding, not a
            // local of its body: a recursive call means the module's name.
            if (!(region == .definition and is_root)) {
                if (current.childByFieldName("name")) |name| try out.append(gpa, name.text(source));
            }
            if (region == .module) continue;
            if (current.childByFieldName("type_parameters")) |parameters| try collectIdentifiers(gpa, source, parameters, out);
        } else if (std.mem.eql(u8, kind, "lambda")) {
            if (region == .module) continue;
            if (current.childByFieldName("parameters")) |parameters| try collectIdentifiers(gpa, source, parameters, out);
        } else if (std.mem.eql(u8, kind, "parameters")) {
            try appendParameterNames(gpa, source, current, out);
        } else if (std.mem.eql(u8, kind, "assignment") or
            std.mem.eql(u8, kind, "augmented_assignment") or
            std.mem.eql(u8, kind, "for_statement") or
            std.mem.eql(u8, kind, "for_in_clause") or
            std.mem.eql(u8, kind, "type_alias_statement"))
        {
            if (current.childByFieldName("left")) |left| try collectIdentifiers(gpa, source, left, out);
        } else if (std.mem.eql(u8, kind, "as_pattern")) {
            if (current.childByFieldName("alias")) |alias| try collectIdentifiers(gpa, source, alias, out);
        } else if (std.mem.eql(u8, kind, "import_statement") or std.mem.eql(u8, kind, "import_from_statement")) {
            try appendImportNames(gpa, source, current, out);
            continue;
        } else if (std.mem.eql(u8, kind, "future_import_statement") or
            std.mem.eql(u8, kind, "delete_statement") or
            std.mem.eql(u8, kind, "nonlocal_statement") or
            std.mem.eql(u8, kind, "case_pattern"))
        {
            // Every identifier inside is, or may be, a name bound here; the
            // node holds nothing else this walk needs.
            try collectIdentifiers(gpa, source, current, out);
            continue;
        } else if (std.mem.eql(u8, kind, "global_statement")) {
            if (region == .definition) try collectIdentifiers(gpa, source, current, out);
            continue;
        } else if (std.mem.eql(u8, kind, "named_expression")) {
            if (region == .definition) {
                if (current.childByFieldName("name")) |name| try out.append(gpa, name.text(source));
            }
        }

        try pushChildren(gpa, &stack, current);
    }
}

/// Appends the names every `global` declaration and every `:=` in the unit
/// bind at module level, wherever they are written, and returns whether the
/// unit has a `from ... import *`.
fn collectUnitWideBindings(
    gpa: Allocator,
    source: []const u8,
    root: ts.Node,
    out: *std.ArrayList([]const u8),
) !bool {
    out.clearRetainingCapacity();
    var wildcard = false;
    var stack: std.ArrayList(ts.Node) = .empty;
    defer stack.deinit(gpa);
    try stack.append(gpa, root);

    while (stack.pop()) |current| {
        const kind = current.kind();
        if (std.mem.eql(u8, kind, "wildcard_import")) {
            wildcard = true;
            continue;
        }
        if (std.mem.eql(u8, kind, "global_statement")) {
            try collectIdentifiers(gpa, source, current, out);
            continue;
        }
        if (std.mem.eql(u8, kind, "named_expression")) {
            if (current.childByFieldName("name")) |name| try out.append(gpa, name.text(source));
        }
        try pushChildren(gpa, &stack, current);
    }
    return wildcard;
}

/// The names a parameter list binds, without the names its defaults and
/// annotations read. Anything of an unrecognized shape contributes every
/// identifier inside it.
fn appendParameterNames(
    gpa: Allocator,
    source: []const u8,
    parameters: ts.Node,
    out: *std.ArrayList([]const u8),
) !void {
    var children = parameters.namedChildren();
    while (children.next()) |parameter| {
        const kind = parameter.kind();
        if (std.mem.eql(u8, kind, "identifier")) {
            try out.append(gpa, parameter.text(source));
        } else if (std.mem.eql(u8, kind, "default_parameter") or std.mem.eql(u8, kind, "typed_default_parameter")) {
            const name = parameter.childByFieldName("name") orelse parameter;
            try collectIdentifiers(gpa, source, name, out);
        } else if (std.mem.eql(u8, kind, "typed_parameter")) {
            // The bound part comes first; the annotation is the `type` field.
            const bound = parameter.namedChild(0) orelse continue;
            try collectIdentifiers(gpa, source, bound, out);
        } else if (std.mem.eql(u8, kind, "keyword_separator") or std.mem.eql(u8, kind, "positional_separator")) {
            continue;
        } else {
            try collectIdentifiers(gpa, source, parameter, out);
        }
    }
}

/// The names an `import` or `from ... import` statement binds: an alias where
/// one is written, else the first name of the dotted path (`import a.b` binds
/// `a`). The module a `from` statement reads is not a binding.
fn appendImportNames(
    gpa: Allocator,
    source: []const u8,
    statement: ts.Node,
    out: *std.ArrayList([]const u8),
) !void {
    const module_name = statement.childByFieldName("module_name");
    var children = statement.namedChildren();
    while (children.next()) |child| {
        if (module_name) |module| {
            if (child.startByte() == module.startByte() and child.endByte() == module.endByte()) continue;
        }
        const kind = child.kind();
        if (std.mem.eql(u8, kind, "aliased_import")) {
            const alias = child.childByFieldName("alias") orelse child;
            try collectIdentifiers(gpa, source, alias, out);
        } else if (std.mem.eql(u8, kind, "dotted_name")) {
            const first = child.namedChild(0) orelse continue;
            try out.append(gpa, first.text(source));
        } else if (!std.mem.eql(u8, kind, "wildcard_import")) {
            try collectIdentifiers(gpa, source, child, out);
        }
    }
}

fn collectIdentifiers(
    gpa: Allocator,
    source: []const u8,
    node: ts.Node,
    out: *std.ArrayList([]const u8),
) !void {
    var stack: std.ArrayList(ts.Node) = .empty;
    defer stack.deinit(gpa);
    try stack.append(gpa, node);
    while (stack.pop()) |current| {
        if (std.mem.eql(u8, current.kind(), "identifier")) {
            try out.append(gpa, current.text(source));
            continue;
        }
        try pushChildren(gpa, &stack, current);
    }
}

/// Pushes `node`'s named children so that they pop in source order.
fn pushChildren(gpa: Allocator, stack: *std.ArrayList(ts.Node), node: ts.Node) !void {
    var index = node.namedChildCount();
    while (index > 0) {
        index -= 1;
        if (node.namedChild(index)) |child| try stack.append(gpa, child);
    }
}

/// Records every call in a covered definition's body. Calls inside nested
/// `def` and `lambda` bodies belong to the covered definition whose source
/// contains them; a nested `class` opens a scope this slice does not model, so
/// it is reported and not walked.
fn walkCalls(
    builder: *contract.BatchBuilder,
    module: ModuleScope,
    body: Body,
    locals: []const []const u8,
    uncovered: *Uncovered,
) !void {
    const gpa = builder.gpa;
    const block = body.definition.childByFieldName("body") orelse return;
    var stack: std.ArrayList(ts.Node) = .empty;
    defer stack.deinit(gpa);
    try stack.append(gpa, block);

    while (stack.pop()) |current| {
        const kind = current.kind();
        if (std.mem.eql(u8, kind, "class_definition")) {
            uncovered.note(kind, .function_body);
            continue;
        }
        if (std.mem.eql(u8, kind, "call")) {
            if (current.childByFieldName("function")) |callee| {
                try emitCall(builder, module, body, locals, current, callee);
            }
        }
        try pushChildren(gpa, &stack, current);
    }
}

fn emitCall(
    builder: *contract.BatchBuilder,
    module: ModuleScope,
    body: Body,
    locals: []const []const u8,
    call: ts.Node,
    callee: ts.Node,
) !void {
    // The callee as the source wrote it: the evidence for this claim, and the
    // thing the designator is read out of rather than the designator itself.
    const written = try builder.dupe(callee.text(module.source));
    if (written.len == 0) return;

    const kind = callee.kind();
    var designator: model.Designator = .{ .name = "" };
    const decision: CallDecision = if (std.mem.eql(u8, kind, "identifier")) blk: {
        designator = .{ .name = written };
        break :blk decideName(module, locals, written);
    } else if (std.mem.eql(u8, kind, "attribute")) blk: {
        // `a.b.c(...)` keeps the name it calls and no qualifier: nothing here
        // establishes that `a.b` names a module rather than a value.
        if (callee.childByFieldName("attribute")) |attribute| {
            designator = .{ .name = try builder.dupe(attribute.text(module.source)) };
        }
        break :blk .{ .unresolved = "the callee is an attribute access; calls through modules, classes, and values are not resolved" };
    } else .{ .unresolved = "the callee is not a name or an attribute access" };

    try builder.addRelationship(.{
        .kind = .calls,
        .source = .{ .entity = body.index },
        .target = switch (decision) {
            .definition => |index| .{ .local = index },
            .unresolved => .{ .designator = designator },
        },
        .evidence = evidenceOf(builder, call, written),
        .resolution = switch (decision) {
            .definition => .{ .fact = .{
                .method = "bare callee naming the one module-level binding of that name in the analyzed source unit, an undecorated function or class, with no binding of it in the enclosing definition and no `import *`",
            } },
            .unresolved => |explanation| .{ .unresolved = .{
                .missing = .target_entity,
                .explanation = explanation,
            } },
        },
    });
}

const CallDecision = union(enum) {
    definition: u32,
    unresolved: []const u8,
};

/// Decides a bare name under ADR 015's four rules. A class's own names are
/// never consulted: Python does not make them visible inside its methods.
fn decideName(module: ModuleScope, locals: []const []const u8, name: []const u8) CallDecision {
    for (locals) |local| {
        if (std.mem.eql(u8, local, name)) {
            return .{ .unresolved = "a parameter or a binding in the enclosing definition has this name" };
        }
    }
    if (module.wildcard) {
        return .{ .unresolved = "the unit has a `from ... import *`, which can bind any module-level name" };
    }

    var matches: u32 = 0;
    var binding: Binding = .other;
    for (module.bindings) |entry| {
        if (!std.mem.eql(u8, entry.name, name)) continue;
        matches += 1;
        binding = entry.binding;
    }
    return switch (matches) {
        0 => .{ .unresolved = "nothing in the analyzed source unit binds this name at module level; it may be a builtin" },
        1 => switch (binding) {
            .definition => |index| .{ .definition = index },
            .decorated => .{ .unresolved = "the one module-level binding of this name is a decorated definition, whose decorators decide what the name is bound to" },
            .other => .{ .unresolved = "the one module-level binding of this name is not a covered definition" },
        },
        else => .{ .unresolved = "the analyzed source unit binds this name more than once at module level, by definition, assignment, import, `global`, or `:=`" },
    };
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
