//! Fixture-scoped Java frontend.
//!
//! It reads Java parse nodes and contributes shared-core assertions. Java's own
//! vocabulary stays in extension payloads: the shared core learns that a
//! definition exists and what it refers to, never what a `method_declaration`
//! is. Constructs outside the declared coverage are reported as unsupported
//! rather than silently omitted.

const std = @import("std");

const core = @import("semidx_core");
const ts = @import("semidx_tree_sitter");

const model = core.model;
const contract = core.contract;

pub const grammar: ts.Grammar = .java;

pub const version = std.fmt.comptimePrint("slice-001+ts-abi{d}", .{ts.runtime_abi_version});

pub const capabilities: contract.Capabilities = .{
    .language = .java,
    .producer = .{ .name = "frontend.java", .version = version },
    .entity_roles = &.{ "class", "method" },
    .relationship_kinds = &.{ .defines, .references, .calls },
    .coverage_note = "top-level classes, their methods, method return types, " ++
        "field types, and invocations inside method bodies; a simple type name " ++
        "not declared in the unit resolves to the one current top-level class " ++
        "another unit declares in the same explicit package, unless a type " ++
        "parameter, member type, supertype, import, or non-class type could " ++
        "give the name another meaning",
};

/// Guards against unbounded recursion on pathological input. Exceeding it is
/// reported as an unsupported construct, never as an absence of invocations.
const max_depth: u32 = 64;

/// What a simple type name can mean among the other source units of one
/// explicit Java package, as read from current graph facts.
pub const Binding = union(enum) {
    /// Exactly one current top-level class of this name, in another unit.
    unique: contract.ExternalTarget,
    /// More than one, counted. The name does not identify a class, and no
    /// candidate is preferred.
    ambiguous: u32,
};

pub const TypeBinding = struct {
    name: []const u8,
    binding: Binding,
};

/// The repository context the analyzer hands this frontend for one unit.
///
/// It is a projection, not a model: the analyzer rebuilds it from the graph for
/// every analysis, and it carries no authority beyond naming candidates. An
/// empty context is what a unit analyzed on its own receives.
pub const Context = struct {
    /// The package the bindings describe. Empty when none were read.
    package: []const u8,
    /// Top-level classes other units currently declare in `package`.
    types: []const TypeBinding,

    pub const empty: Context = .{ .package = "", .types = &.{} };

    /// A binding is only an answer for the package it was read for.
    pub fn lookup(self: Context, package: []const u8, name: []const u8) ?Binding {
        if (package.len == 0 or !std.mem.eql(u8, self.package, package)) return null;
        for (self.types) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.binding;
        }
        return null;
    }
};

/// The explicit package a Java source unit declares, or null when it declares
/// none. Annotations on the declaration are not part of the name, and the name
/// is rebuilt from its identifiers, so layout inside it cannot change it.
pub fn declaredPackage(
    allocator: std.mem.Allocator,
    root: ts.Node,
    source: []const u8,
) !?[]const u8 {
    var top_level = root.namedChildren();
    while (top_level.next()) |node| {
        if (!std.mem.eql(u8, node.kind(), "package_declaration")) continue;
        var children = node.namedChildren();
        while (children.next()) |child| {
            if (!isName(child.kind())) continue;
            var name: std.ArrayList(u8) = .empty;
            errdefer name.deinit(allocator);
            if (!try appendName(allocator, &name, child, source, 0)) return null;
            return try name.toOwnedSlice(allocator);
        }
        return null;
    }
    return null;
}

fn isName(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "identifier") or std.mem.eql(u8, kind, "scoped_identifier");
}

/// Returns false when the name nests deeper than this frontend traverses.
fn appendName(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    node: ts.Node,
    source: []const u8,
    depth: u32,
) !bool {
    if (depth >= max_depth) return false;
    if (!std.mem.eql(u8, node.kind(), "scoped_identifier")) {
        try out.appendSlice(allocator, node.text(source));
        return true;
    }
    const scope = node.childByFieldName("scope") orelse return false;
    const name = node.childByFieldName("name") orelse return false;
    if (!try appendName(allocator, out, scope, source, depth + 1)) return false;
    try out.append(allocator, '.');
    try out.appendSlice(allocator, name.text(source));
    return true;
}

