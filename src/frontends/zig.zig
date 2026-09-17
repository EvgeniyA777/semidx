//! Zig frontend.
//!
//! Coverage starts narrow on purpose: it grows only where the grammar exposes a
//! construct with exact evidence. Everything outside it is reported as
//! unsupported rather than approximated, and Zig's own vocabulary stays in
//! extension payloads.
//!
//! Covered today:
//!
//! - a named top-level `fn` declaration, as a `function` definition;
//! - a top-level `const` whose value is written directly as a `struct`,
//!   `enum`, `union`, or `opaque` expression, as a `container` definition;
//! - a named `fn` declared directly inside such a container, as a `function`
//!   definition whose identity carries the container's name
//!   ([ADR 006](../../docs/adr/006_allow_narrow_zig_member_definitions_and_local_import_calls.md)); and
//! - inside a covered top-level function body, every call expression: a call
//!   whose callee is a bare name is a `CALLS` fact only when that name can mean
//!   nothing but the one top-level function of that name in the same unit.
//!
//! A top-level `const alias = @import("relative/path.zig");` that names exactly
//! one indexed Zig unit is a local import alias. It is analysis context, not an
//! entity or a relationship, and establishing one declares a dependency on the
//! unit it names. Every other import is reported or left uncovered.
//!
//! Not covered: other top-level constants and variables (imports, aliases,
//! values), tests, `comptime` blocks, `usingnamespace`, container fields and
//! every container member other than a named `fn`, containers nested in
//! containers or in function bodies, the bodies of member functions, builtin
//! calls, and names that are not called. Nothing here resolves a container's
//! namespace, imports, fields, or methods.

const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("semidx_core");
const ts = @import("semidx_tree_sitter");

const model = core.model;
const contract = core.contract;

pub const grammar: ts.Grammar = .zig;

pub const version = std.fmt.comptimePrint("plan-006+ts-abi{d}", .{ts.runtime_abi_version});

pub const capabilities: contract.Capabilities = .{
    .language = .zig,
    .producer = .{ .name = "frontend.zig", .version = version },
    .entity_roles = &.{ "function", "container" },
    .relationship_kinds = &.{ .defines, .calls },
    .coverage_note = "named top-level `fn` declarations, top-level `const` " ++
        "declarations bound directly to a struct, enum, union, or opaque " ++
        "expression, and named `fn` declarations directly inside those " ++
        "containers; call expressions in top-level functions' bodies, where a " ++
        "bare callee name resolves only to the unit's one top-level function of " ++
        "that name and every other callee stays unresolved; member function " ++
        "bodies, other container members, nested containers, builtin calls, and " ++
        "every other declaration are unsupported",
};

/// What an `@import` string names, read lexically against the importing unit's
/// root-relative path. Nothing here touches the filesystem: a path is only ever
/// compared, byte for byte, with the paths of indexed source units, so case
/// folding, symbolic links, and package search cannot make a match.
pub const ImportPath = union(enum) {
    /// A normalized, root-relative, `/`-separated path to a Zig file.
    file: []const u8,
    /// A package or builtin module name such as `std`, which is not resolved.
    package,
    /// Written as a Zig file path, but it cannot name a unit under the root.
    rejected: []const u8,
};

pub fn resolveImportPath(
    allocator: Allocator,
    importer: []const u8,
    literal: []const u8,
) Allocator.Error!ImportPath {
    if (!std.mem.endsWith(u8, literal, ".zig")) return .package;
    if (std.mem.startsWith(u8, literal, "/")) return .{ .rejected = "the path is absolute" };
    if (std.mem.indexOfScalar(u8, literal, '\\') != null) {
        return .{ .rejected = "the path contains a backslash, which is not read as a separator" };
    }

    var segments: std.ArrayList([]const u8) = .empty;
    defer segments.deinit(allocator);
    if (std.mem.lastIndexOfScalar(u8, importer, '/')) |end| {
        var directories = std.mem.splitScalar(u8, importer[0..end], '/');
        while (directories.next()) |directory| try segments.append(allocator, directory);
    }
    var parts = std.mem.splitScalar(u8, literal, '/');
    while (parts.next()) |part| {
        if (part.len == 0) return .{ .rejected = "the path has an empty segment" };
        if (std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (segments.items.len == 0) return .{ .rejected = "the path escapes the indexed root" };
            _ = segments.pop();
            continue;
        }
        try segments.append(allocator, part);
    }
    return .{ .file = try std.mem.join(allocator, "/", segments.items) };
}

