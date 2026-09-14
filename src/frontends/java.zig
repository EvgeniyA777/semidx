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
        "field types, and invocations inside method bodies",
};

/// Guards against unbounded recursion on pathological input. Exceeding it is
/// reported as an unsupported construct, never as an absence of invocations.
const max_depth: u32 = 64;

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
    const scope = try builder.dupe(input.unit.path);

    var classes: std.ArrayList(ClassInfo) = .empty;
    defer classes.deinit(gpa);
    var methods: std.ArrayList(MethodInfo) = .empty;
    defer methods.deinit(gpa);

    var package: []const u8 = "";

    // Pass 1: definitions. A relationship can only be expressed once every
    // definition in the unit has a batch-local index.
    var top_level = root.namedChildren();
    while (top_level.next()) |node| {
        const kind = node.kind();

        if (std.mem.eql(u8, kind, "package_declaration")) {
            package = try builder.dupe(packageName(node, source));
            continue;
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
            try emitTypeReference(builder, source, class.index, type_node, classes.items);
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
            try emitTypeReference(builder, source, method.index, type_node, classes.items);
        }

        const body = method.node.childByFieldName("body") orelse continue;
        try emitInvocations(builder, source, method, body, methods.items, 0);
    }
}

fn packageName(node: ts.Node, source: []const u8) []const u8 {
    var children = node.namedChildren();
    if (children.next()) |identifier| return identifier.text(source);
    return "";
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

fn emitTypeReference(
    builder: *contract.BatchBuilder,
    source: []const u8,
    from: u32,
    type_node: ts.Node,
    classes: []const ClassInfo,
) !void {
    if (std.mem.eql(u8, type_node.kind(), "void_type")) return;
    const name = try builder.dupe(type_node.text(source));
    const resolved = findClass(classes, name);
    try builder.addRelationship(.{
        .kind = .references,
        .source = .{ .entity = from },
        .target = if (resolved) |index| .{ .local = index } else .{ .designator = name },
        .evidence = evidenceOf(builder, type_node, name),
        .resolution = if (resolved != null)
            .{ .fact = .{ .method = "type name declared in the analyzed source unit" } }
        else
            .{ .unresolved = .{
                .missing = .target_entity,
                .explanation = "the type is not declared in the analyzed source unit",
            } },
    });
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