const ClassInfo = struct {
    index: u32,
    name: []const u8,
    node: ts.Node,
    body: ?ts.Node,
};

const MethodInfo = struct {
    index: u32,
    name: []const u8,
    class_index: u32,
    class_name: []const u8,
    node: ts.Node,
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
            "the source unit does not parse cleanly, so no Java assertions were derived from it",
        );
        return;
    }

    const gpa = builder.gpa;
    // Entities are scoped to the unit, not to where the unit currently sits.
    const scope: model.Scope = .{ .unit = input.unit.id };

    var classes: std.ArrayList(ClassInfo) = .empty;
    defer classes.deinit(gpa);
    var methods: std.ArrayList(MethodInfo) = .empty;
    defer methods.deinit(gpa);

    const package = (try declaredPackage(builder.allocator(), root, source)) orelse "";

    // Names something other than this unit's classes may give a meaning to,
    // before the same package's other units are consulted.
    var imported: std.ArrayList([]const u8) = .empty;
    defer imported.deinit(gpa);
    var other_types: std.ArrayList([]const u8) = .empty;
    defer other_types.deinit(gpa);

    // Pass 1: definitions. A relationship can only be expressed once every
    // definition in the unit has a batch-local index.
    var top_level = root.namedChildren();
    while (top_level.next()) |node| {
        const kind = node.kind();

        if (std.mem.eql(u8, kind, "package_declaration")) continue;
        if (std.mem.eql(u8, kind, "import_declaration")) {
            if (importedName(node, source)) |name| try imported.append(gpa, name);
        } else if (isTypeDeclaration(kind)) {
            if (node.childByFieldName("name")) |name_node| {
                if (!std.mem.eql(u8, kind, "class_declaration")) try other_types.append(gpa, name_node.text(source));
            }
        }
        if (!std.mem.eql(u8, kind, "class_declaration")) {
            try builder.addDiagnostic(.unsupported_construct, try builder.print(
                "`{s}` at the top level is outside this frontend's coverage",
                .{kind},
            ));
            continue;
        }

        const name_node = node.childByFieldName("name") orelse {
            try builder.addDiagnostic(
                .unsupported_construct,
                "a class declaration without a name is outside this frontend's coverage",
            );
            continue;
        };
        const name = try builder.dupe(name_node.text(source));

        const index = try builder.addEntity(.{
            .kind = .definition,
            .identity = .{
                .scope = scope,
                .language = .java,
                .role = "class",
                .name = name,
                .signature = name,
                .container_path = &.{},
            },
            .evidence = evidenceOf(builder, node, name),
            .extension = .{
                .namespace = "java",
                .labels = try builder.labels(&.{
                    .{ .key = "java.construct", .value = "class_declaration" },
                    .{ .key = "java.package", .value = package },
                }),
            },
            .resolution = .{ .fact = .{
                .method = "class declaration in the analyzed source unit",
            } },
        });

        const body = node.childByFieldName("body");
        try classes.append(gpa, .{ .index = index, .name = name, .node = node, .body = body });

        const class_body = body orelse continue;
        var members = class_body.namedChildren();
        while (members.next()) |member| {
            const member_kind = member.kind();
            if (!std.mem.eql(u8, member_kind, "method_declaration")) {
                try builder.addDiagnostic(.unsupported_construct, try builder.print(
                    "`{s}` inside `{s}` is outside this frontend's coverage",
                    .{ member_kind, name },
                ));
                continue;
            }

            const method_name_node = member.childByFieldName("name") orelse continue;
            const method_name = try builder.dupe(method_name_node.text(source));
            const signature = try methodSignature(builder, source, method_name, member);
            const return_type = if (member.childByFieldName("type")) |type_node|
                try builder.dupe(type_node.text(source))
            else
                "";

            const method_index = try builder.addEntity(.{
                .kind = .definition,
                .identity = .{
                    .scope = scope,
                    .language = .java,
                    .role = "method",
                    .name = method_name,
                    .signature = signature,
                    .container_path = try builder.dupeSlice(&.{name}),
                },
                .evidence = evidenceOf(builder, member, method_name),
                .extension = .{
                    .namespace = "java",
                    .labels = try builder.labels(&.{
                        .{ .key = "java.construct", .value = "method_declaration" },
                        .{ .key = "java.return_type", .value = return_type },
                        .{ .key = "java.package", .value = package },
                    }),
                },
                .resolution = .{ .fact = .{
                    .method = "method declaration in the analyzed source unit",
                } },
            });

            try methods.append(gpa, .{
                .index = method_index,
                .name = method_name,
                .class_index = index,
                .class_name = name,
                .node = member,
            });
        }
    }

    if (classes.items.len == 0) {
        try builder.addDiagnostic(
            .confirmed_absence,
            "the source unit parsed and declares no class within this frontend's coverage",
        );
    }

    const unit_scope: UnitScope = .{
        .package = package,
        .classes = classes.items,
        .imported = imported.items,
        .other_types = other_types.items,
        .context = context,
    };

    // Pass 2: relationships.
    for (classes.items) |class| {
        try builder.addRelationship(.{
            .kind = .defines,
            .source = .unit_container,
            .target = .{ .local = class.index },
            .evidence = evidenceOf(builder, class.node, class.name),
            .resolution = .{ .fact = .{
                .method = "declared directly in this source unit",
            } },
        });

        const body = class.body orelse continue;
        var members = body.namedChildren();
        while (members.next()) |member| {
            if (!std.mem.eql(u8, member.kind(), "field_declaration")) continue;
            const type_node = member.childByFieldName("type") orelse continue;
            try emitTypeReference(builder, source, class.index, type_node, .{
                .unit = unit_scope,
                .class = class,
                .method = null,
            });
        }
    }

    for (methods.items) |method| {
        try builder.addRelationship(.{
            .kind = .defines,
            .source = .{ .entity = method.class_index },
            .target = .{ .local = method.index },
            .evidence = evidenceOf(builder, method.node, method.name),
            .resolution = .{ .fact = .{
                .method = "declared directly in this class body",
            } },
        });

        if (method.node.childByFieldName("type")) |type_node| {
            try emitTypeReference(builder, source, method.index, type_node, .{
                .unit = unit_scope,
                .class = classByIndex(classes.items, method.class_index),
                .method = method.node,
            });
        }

        const body = method.node.childByFieldName("body") orelse continue;
        try emitInvocations(builder, source, method, body, methods.items, 0);
    }
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