/// The indexed Zig unit one local import path names, as the analyzer read it
/// from the graph before this unit was analyzed.
pub const Provider = struct {
    path: []const u8,
    unit: model.SourceUnitId,
    /// Whether the unit's analysis is current. A pending, stale, or failed
    /// provider still establishes the alias, but offers nothing to resolve to.
    current: bool,
};

/// What the analyzer hands the Zig frontend about the rest of the repository.
pub const Context = struct {
    /// False when the unit is analyzed without a graph to look providers up in.
    repository: bool,
    /// One entry per requested path that names an indexed, live Zig unit.
    providers: []const Provider,

    pub const empty: Context = .{ .repository = false, .providers = &.{} };

    fn provider(self: Context, path: []const u8) ?Provider {
        for (self.providers) |entry| {
            if (std.mem.eql(u8, entry.path, path)) return entry;
        }
        return null;
    }
};

/// The root-relative Zig file paths the unit's top-level import declarations
/// name, each once, so the analyzer can look them up before analysis.
pub fn localImportPaths(
    allocator: Allocator,
    root: ts.Node,
    source: []const u8,
    importer: []const u8,
) Allocator.Error![]const []const u8 {
    var paths: std.ArrayList([]const u8) = .empty;
    var members = root.namedChildren();
    while (members.next()) |member| {
        if (!std.mem.eql(u8, member.kind(), "variable_declaration")) continue;
        const declaration = importDeclaration(member, source) orelse continue;
        const path = switch (try resolveImportPath(allocator, importer, declaration.literal)) {
            .file => |path| path,
            .package, .rejected => continue,
        };
        for (paths.items) |seen| {
            if (std.mem.eql(u8, seen, path)) break;
        } else try paths.append(allocator, path);
    }
    return paths.items;
}

/// Guards against unbounded recursion on pathological input. Exceeding it is
/// reported as an unsupported construct, never as an absence of calls.
const max_depth: u32 = 64;

/// The most distinct uncovered constructs reported one by one. The rest are
/// still reported, as one count.
const max_reported_kinds: usize = 16;