fn methodSignature(
    builder: *contract.BatchBuilder,
    source: []const u8,
    name: []const u8,
    node: ts.Node,
) ![]const u8 {
    const parameters = node.childByFieldName("parameters") orelse
        return builder.print("{s}()", .{name});

    var types: std.ArrayList(u8) = .empty;
    defer types.deinit(builder.gpa);

    var children = parameters.namedChildren();
    var first = true;
    while (children.next()) |parameter| {
        const type_node = parameter.childByFieldName("type") orelse continue;
        if (!first) try types.append(builder.gpa, ',');
        try types.appendSlice(builder.gpa, type_node.text(source));
        first = false;
    }
    return builder.print("{s}({s})", .{ name, types.items });
}

/// What a type reference can be resolved against, for the whole unit.
const UnitScope = struct {
    /// Empty for the default package.
    package: []const u8,
    classes: []const ClassInfo,
    /// Simple names brought in by single-type and single static imports.
    imported: []const []const u8,
    /// Top-level interfaces, enums, records, and annotation types. This
    /// frontend does not cover them, but they still claim their names.
    other_types: []const []const u8,
    context: Context,
};

/// Where one type reference sits.
const TypeScope = struct {
    unit: UnitScope,
    class: ClassInfo,
    /// The method whose return type is being read, if any.
    method: ?ts.Node,
};

const TypeResolution = struct {
    target: contract.DraftTarget,
    resolution: model.Resolution,
    /// Set when the target was read from another unit.
    provider: ?model.SourceUnitId = null,
};

fn emitTypeReference(
    builder: *contract.BatchBuilder,
    source: []const u8,
    from: u32,
    type_node: ts.Node,
    scope: TypeScope,
) !void {
    if (std.mem.eql(u8, type_node.kind(), "void_type")) return;
    const name = try builder.dupe(type_node.text(source));
    const resolved = try resolveType(builder, source, type_node, name, scope);
    try builder.addRelationship(.{
        .kind = .references,
        .source = .{ .entity = from },
        .target = resolved.target,
        .evidence = evidenceOf(builder, type_node, name),
        .resolution = resolved.resolution,
    });
    if (resolved.provider) |provider| try declareProvider(builder, provider);
}

/// Resolves a type name the way ADR 004 permits and no further.
///
/// A name declared in the unit is a local fact, as before. Otherwise only a
/// simple name in a unit with an explicit package may reach another unit, and
/// only after ruling out everything Java would let take precedence over a type
/// of the same package: a type parameter, a member type (declared or
/// inherited), a single-type or static import, and a type declared in this
/// unit. When one of those cannot be ruled out the name stays unresolved and
/// says why, because a same-package match that ignored them would be a string
/// match wearing the face of a fact.
fn resolveType(
    builder: *contract.BatchBuilder,
    source: []const u8,
    type_node: ts.Node,
    name: []const u8,
    scope: TypeScope,
) !TypeResolution {
    const unit = scope.unit;
    if (findClass(unit.classes, name)) |index| return .{
        .target = .{ .local = index },
        .resolution = .{ .fact = .{ .method = "type name declared in the analyzed source unit" } },
    };

    const kind = type_node.kind();
    if (std.mem.eql(u8, kind, "scoped_type_identifier")) {
        return unresolvedType(name, "a qualified type name is not resolved beyond the analyzed source unit");
    }
    if (!std.mem.eql(u8, kind, "type_identifier")) {
        return unresolvedType(name, "the type is not declared in the analyzed source unit");
    }
    if (unit.package.len == 0) {
        return unresolvedType(name, "the type is not declared in the analyzed source unit, " ++
            "and a unit without a package declaration resolves nothing beyond itself");
    }
    if (scope.method) |method| {
        if (declaresTypeParameter(method, source, name)) {
            return unresolvedType(name, "the name is a type parameter of the enclosing method");
        }
    }
    if (declaresTypeParameter(scope.class.node, source, name)) {
        return unresolvedType(name, "the name is a type parameter of the enclosing class");
    }
    if (declaresMemberType(scope.class.body, source, name)) {
        return unresolvedType(name, "the enclosing class declares a member type of this name, " ++
            "which this frontend does not cover");
    }
    if (scope.class.node.childByFieldName("superclass") != null or
        scope.class.node.childByFieldName("interfaces") != null)
    {
        return unresolvedType(name, "the enclosing class has supertypes, and a member type " ++
            "it may inherit under this name is not resolved");
    }
    if (containsName(unit.imported, name)) {
        return unresolvedType(name, "an import names this type, and imports are not resolved");
    }
    if (containsName(unit.other_types, name)) {
        return unresolvedType(name, "the analyzed source unit declares a non-class type of this name, " ++
            "which this frontend does not cover");
    }

    const binding = unit.context.lookup(unit.package, name) orelse
        return unresolvedType(name, try builder.print(
            "no current top-level class of this name is declared in package `{s}`; " ++
                "imports and other packages are not resolved",
            .{unit.package},
        ));
    return switch (binding) {
        .unique => |target| .{
            .target = .{ .external = target },
            .resolution = .{ .fact = .{
                .method = "the only current top-level class of this simple name in the same explicit package",
            } },
            .provider = target.provider,
        },
        .ambiguous => |count| unresolvedType(name, try builder.print(
            "{d} current top-level classes of this name are declared in package `{s}`, " ++
                "so the name is ambiguous",
            .{ count, unit.package },
        )),
    };
}

fn unresolvedType(name: []const u8, explanation: []const u8) TypeResolution {
    return .{
        .target = .{ .designator = name },
        .resolution = .{ .unresolved = .{ .missing = .target_entity, .explanation = explanation } },
    };
}

fn declareProvider(builder: *contract.BatchBuilder, provider: model.SourceUnitId) !void {
    for (builder.dependencies.items) |declared| {
        if (declared.provider == provider) return;
    }
    try builder.addDependency(
        provider,
        "resolved a simple type name to a top-level class declared in the same Java package",
    );
}

fn isTypeDeclaration(kind: []const u8) bool {
    const kinds = [_][]const u8{
        "class_declaration",
        "interface_declaration",
        "enum_declaration",
        "record_declaration",
        "annotation_type_declaration",
    };
    for (kinds) |candidate| {
        if (std.mem.eql(u8, kind, candidate)) return true;
    }
    return false;
}