/// Where an uncovered construct was found.
const Placement = enum { top_level, container_member, function_body };

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
                .function_body => try builder.print(
                    "{d} `{s}` inside a function body, whose calls were not analyzed",
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

/// One name declared at the top level of the unit, covered or not. Every one
/// counts when deciding what a bare name can mean.
const TopLevelName = struct {
    name: []const u8,
    /// The batch index of the covered function this name declares, if it is
    /// one.
    function: ?u32,
};

/// A top-level `[pub] const <alias> = @import("<literal>");`.
const ImportDeclaration = struct {
    node: ts.Node,
    alias: []const u8,
    literal: []const u8,
};

/// Whether a top-level import declaration established a local import alias,
/// and if not, why.
const AliasState = union(enum) {
    established: Provider,
    /// A package or builtin import, which is not resolved and not reported
    /// beyond its uncovered declaration.
    package,
    declined: []const u8,
};

const Alias = struct {
    declaration: ImportDeclaration,
    state: AliasState,
};

/// A covered top-level container, whose direct members are read once every
/// top-level declaration has been.
const CoveredContainer = struct {
    index: u32,
    name: []const u8,
    value: ts.Node,
};

/// A covered function whose body is walked for calls.
const FunctionBody = struct {
    index: u32,
    declaration: ts.Node,
    body: ts.Node,
};

/// What the call walk of one unit needs to decide a bare callee name.
const CallScope = struct {
    source: []const u8,
    names: []const TopLevelName,
    /// `usingnamespace` can bring declarations of any name into the unit's
    /// namespace, so no bare name is decided while one is present.
    using_namespace: bool,
};

pub fn analyze(
    builder: *contract.BatchBuilder,
    input: contract.FrontendInput,
    tree: ts.Tree,
    context: Context,
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

    const gpa = builder.gpa;
    var names: std.ArrayList(TopLevelName) = .empty;
    defer names.deinit(gpa);
    var bodies: std.ArrayList(FunctionBody) = .empty;
    defer bodies.deinit(gpa);
    var containers: std.ArrayList(CoveredContainer) = .empty;
    defer containers.deinit(gpa);
    var imports: std.ArrayList(ImportDeclaration) = .empty;
    defer imports.deinit(gpa);
    var using_namespace = false;

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
            const index = try addDefinition(builder, scope, member, name, "function", &.{}, &.{
                .{ .key = "zig.construct", .value = "function" },
            }, "named top-level `fn` declaration in the analyzed source unit");
            try addDefines(builder, member, name, index);
            definitions += 1;
            try names.append(gpa, .{ .name = name, .function = index });
            if (member.childByFieldName("body")) |body| {
                try bodies.append(gpa, .{ .index = index, .declaration = member, .body = body });
            }
            continue;
        }

        if (std.mem.eql(u8, kind, "variable_declaration")) {
            if (declaredIdentifier(member)) |identifier| {
                try names.append(gpa, .{ .name = identifier.text(source), .function = null });
            }
            if (importDeclaration(member, source)) |declaration| try imports.append(gpa, declaration);
            const declaration = containerDeclaration(member) orelse {
                uncovered.note(kind, .top_level);
                continue;
            };
            const name = try builder.dupe(declaration.name.text(source));
            const index = try addDefinition(builder, scope, member, name, "container", &.{}, &.{
                .{ .key = "zig.construct", .value = "container" },
                .{ .key = "zig.container", .value = declaration.label },
            }, "top-level `const` bound directly to a container expression in the analyzed source unit");
            try addDefines(builder, member, name, index);
            definitions += 1;
            try containers.append(gpa, .{ .index = index, .name = name, .value = declaration.value });
            continue;
        }

        if (std.mem.eql(u8, kind, "using_namespace_declaration")) using_namespace = true;
        uncovered.note(kind, .top_level);
    }

    const aliases = try builder.allocator().alloc(Alias, imports.items.len);
    for (imports.items, aliases) |declaration, *alias| {
        alias.* = .{
            .declaration = declaration,
            .state = try aliasState(builder, input.unit, context, names.items, using_namespace, declaration),
        };
        switch (alias.state) {
            .established => |provider| try builder.addDependency(provider.unit, try builder.print(
                "top-level `const {s} = @import(\"{s}\")` names this unit",
                .{ declaration.alias, declaration.literal },
            )),
            .package, .declined => {},
        }
    }

    // Members come after every top-level declaration, so a unit's top-level
    // definitions keep the batch order they had before members were covered.
    var unanalyzed_member_bodies: u32 = 0;
    for (containers.items) |container| {
        const path = try builder.dupeSlice(&.{container.name});
        var inner = container.value.namedChildren();
        while (inner.next()) |inner_member| {
            const kind = inner_member.kind();
            if (isComment(kind)) continue;
            if (!std.mem.eql(u8, kind, "function_declaration")) {
                uncovered.note(kind, .container_member);
                continue;
            }
            const name_node = inner_member.childByFieldName("name") orelse {
                uncovered.note(kind, .container_member);
                continue;
            };
            const name = try builder.dupe(name_node.text(source));
            const index = try addDefinition(builder, scope, inner_member, name, "function", path, &.{
                .{ .key = "zig.construct", .value = "function" },
                .{ .key = "zig.placement", .value = "container_member" },
            }, "named `fn` declared directly inside a covered top-level container in the analyzed source unit");
            try builder.addRelationship(.{
                .kind = .defines,
                .source = .{ .entity = container.index },
                .target = .{ .local = index },
                .evidence = evidenceOf(builder, inner_member, name),
                .resolution = .{ .fact = .{
                    .method = "declared directly inside this top-level container",
                } },
            });
            if (inner_member.childByFieldName("body") != null) unanalyzed_member_bodies += 1;
        }
    }

    const unit_scope: CallScope = .{
        .source = source,
        .names = names.items,
        .using_namespace = using_namespace,
    };
    var too_deep = false;
    for (bodies.items) |function| {
        var locals: std.ArrayList([]const u8) = .empty;
        defer locals.deinit(gpa);
        try collectParameters(gpa, source, function.declaration, &locals);
        try collectBindings(gpa, source, function.body, &locals, 0);
        try walkCalls(builder, unit_scope, function, locals.items, function.body, &uncovered, &too_deep, 0);
    }

    try uncovered.report(builder);
    try reportDeclinedAliases(builder, aliases);
    if (unanalyzed_member_bodies > 0) {
        try builder.addDiagnostic(.unsupported_construct, try builder.print(
            "{d} member function bodies inside top-level containers were not analyzed for calls",
            .{unanalyzed_member_bodies},
        ));
    }
    if (too_deep) {
        try builder.addDiagnostic(
            .unsupported_construct,
            "a function body nested deeper than this frontend traverses was not analyzed for calls",
        );
    }
    if (definitions == 0) {
        try builder.addDiagnostic(
            .confirmed_absence,
            "the source unit parsed and declares no top-level function or container",
        );
    }
}