/// The simple name a non-wildcard import brings into scope. Static imports
/// count: a single static import can import a member type.
fn importedName(node: ts.Node, source: []const u8) ?[]const u8 {
    var name: ?ts.Node = null;
    var children = node.namedChildren();
    while (children.next()) |child| {
        const kind = child.kind();
        if (std.mem.eql(u8, kind, "asterisk")) return null;
        if (isName(kind)) name = child;
    }
    const found = name orelse return null;
    if (std.mem.eql(u8, found.kind(), "scoped_identifier")) {
        const last = found.childByFieldName("name") orelse return null;
        return last.text(source);
    }
    return found.text(source);
}

fn declaresTypeParameter(declaration: ts.Node, source: []const u8, name: []const u8) bool {
    const parameters = declaration.childByFieldName("type_parameters") orelse return false;
    var children = parameters.namedChildren();
    while (children.next()) |parameter| {
        var parts = parameter.namedChildren();
        while (parts.next()) |part| {
            if (!std.mem.eql(u8, part.kind(), "type_identifier")) continue;
            if (std.mem.eql(u8, part.text(source), name)) return true;
        }
    }
    return false;
}

fn declaresMemberType(body: ?ts.Node, source: []const u8, name: []const u8) bool {
    const class_body = body orelse return false;
    var members = class_body.namedChildren();
    while (members.next()) |member| {
        if (!isTypeDeclaration(member.kind())) continue;
        const member_name = member.childByFieldName("name") orelse continue;
        if (std.mem.eql(u8, member_name.text(source), name)) return true;
    }
    return false;
}

fn containsName(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

fn classByIndex(classes: []const ClassInfo, index: u32) ClassInfo {
    for (classes) |class| {
        if (class.index == index) return class;
    }
    unreachable;
}

fn emitInvocations(
    builder: *contract.BatchBuilder,
    source: []const u8,
    method: MethodInfo,
    node: ts.Node,
    methods: []const MethodInfo,
    depth: u32,
) !void {
    if (depth >= max_depth) {
        try builder.addDiagnostic(
            .unsupported_construct,
            "a method body nested deeper than this frontend traverses was not analyzed for invocations",
        );
        return;
    }

    if (std.mem.eql(u8, node.kind(), "method_invocation")) {
        try emitInvocation(builder, source, method, node, methods);
    }

    var children = node.namedChildren();
    while (children.next()) |child| {
        try emitInvocations(builder, source, method, child, methods, depth + 1);
    }
}

fn emitInvocation(
    builder: *contract.BatchBuilder,
    source: []const u8,
    method: MethodInfo,
    node: ts.Node,
    methods: []const MethodInfo,
) !void {
    const name_node = node.childByFieldName("name") orelse return;
    const name = try builder.dupe(name_node.text(source));

    // A qualified invocation names a receiver this frontend does not analyze,
    // so its target stays a designator carrying the text that was read.
    const qualified = node.childByFieldName("object") != null;
    const resolved = if (qualified) null else findMethod(methods, method.class_name, name);
    const designator = if (qualified) try builder.dupe(node.text(source)) else name;

    try builder.addRelationship(.{
        .kind = .calls,
        .source = .{ .entity = method.index },
        .target = if (resolved) |index| .{ .local = index } else .{ .designator = designator },
        .evidence = evidenceOf(builder, node, designator),
        .resolution = if (resolved != null)
            .{ .fact = .{
                .method = "unqualified invocation of a method declared in the same class",
            } }
        else if (qualified)
            .{ .unresolved = .{
                .missing = .target_entity,
                .explanation = "the invocation is qualified by a receiver this frontend does not resolve",
            } }
        else
            .{ .unresolved = .{
                .missing = .target_entity,
                .explanation = "no method of this name is declared in the enclosing class",
            } },
    });
}

fn findClass(classes: []const ClassInfo, name: []const u8) ?u32 {
    for (classes) |class| {
        if (std.mem.eql(u8, class.name, name)) return class.index;
    }
    return null;
}

fn findMethod(methods: []const MethodInfo, class_name: []const u8, name: []const u8) ?u32 {
    for (methods) |method| {
        if (!std.mem.eql(u8, method.class_name, class_name)) continue;
        if (std.mem.eql(u8, method.name, name)) return method.index;
    }
    return null;
}