/// Decides whether one import declaration establishes a local import alias
/// ([ADR 006](../../docs/adr/006_allow_narrow_zig_member_definitions_and_local_import_calls.md)).
fn aliasState(
    builder: *contract.BatchBuilder,
    unit: contract.SourceUnit,
    context: Context,
    names: []const TopLevelName,
    using_namespace: bool,
    declaration: ImportDeclaration,
) !AliasState {
    const path = switch (try resolveImportPath(builder.allocator(), unit.path, declaration.literal)) {
        .package => return .package,
        .rejected => |reason| return .{ .declined = reason },
        .file => |path| path,
    };
    if (!context.repository) {
        return .{ .declined = "the unit was analyzed without repository context to find the imported unit in" };
    }
    const provider = context.provider(path) orelse return .{ .declined = try builder.print(
        "no indexed Zig source unit has the path `{s}`",
        .{path},
    ) };
    if (provider.unit == unit.id) return .{ .declined = "the path names the analyzed unit itself" };

    var declared: usize = 0;
    for (names) |entry| {
        if (std.mem.eql(u8, entry.name, declaration.alias)) declared += 1;
    }
    if (declared != 1) return .{ .declined = "the unit's top level declares this name more than once" };
    if (using_namespace) {
        return .{ .declined = "the unit has a `usingnamespace` declaration, which can bring another declaration of this name into scope" };
    }
    return .{ .established = provider };
}

fn reportDeclinedAliases(builder: *contract.BatchBuilder, aliases: []const Alias) !void {
    var reported: usize = 0;
    var overflow: usize = 0;
    for (aliases) |alias| {
        const reason = switch (alias.state) {
            .declined => |reason| reason,
            .established, .package => continue,
        };
        if (reported == max_reported_kinds) {
            overflow += 1;
            continue;
        }
        reported += 1;
        try builder.addDiagnostic(.unsupported_construct, try builder.print(
            "`const {s} = @import(\"{s}\")` establishes no local import alias: {s}",
            .{ alias.declaration.alias, alias.declaration.literal, reason },
        ));
    }
    if (overflow > 0) {
        try builder.addDiagnostic(.unsupported_construct, try builder.print(
            "{d} further Zig file imports establish no local import alias",
            .{overflow},
        ));
    }
}

/// Reads `[pub] const <identifier> = @import("<literal>");` from the
/// declaration's tokens in order. Returns null for anything else: `var`, a type
/// annotation, `extern` or `export`, an argument that is not one plain string
/// literal, or an import used inside a larger expression.
fn importDeclaration(node: ts.Node, source: []const u8) ?ImportDeclaration {
    var is_const = false;
    var alias: ?ts.Node = null;
    var value: ?ts.Node = null;

    const count = node.childCount();
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const token = node.childAt(index) orelse continue;
        const kind = token.kind();
        if (isComment(kind)) continue;
        if (!token.isNamed()) {
            if (std.mem.eql(u8, kind, "const")) {
                is_const = true;
            } else if (!std.mem.eql(u8, kind, "pub") and !std.mem.eql(u8, kind, "=") and !std.mem.eql(u8, kind, ";")) {
                return null;
            }
            continue;
        }
        if (alias == null) {
            if (!std.mem.eql(u8, kind, "identifier")) return null;
            alias = token;
            continue;
        }
        if (value != null) return null;
        value = token;
    }
    if (!is_const) return null;
    const call = value orelse return null;
    if (!std.mem.eql(u8, call.kind(), "builtin_function")) return null;

    var builtin: ?ts.Node = null;
    var arguments: ?ts.Node = null;
    var parts = call.namedChildren();
    while (parts.next()) |part| {
        const kind = part.kind();
        if (std.mem.eql(u8, kind, "builtin_identifier")) {
            builtin = part;
        } else if (std.mem.eql(u8, kind, "arguments")) {
            arguments = part;
        } else if (!isComment(kind)) {
            return null;
        }
    }
    if (!std.mem.eql(u8, (builtin orelse return null).text(source), "@import")) return null;

    var string: ?ts.Node = null;
    var values = (arguments orelse return null).namedChildren();
    while (values.next()) |argument| {
        if (isComment(argument.kind())) continue;
        if (string != null or !std.mem.eql(u8, argument.kind(), "string")) return null;
        string = argument;
    }

    var literal: []const u8 = "";
    var content = (string orelse return null).namedChildren();
    while (content.next()) |piece| {
        // An escape sequence spells a path differently from its bytes, and a
        // second content node can only follow one.
        if (!std.mem.eql(u8, piece.kind(), "string_content") or literal.len != 0) return null;
        literal = piece.text(source);
    }
    return .{ .node = node, .alias = alias.?.text(source), .literal = literal };
}

/// The names a function's own parameters bind.
fn collectParameters(
    gpa: std.mem.Allocator,
    source: []const u8,
    declaration: ts.Node,
    locals: *std.ArrayList([]const u8),
) !void {
    var children = declaration.namedChildren();
    while (children.next()) |child| {
        if (!std.mem.eql(u8, child.kind(), "parameters")) continue;
        var parameters = child.namedChildren();
        while (parameters.next()) |parameter| {
            const name = parameter.childByFieldName("name") orelse continue;
            try locals.append(gpa, name.text(source));
        }
    }
}

/// Every name a function body binds anywhere: `const` and `var` declarations
/// (including destructuring), capture payloads, and parameters of nested
/// function types. Scope is ignored on purpose. Treating a binding as visible
/// everywhere in the body can only leave more calls unresolved, never resolve
/// one wrongly.
fn collectBindings(
    gpa: std.mem.Allocator,
    source: []const u8,
    node: ts.Node,
    locals: *std.ArrayList([]const u8),
    depth: u32,
) !void {
    // Calls below the depth limit are not recorded either, and a binding can
    // only shadow calls in its own block or deeper.
    if (depth >= max_depth) return;

    const kind = node.kind();
    if (std.mem.eql(u8, kind, "payload")) {
        var captures = node.namedChildren();
        while (captures.next()) |capture| {
            if (std.mem.eql(u8, capture.kind(), "identifier")) try locals.append(gpa, capture.text(source));
        }
        return;
    }
    if (std.mem.eql(u8, kind, "parameter")) {
        if (node.childByFieldName("name")) |name| try locals.append(gpa, name.text(source));
    }

    // A `const` or `var` keyword binds the identifier that follows it.
    const count = node.childCount();
    var binds_next = false;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const child = node.childAt(index) orelse continue;
        const child_kind = child.kind();
        if (isComment(child_kind)) continue;
        if (!child.isNamed()) {
            binds_next = std.mem.eql(u8, child_kind, "const") or std.mem.eql(u8, child_kind, "var");
            continue;
        }
        if (binds_next and std.mem.eql(u8, child_kind, "identifier")) {
            try locals.append(gpa, child.text(source));
        } else {
            try collectBindings(gpa, source, child, locals, depth + 1);
        }
        binds_next = false;
    }
}

fn walkCalls(
    builder: *contract.BatchBuilder,
    scope: CallScope,
    function: FunctionBody,
    locals: []const []const u8,
    node: ts.Node,
    uncovered: *Uncovered,
    too_deep: *bool,
    depth: u32,
) !void {
    if (depth >= max_depth) {
        too_deep.* = true;
        return;
    }

    const kind = node.kind();
    if (containerLabel(kind) != null) {
        // A container opens its own namespace, where a bare name may mean one
        // of its members instead.
        uncovered.note(kind, .function_body);
        return;
    }
    if (std.mem.eql(u8, kind, "call_expression")) {
        if (node.childByFieldName("function")) |callee| {
            try emitCall(builder, scope, function, locals, node, callee);
        }
    }

    var children = node.namedChildren();
    while (children.next()) |child| {
        try walkCalls(builder, scope, function, locals, child, uncovered, too_deep, depth + 1);
    }
}

fn emitCall(
    builder: *contract.BatchBuilder,
    scope: CallScope,
    function: FunctionBody,
    locals: []const []const u8,
    call: ts.Node,
    callee: ts.Node,
) !void {
    const simple = std.mem.eql(u8, callee.kind(), "identifier");
    const designator = try builder.dupe(callee.text(scope.source));
    if (designator.len == 0) return;

    const decision: CallDecision = if (simple)
        decideName(scope, locals, designator)
    else
        .{ .unresolved = "the callee is not a bare name; field, namespace, method, and computed callees are not resolved" };

    try builder.addRelationship(.{
        .kind = .calls,
        .source = .{ .entity = function.index },
        .target = switch (decision) {
            .function => |index| .{ .local = index },
            .unresolved => .{ .designator = designator },
        },
        .evidence = evidenceOf(builder, call, designator),
        .resolution = switch (decision) {
            .function => .{ .fact = .{
                .method = "bare callee naming the one top-level declaration of that name in the analyzed source unit, a function",
            } },
            .unresolved => |explanation| .{ .unresolved = .{
                .missing = .target_entity,
                .explanation = explanation,
            } },
        },
    });
}

const CallDecision = union(enum) {
    function: u32,
    unresolved: []const u8,
};

fn decideName(scope: CallScope, locals: []const []const u8, name: []const u8) CallDecision {
    for (locals) |local| {
        if (std.mem.eql(u8, local, name)) {
            return .{ .unresolved = "a parameter or local binding in the enclosing function has this name" };
        }
    }
    if (scope.using_namespace) {
        return .{ .unresolved = "the unit has a `usingnamespace` declaration, which can bring another declaration of this name into scope" };
    }

    var matches: u32 = 0;
    var function: ?u32 = null;
    for (scope.names) |entry| {
        if (!std.mem.eql(u8, entry.name, name)) continue;
        matches += 1;
        function = entry.function;
    }
    return switch (matches) {
        0 => .{ .unresolved = "no top-level declaration of this name exists in the analyzed source unit" },
        1 => if (function) |index|
            .{ .function = index }
        else
            .{ .unresolved = "the one top-level declaration of this name is not a covered function" },
        else => .{ .unresolved = "more than one top-level declaration in the analyzed source unit has this name" },
    };
}

fn addDefinition(
    builder: *contract.BatchBuilder,
    scope: model.Scope,
    node: ts.Node,
    name: []const u8,
    role: []const u8,
    container_path: []const []const u8,
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
            .container_path = container_path,
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

/// The identifier a `const` or `var` declaration binds: the first identifier
/// child, which the grammar places directly after the keyword. Anything before
/// it is a keyword or an `extern` library string.
fn declaredIdentifier(node: ts.Node) ?ts.Node {
    var children = node.namedChildren();
    while (children.next()) |child| {
        const kind = child.kind();
        if (std.mem.eql(u8, kind, "identifier")) return child;
        if (isComment(kind) or std.mem.eql(u8, kind, "string")) continue;
        return null;
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
