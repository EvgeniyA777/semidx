//! Developer-only measurement command: what the Java supertype guard and the
//! value-receiver family would cost and buy.
//!
//! [Plan 014](../docs/plans/014_java_receiver_coverage.md) Stage 0 has to price
//! two families before any code is written, and neither price can be read from
//! the graph alone. The hierarchy the guard protects against is not recorded —
//! a class definition says *whether* it declares supertypes and never *which* —
//! and a Java interface is not a definition at all. So this command reads the
//! graph for the claim families and the **source** for the hierarchy, and says
//! how much of each family a recorded hierarchy could convert.
//!
//! It is not a lane and not a conformance check. `zig build test`,
//! `zig build test-mcp`, `zig build dogfood` and `zig build preview-gate` do not
//! build it, and no test asserts against its output.
//!
//! **The report is reproducible without this program.** The procedure, in full:
//!
//! 1. Index the root and publish one snapshot. Report definitions, recorded
//!    assertions, current facts, unresolved, approximate, stale, and
//!    diagnostics by kind.
//! 2. Build a **source model** of every Java unit found by the same scan, by
//!    parsing each one with the same tree-sitter Java grammar the frontend uses:
//!    * its declared package, and the Java source root
//!      ([ADR 008](../docs/adr/008_java_visibility_boundaries.md)) that is what
//!      remains of its path once the package directories and the file name are
//!      stripped;
//!    * its single-type imports;
//!    * every **top-level** type declaration: name, kind (class, interface,
//!      enum, record, annotation type), the methods it declares with their
//!      access and `static`, the member types it declares, and the supertypes
//!      it writes — the `superclass` field, the `interfaces` field, and the
//!      `extends_interfaces` child, each read down to a base name and a shape
//!      (`simple`, `generic`, `qualified`, `other`).
//! 3. Resolve a simple type name from a referring unit the way ADR 004 and
//!    ADR 008 permit: a top-level declaration in the unit itself wins; then a
//!    single-type import of the name, whose answer is final either way; then
//!    the unit's own explicit package. A candidate counts only when its source
//!    root shares scope with the referring unit's. Exactly one visible
//!    candidate is a declaration, more than one is `ambiguous`, none visible
//!    with candidates elsewhere is `out_of_scope`, and none at all is `none`.
//! 4. Walk the declared hierarchy from a starting type, depth-first, with a
//!    path stack for cycle detection and a hard depth cap of 16. A chain is
//!    **closed** when every supertype on every reachable type resolves by
//!    step 3 to a top-level class or interface. Anything else leaves it open
//!    and names the first condition that failed.
//!    Two bounds are reported. The **lenient** bound reads the base name of a
//!    generic supertype (`implements List<String>` follows `List`); it is the
//!    upper bound Plan 014 Gate A is measured on, and it checks neither member
//!    types, nor access, nor staleness, nor the real resolution of each name.
//!    The **strict** bound leaves a chain open at any supertype that is not a
//!    bare `type_identifier`, which is what today's unchanged `resolveType`
//!    would answer.
//! 5. Take every unresolved claim the guard declined, by matching the
//!    frontend's own words:
//!    * a `references` claim containing "the enclosing class has supertypes,
//!      and a member type";
//!    * a `calls` claim containing "the enclosing class has supertypes, and a
//!      field it may inherit" — the receiver side;
//!    * a `calls` claim containing "the enclosing class has supertypes, and a
//!      method of this name it may inherit" — the unqualified side, counted
//!      apart because Plan 014's gate arithmetic is over the first two.
//!    Find the enclosing type of each: the claim's source entity is the class
//!    itself, or a method whose `container_path` names it. Walk that type's
//!    chain by step 4.
//! 6. Take every unresolved `calls` claim containing "is declared here as a
//!    binding, so it is read as a value", read the receiver name from between
//!    the backticks in its own explanation and the invoked method name from its
//!    designator, locate the invocation in the parse tree by the start byte of
//!    its evidence, and classify it against the conditions Plan 014 D10 lists,
//!    in order. It is reported twice: as it stands, and as it would stand if
//!    the enclosing class's supertype guard were lifted.
//! 7. Report the fan-out inputs: the distribution of chain depth and of how
//!    many types a chain visits, and the largest number of distinct reader
//!    units a single type would owe a reanalysis under Plan 014 D7.
//!
//! Nothing here decides anything about the graph. It is a classification of
//! claims the graph already holds, against a model of the source those claims
//! were read from.

const std = @import("std");
const semidx = @import("semidx");

const model = semidx.model;
const ts = semidx.ts;
const java = semidx.frontends.java;

/// Plan 014 D5. A walk that reaches it declines with its own reason.
const max_chain_depth: u32 = 16;

/// The same guard against pathological nesting the Java frontend carries.
const max_walk_depth: u32 = 64;

// -- the words the frontend uses ------------------------------------------
//
// Matching the frontend's own explanations is what keeps a family countable
// without re-deriving it: rewording a reason in `src/frontends/java.zig` makes
// its claims disappear from a row here, which is visible, rather than moving
// them somewhere plausible, which is not.

const guard_reference_words = "the enclosing class has supertypes, and a member type";
const guard_receiver_words = "the enclosing class has supertypes, and a field it may inherit";
const guard_unqualified_words = "the enclosing class has supertypes, and a method of this name it may inherit";
const receiver_bound_words = "is declared here as a binding, so it is read as a value";

// -- the source model ------------------------------------------------------

const TypeKind = enum {
    class,
    interface,
    enum_type,
    record,
    annotation,

    fn fromNodeKind(kind: []const u8) ?TypeKind {
        if (std.mem.eql(u8, kind, "class_declaration")) return .class;
        if (std.mem.eql(u8, kind, "interface_declaration")) return .interface;
        if (std.mem.eql(u8, kind, "enum_declaration")) return .enum_type;
        if (std.mem.eql(u8, kind, "record_declaration")) return .record;
        if (std.mem.eql(u8, kind, "annotation_type_declaration")) return .annotation;
        return null;
    }

    /// A supertype chain is classes and interfaces and nothing else: no enum,
    /// record, or annotation type can appear in one (Plan 014 Non-Scope).
    fn inChain(self: TypeKind) bool {
        return self == .class or self == .interface;
    }

    fn tag(self: TypeKind) []const u8 {
        return switch (self) {
            .class => "class",
            .interface => "interface",
            .enum_type => "enum",
            .record => "record",
            .annotation => "annotation",
        };
    }
};

/// How a type was written where a name was expected.
const TypeShape = enum { simple, generic, qualified, other };

const TypeName = struct {
    name: []const u8,
    shape: TypeShape,
};

/// The base name a type node writes, and how it wrote it.
///
/// `List<String>` writes `List` generically, `a.b.C` writes `C` qualified, and
/// an array or a primitive writes no name this measurement can follow.
fn readTypeName(node: ts.Node, source: []const u8) TypeName {
    const kind = node.kind();
    if (std.mem.eql(u8, kind, "type_identifier")) {
        return .{ .name = node.text(source), .shape = .simple };
    }
    if (std.mem.eql(u8, kind, "generic_type")) {
        var children = node.namedChildren();
        while (children.next()) |child| {
            const inner = readTypeName(child, source);
            if (inner.shape == .other) continue;
            return .{
                .name = inner.name,
                .shape = if (inner.shape == .qualified) .qualified else .generic,
            };
        }
        return .{ .name = "", .shape = .other };
    }
    if (std.mem.eql(u8, kind, "annotated_type")) {
        var found: TypeName = .{ .name = "", .shape = .other };
        var children = node.namedChildren();
        while (children.next()) |child| {
            const inner = readTypeName(child, source);
            if (inner.shape != .other) found = inner;
        }
        return found;
    }
    if (std.mem.eql(u8, kind, "scoped_type_identifier")) {
        var last: []const u8 = "";
        var children = node.namedChildren();
        while (children.next()) |child| {
            if (std.mem.eql(u8, child.kind(), "type_identifier")) last = child.text(source);
        }
        return .{ .name = last, .shape = .qualified };
    }
    return .{ .name = "", .shape = .other };
}

const Supertype = struct {
    name: []const u8,
    shape: TypeShape,
    /// Written in an `implements` or `extends`-interfaces position, which is
    /// where an interface is named.
    interface_position: bool,
};

const MethodDecl = struct {
    name: []const u8,
    access: java.Access,
    is_static: bool,
};

const TypeDecl = struct {
    unit: u32,
    name: []const u8,
    kind: TypeKind,
    supertypes: []const Supertype,
    methods: []const MethodDecl,
    member_types: []const []const u8,
};

const UnitModel = struct {
    path: []const u8,
    package: []const u8,
    /// Null when the path does not spell the declared package, which under
    /// ADR 008 means the unit resolves nothing beyond itself.
    source_root: ?[]const u8,
    imports: []const java.SingleTypeImport,
    /// Indices into `World.decls`, for the unit's top-level declarations only.
    types: []const u32,
};

/// The declared modifiers of a member, as written.
///
/// It mirrors `modifiersOf` in `src/frontends/java.zig`, with the one addition
/// Plan 014 D2 makes: a member declared in an interface body with no access
/// keyword is `public`, because that is what Java defines it to be.
fn modifiersOf(node: ts.Node, in_interface: bool) MethodDecl {
    var access: java.Access = if (in_interface) .public else .package_private;
    // A method declared in an interface is implicitly public and never
    // implicitly static, and `default` and `abstract` change neither.
    var is_static = false;
    var index: u32 = 0;
    while (index < node.childCount()) : (index += 1) {
        const child = node.childAt(index) orelse continue;
        if (!std.mem.eql(u8, child.kind(), "modifiers")) continue;
        var keyword: u32 = 0;
        while (keyword < child.childCount()) : (keyword += 1) {
            const token = child.childAt(keyword) orelse continue;
            const text = token.kind();
            if (std.mem.eql(u8, text, "public")) {
                access = .public;
            } else if (std.mem.eql(u8, text, "protected")) {
                access = .protected;
            } else if (std.mem.eql(u8, text, "private")) {
                access = .private;
            } else if (std.mem.eql(u8, text, "static")) {
                is_static = true;
            }
        }
        break;
    }
    return .{ .name = "", .access = access, .is_static = is_static };
}

fn bodyOf(node: ts.Node) ?ts.Node {
    return node.childByFieldName("body");
}

fn appendTypeList(
    arena: std.mem.Allocator,
    out: *std.ArrayList(Supertype),
    holder: ts.Node,
    source: []const u8,
    interface_position: bool,
) !void {
    var children = holder.namedChildren();
    while (children.next()) |child| {
        if (std.mem.eql(u8, child.kind(), "type_list")) {
            var types = child.namedChildren();
            while (types.next()) |entry| {
                const read = readTypeName(entry, source);
                try out.append(arena, .{
                    .name = read.name,
                    .shape = read.shape,
                    .interface_position = interface_position,
                });
            }
            continue;
        }
        const read = readTypeName(child, source);
        if (read.shape == .other and read.name.len == 0 and
            std.mem.eql(u8, child.kind(), "annotation")) continue;
        try out.append(arena, .{
            .name = read.name,
            .shape = read.shape,
            .interface_position = interface_position,
        });
    }
}

fn collectSupertypes(
    arena: std.mem.Allocator,
    node: ts.Node,
    source: []const u8,
) ![]const Supertype {
    var found: std.ArrayList(Supertype) = .empty;
    if (node.childByFieldName("superclass")) |superclass| {
        try appendTypeList(arena, &found, superclass, source, false);
    }
    if (node.childByFieldName("interfaces")) |interfaces| {
        try appendTypeList(arena, &found, interfaces, source, true);
    }
    // An interface writes its supertypes as an `extends_interfaces` child
    // rather than as a field, so it is not reachable by field name.
    var children = node.namedChildren();
    while (children.next()) |child| {
        if (!std.mem.eql(u8, child.kind(), "extends_interfaces")) continue;
        try appendTypeList(arena, &found, child, source, true);
    }
    return found.toOwnedSlice(arena);
}

fn collectMembers(
    arena: std.mem.Allocator,
    node: ts.Node,
    source: []const u8,
    kind: TypeKind,
    methods: *std.ArrayList(MethodDecl),
    member_types: *std.ArrayList([]const u8),
) !void {
    const body = bodyOf(node) orelse return;
    const in_interface = kind == .interface;
    var members = body.namedChildren();
    while (members.next()) |member| {
        const member_kind = member.kind();
        if (std.mem.eql(u8, member_kind, "method_declaration")) {
            const name_node = member.childByFieldName("name") orelse continue;
            var declared = modifiersOf(member, in_interface);
            declared.name = name_node.text(source);
            try methods.append(arena, declared);
            continue;
        }
        if (TypeKind.fromNodeKind(member_kind) != null) {
            if (member.childByFieldName("name")) |name_node| {
                try member_types.append(arena, name_node.text(source));
            }
        }
    }
}

// -- the world -------------------------------------------------------------

const World = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    units: []UnitModel,
    decls: []TypeDecl,
    /// Every declaration index carrying one simple name.
    by_name: std.StringHashMapUnmanaged([]const u32),

    fn declsNamed(self: *const World, name: []const u8) []const u32 {
        return self.by_name.get(name) orelse &.{};
    }
};

const Resolution = union(enum) {
    decl: u32,
    none,
    ambiguous,
    out_of_scope,
};

/// What a simple name reaches from `from`, under ADR 004 and ADR 008.
fn resolveSimpleName(world: *const World, from: u32, name: []const u8) Resolution {
    if (name.len == 0) return .none;
    const unit = world.units[from];

    for (unit.types) |index| {
        if (std.mem.eql(u8, world.decls[index].name, name)) return .{ .decl = index };
    }

    for (unit.imports) |imported| {
        if (!std.mem.eql(u8, imported.name, name)) continue;
        // A single-type import beats the unit's own package, and its answer is
        // final either way: a name Java takes from an import does not fall back.
        return resolveInPackage(world, from, name, imported.package, false);
    }

    if (unit.package.len == 0) return .none;
    return resolveInPackage(world, from, name, unit.package, true);
}

fn resolveInPackage(
    world: *const World,
    from: u32,
    name: []const u8,
    package: []const u8,
    skip_own_unit: bool,
) Resolution {
    const referring = world.units[from].source_root;
    var visible: u32 = 0;
    var elsewhere: u32 = 0;
    var found: u32 = 0;
    for (world.declsNamed(name)) |index| {
        const decl = world.decls[index];
        if (skip_own_unit and decl.unit == from) continue;
        const provider = world.units[decl.unit];
        if (!std.mem.eql(u8, provider.package, package)) continue;
        const provider_root = provider.source_root orelse {
            elsewhere += 1;
            continue;
        };
        const referring_root = referring orelse {
            elsewhere += 1;
            continue;
        };
        if (!java.sharesScope(referring_root, provider_root)) {
            elsewhere += 1;
            continue;
        }
        if (visible == 0) found = index;
        visible += 1;
    }
    if (visible == 1) return .{ .decl = found };
    if (visible > 1) return .ambiguous;
    if (elsewhere > 0) return .out_of_scope;
    return .none;
}

// -- the hierarchy walk ----------------------------------------------------

const ChainReason = enum {
    closed,
    unresolved_supertype,
    ambiguous_supertype,
    out_of_scope_supertype,
    non_chain_supertype,
    supertype_not_simple,
    cycle,
    depth_cap,

    fn tag(self: ChainReason) []const u8 {
        return @tagName(self);
    }
};

const ChainOutcome = struct {
    reason: ChainReason,
    /// The deepest link the walk reached.
    depth: u32,
    /// Distinct types the walk visited, the starting type included.
    visited: u32,
    /// Whether any type the walk reached is an interface.
    uses_interface: bool,

    fn closed(self: ChainOutcome) bool {
        return self.reason == .closed;
    }
};

const Walker = struct {
    world: *const World,
    strict: bool,
    visited: std.ArrayList(u32),
    path: std.ArrayList(u32),
    gpa: std.mem.Allocator,
    depth: u32,
    uses_interface: bool,

    fn reset(self: *Walker) void {
        self.visited.clearRetainingCapacity();
        self.path.clearRetainingCapacity();
        self.depth = 0;
        self.uses_interface = false;
    }

    fn walk(self: *Walker, start: u32) !ChainOutcome {
        self.reset();
        const reason = try self.descend(start, 0);
        return .{
            .reason = reason,
            .depth = self.depth,
            .visited = @intCast(self.visited.items.len),
            .uses_interface = self.uses_interface,
        };
    }

    fn descend(self: *Walker, at: u32, depth: u32) !ChainReason {
        if (depth > self.depth) self.depth = depth;
        if (depth >= max_chain_depth) return .depth_cap;
        if (std.mem.indexOfScalar(u32, self.path.items, at) != null) return .cycle;
        if (std.mem.indexOfScalar(u32, self.visited.items, at) == null) {
            try self.visited.append(self.gpa, at);
        }
        const decl = self.world.decls[at];
        if (decl.kind == .interface) self.uses_interface = true;

        try self.path.append(self.gpa, at);
        defer _ = self.path.pop();

        for (decl.supertypes) |supertype| {
            if (self.strict and supertype.shape != .simple) return .supertype_not_simple;
            if (supertype.shape == .qualified or supertype.shape == .other) return .supertype_not_simple;
            switch (resolveSimpleName(self.world, decl.unit, supertype.name)) {
                .none => return .unresolved_supertype,
                .ambiguous => return .ambiguous_supertype,
                .out_of_scope => return .out_of_scope_supertype,
                .decl => |index| {
                    if (!self.world.decls[index].kind.inChain()) return .non_chain_supertype;
                    const reason = try self.descend(index, depth + 1);
                    if (reason != .closed) return reason;
                },
            }
        }
        return .closed;
    }
};

// -- counters --------------------------------------------------------------

/// One family of guard-declined claims, classified by what its chain does.
const GuardTally = struct {
    total: usize = 0,
    /// The enclosing type could not be found in the source model. It is
    /// counted apart rather than folded into an open chain.
    no_enclosing_type: usize = 0,
    /// The enclosing type declares no supertype the model could read, which
    /// would mean the guard fired on something this model cannot see.
    no_supertypes: usize = 0,
    lenient_closed: usize = 0,
    lenient_closed_with_interface: usize = 0,
    strict_closed: usize = 0,
    strict_closed_with_interface: usize = 0,
    /// By the first condition that left the chain open, lenient mode.
    lenient_reasons: [8]usize = [_]usize{0} ** 8,
    strict_reasons: [8]usize = [_]usize{0} ** 8,
};

/// Where a value-receiver call stops, in the order Plan 014 D10 asks.
const ReceiverStop = enum {
    addressable,
    binding_not_found,
    uncovered_introducer,
    uncovered_type_shape,
    type_parameter,
    member_type_of_enclosing,
    static_import_of_name,
    enclosing_supertypes_guard,
    receiver_type_none,
    receiver_type_ambiguous,
    receiver_type_out_of_scope,
    target_not_a_chain_type,
    target_is_interface,
    target_chain_open,
    target_name_in_chain,
    target_no_method,
    target_overloaded,
    target_inaccessible,
    nested_class_body,
    invocation_not_located,

    fn tag(self: ReceiverStop) []const u8 {
        return @tagName(self);
    }
};

const stop_count = std.enums.values(ReceiverStop).len;

// -- pending value-receiver claims ----------------------------------------

const PendingCall = struct {
    /// The byte the invocation node starts at, from the claim's evidence.
    start_byte: u32,
    /// The method name the invocation writes, from the claim's designator.
    method: []const u8,
    /// The receiver name, read from the frontend's own explanation.
    receiver: []const u8,
    located: bool = false,
};

/// The receiver name the decline names, which the frontend writes between
/// backticks: "the receiver name `x` is declared here as a binding...".
fn receiverNameOf(explanation: []const u8) ?[]const u8 {
    const open = std.mem.indexOfScalar(u8, explanation, '`') orelse return null;
    const rest = explanation[open + 1 ..];
    const close = std.mem.indexOfScalar(u8, rest, '`') orelse return null;
    if (close == 0) return null;
    return rest[0..close];
}

// -- binding environment ---------------------------------------------------

const Introducer = enum { field, parameter, local, uncovered };

const Binding = struct {
    name: []const u8,
    introducer: Introducer,
    type_name: []const u8,
    shape: TypeShape,
};

fn typeOfDeclaration(node: ts.Node, source: []const u8) TypeName {
    const type_node = node.childByFieldName("type") orelse
        return .{ .name = "", .shape = .other };
    return readTypeName(type_node, source);
}

fn appendDeclarators(
    gpa: std.mem.Allocator,
    into: *std.ArrayList(Binding),
    declaration: ts.Node,
    source: []const u8,
    introducer: Introducer,
) !void {
    const declared = typeOfDeclaration(declaration, source);
    var children = declaration.namedChildren();
    while (children.next()) |child| {
        if (!std.mem.eql(u8, child.kind(), "variable_declarator")) continue;
        const name = child.childByFieldName("name") orelse continue;
        // `String x[]` declares an array however its type node reads, so the
        // declarator's own dimensions make the shape uncovered.
        const shape: TypeShape = if (child.childByFieldName("dimensions") != null)
            .other
        else
            declared.shape;
        try into.append(gpa, .{
            .name = name.text(source),
            .introducer = introducer,
            .type_name = declared.name,
            .shape = shape,
        });
    }
}

fn appendUncovered(
    gpa: std.mem.Allocator,
    into: *std.ArrayList(Binding),
    name: []const u8,
) !void {
    try into.append(gpa, .{
        .name = name,
        .introducer = .uncovered,
        .type_name = "",
        .shape = .other,
    });
}

fn lastIdentifier(node: ts.Node) ?ts.Node {
    var found: ?ts.Node = null;
    var children = node.namedChildren();
    while (children.next()) |child| {
        if (std.mem.eql(u8, child.kind(), "identifier")) found = child;
    }
    return found;
}

/// Every name the method binds whose scope reaches past the construct binding
/// it, with the declared type where Plan 012's covered list admits one.
///
/// It mirrors `collectMethodBindings` in `src/frontends/java.zig`: the same
/// constructs, in the same order. What it adds is the declared type, and the
/// record that every construct outside the covered list introduces a name whose
/// type this analysis does not read.
fn collectMethodBindings(
    gpa: std.mem.Allocator,
    into: *std.ArrayList(Binding),
    node: ts.Node,
    source: []const u8,
    depth: u32,
) !void {
    if (depth >= max_walk_depth) return;

    const kind = node.kind();
    if (std.mem.eql(u8, kind, "formal_parameter")) {
        if (node.childByFieldName("name")) |name| {
            const declared = typeOfDeclaration(node, source);
            const shape: TypeShape = if (node.childByFieldName("dimensions") != null)
                .other
            else
                declared.shape;
            try into.append(gpa, .{
                .name = name.text(source),
                .introducer = .parameter,
                .type_name = declared.name,
                .shape = shape,
            });
        }
    } else if (std.mem.eql(u8, kind, "catch_formal_parameter") or
        std.mem.eql(u8, kind, "enhanced_for_statement") or
        std.mem.eql(u8, kind, "resource") or
        std.mem.eql(u8, kind, "instanceof_expression"))
    {
        if (node.childByFieldName("name")) |name| try appendUncovered(gpa, into, name.text(source));
    } else if (std.mem.eql(u8, kind, "spread_parameter")) {
        var children = node.namedChildren();
        while (children.next()) |child| {
            if (!std.mem.eql(u8, child.kind(), "variable_declarator")) continue;
            const name = child.childByFieldName("name") orelse continue;
            try appendUncovered(gpa, into, name.text(source));
        }
    } else if (std.mem.eql(u8, kind, "type_pattern") or
        std.mem.eql(u8, kind, "record_pattern_component"))
    {
        if (lastIdentifier(node)) |name| try appendUncovered(gpa, into, name.text(source));
    } else if (std.mem.eql(u8, kind, "lambda_expression")) {
        if (node.childByFieldName("parameters")) |parameters| {
            if (std.mem.eql(u8, parameters.kind(), "identifier")) {
                try appendUncovered(gpa, into, parameters.text(source));
            }
        }
    } else if (std.mem.eql(u8, kind, "inferred_parameters")) {
        var names = node.namedChildren();
        while (names.next()) |child| {
            if (std.mem.eql(u8, child.kind(), "identifier")) {
                try appendUncovered(gpa, into, child.text(source));
            }
        }
    }

    var children = node.namedChildren();
    while (children.next()) |child| try collectMethodBindings(gpa, into, child, source, depth + 1);
}

fn isTypeBody(kind: []const u8) bool {
    const kinds = [_][]const u8{ "class_body", "interface_body", "enum_body", "annotation_type_body" };
    for (kinds) |candidate| {
        if (std.mem.eql(u8, kind, candidate)) return true;
    }
    return false;
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

// -- options ---------------------------------------------------------------

const Options = struct {
    root: []const u8 = "",
    top: usize = 20,
};

const usage =
    \\usage: semidx-java-coverage --root <dir> [--top <n>]
    \\
    \\Indexes <dir>, reads its Java source for the declared hierarchy, and prices
    \\the two families Plan 014 is about. See the header of src/java_coverage.zig
    \\for the procedure, which does not depend on this program.
    \\
;

fn parseOptions(arguments: anytype) !Options {
    var options: Options = .{};
    while (arguments.next()) |argument| {
        if (std.mem.eql(u8, argument, "--root")) {
            options.root = arguments.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, argument, "--top")) {
            const value = arguments.next() orelse return error.MissingValue;
            options.top = std.fmt.parseInt(usize, value, 10) catch return error.BadTop;
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

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var world = try buildWorld(gpa, arena, found);
    defer world.by_name.deinit(gpa);

    try reportBaseline(out, options, scanned, &snapshot, &world);
    try reportHierarchy(out, &world);

    var walker: Walker = .{
        .world = &world,
        .strict = false,
        .visited = .empty,
        .path = .empty,
        .gpa = gpa,
        .depth = 0,
        .uses_interface = false,
    };
    defer walker.visited.deinit(gpa);
    defer walker.path.deinit(gpa);

    const guard = try reportGuardFamily(out, gpa, &snapshot, &world, &walker, options.top);
    try reportValueReceivers(out, gpa, arena, &snapshot, &world, &walker, found);
    try reportGateA(out, guard);

    try out.flush();
}

// -- building the world ----------------------------------------------------

fn buildWorld(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    found: semidx.source.SourceScan,
) !World {
    var parser = try ts.Parser.init(java.grammar);
    defer parser.deinit();

    var units: std.ArrayList(UnitModel) = .empty;
    var decls: std.ArrayList(TypeDecl) = .empty;

    for (found.units) |unit| {
        if (unit.language != .java) continue;
        const unit_index: u32 = @intCast(units.items.len);

        var model_entry: UnitModel = .{
            .path = unit.path,
            .package = "",
            .source_root = null,
            .imports = &.{},
            .types = &.{},
        };

        var tree = parser.parse(unit.bytes, null) catch {
            try units.append(arena, model_entry);
            continue;
        };
        defer tree.deinit();
        const tree_root = tree.root();
        if (tree_root.hasError()) {
            // The frontend derives nothing from a unit that does not parse
            // cleanly, so neither does this model.
            try units.append(arena, model_entry);
            continue;
        }

        model_entry.package = (try java.declaredPackage(arena, tree_root, unit.bytes)) orelse "";
        model_entry.source_root = java.sourceRoot(unit.path, model_entry.package);
        model_entry.imports = try java.singleTypeImports(arena, tree_root, unit.bytes);

        var own: std.ArrayList(u32) = .empty;
        var top_level = tree_root.namedChildren();
        while (top_level.next()) |node| {
            const kind = TypeKind.fromNodeKind(node.kind()) orelse continue;
            const name_node = node.childByFieldName("name") orelse continue;

            var methods: std.ArrayList(MethodDecl) = .empty;
            var member_types: std.ArrayList([]const u8) = .empty;
            try collectMembers(arena, node, unit.bytes, kind, &methods, &member_types);

            try own.append(arena, @intCast(decls.items.len));
            try decls.append(arena, .{
                .unit = unit_index,
                .name = name_node.text(unit.bytes),
                .kind = kind,
                .supertypes = try collectSupertypes(arena, node, unit.bytes),
                .methods = try methods.toOwnedSlice(arena),
                .member_types = try member_types.toOwnedSlice(arena),
            });
        }
        model_entry.types = try own.toOwnedSlice(arena);
        try units.append(arena, model_entry);
    }

    const all_units = try units.toOwnedSlice(arena);
    const all_decls = try decls.toOwnedSlice(arena);

    var buckets: std.StringHashMapUnmanaged(std.ArrayList(u32)) = .empty;
    defer {
        var values = buckets.valueIterator();
        while (values.next()) |list| list.deinit(gpa);
        buckets.deinit(gpa);
    }
    for (all_decls, 0..) |decl, at| {
        const slot = try buckets.getOrPut(gpa, decl.name);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.append(gpa, @intCast(at));
    }

    var by_name: std.StringHashMapUnmanaged([]const u32) = .empty;
    var entries = buckets.iterator();
    while (entries.next()) |entry| {
        try by_name.put(gpa, entry.key_ptr.*, try arena.dupe(u32, entry.value_ptr.items));
    }

    return .{
        .gpa = gpa,
        .arena = arena,
        .units = all_units,
        .decls = all_decls,
        .by_name = by_name,
    };
}

// -- reports ---------------------------------------------------------------

fn reportBaseline(
    out: anytype,
    options: Options,
    scanned: semidx.Index.ScanOutcome,
    snapshot: *const semidx.Snapshot,
    world: *const World,
) !void {
    try out.print("root:        {s}\n", .{options.root});
    try out.print("units:       {d} indexed\n", .{scanned.added + scanned.unchanged + scanned.changed});
    try out.print("java units:  {d} in the source model\n", .{world.units.len});
    // How often a frontend was asked to read a unit, against how many units the
    // scan found. A unit read twice in one batch is the mechanism
    // [Follow-up 018](../docs/followups/018_unexplained_assertion_delta.md)
    // names, so the two numbers are recorded rather than left to be assumed.
    try out.print("analyzed:    {d} frontend reads, {d} of them invalidations\n", .{
        scanned.analyzed,
        scanned.invalidated,
    });
    try out.print("revision:    {d}\n\n", .{snapshot.revision});

    try out.print("definitions  {d}\n", .{snapshot.countEntities(.{ .kind = .definition })});
    try out.print("  java        {d}\n", .{snapshot.countEntities(.{ .kind = .definition, .language = .java })});
    try out.print("assertions   {d} recorded\n", .{snapshot.assertions.len});
    try out.print("  facts       {d}\n", .{snapshot.countAssertions(.{ .resolution = .fact })});
    try out.print("  unresolved  {d}\n", .{snapshot.countUnresolvedAssertions()});
    try out.print("  approximate {d}\n", .{snapshot.countApproximateAssertions()});
    try out.print("  stale       {d}\n", .{snapshot.countAssertions(.{ .freshness = .stale })});
    try out.print("diagnostics  {d}\n", .{snapshot.diagnostics.len});

    var by_kind = [_]usize{0} ** 4;
    for (snapshot.diagnostics) |diagnostic| by_kind[@intFromEnum(diagnostic.kind)] += 1;
    for (std.enums.values(model.DiagnosticKind)) |kind| {
        try out.print("  {s:<22} {d}\n", .{ @tagName(kind), by_kind[@intFromEnum(kind)] });
    }
    try out.print("\n", .{});
}

fn reportHierarchy(out: anytype, world: *const World) !void {
    var by_kind = [_]usize{0} ** 5;
    var with_supertypes: usize = 0;
    var supertype_links: usize = 0;
    var shapes = [_]usize{0} ** 4;
    var interface_links: usize = 0;

    for (world.decls) |decl| {
        by_kind[@intFromEnum(decl.kind)] += 1;
        if (decl.supertypes.len != 0) with_supertypes += 1;
        for (decl.supertypes) |supertype| {
            supertype_links += 1;
            shapes[@intFromEnum(supertype.shape)] += 1;
            if (supertype.interface_position) interface_links += 1;
        }
    }

    try out.print("Top-level Java type declarations in source\n", .{});
    for (std.enums.values(TypeKind)) |kind| {
        try out.print("  {s:<12} {d}\n", .{ kind.tag(), by_kind[@intFromEnum(kind)] });
    }
    try out.print("  {s:<12} {d}\n", .{ "with supers", with_supertypes });
    try out.print("\nDeclared supertype links: {d} ({d} in an interface position)\n", .{
        supertype_links,
        interface_links,
    });
    for (std.enums.values(TypeShape)) |shape| {
        try out.print("  {s:<12} {d}\n", .{ @tagName(shape), shapes[@intFromEnum(shape)] });
    }

    // How many of those links reach an indexed declaration at all, which is the
    // single-link version of the question the chain walk asks transitively.
    var reached = [_]usize{0} ** 4;
    var reached_interface: usize = 0;
    for (world.decls) |decl| {
        for (decl.supertypes) |supertype| {
            switch (resolveSimpleName(world, decl.unit, supertype.name)) {
                .decl => |at| {
                    reached[0] += 1;
                    if (world.decls[at].kind == .interface) reached_interface += 1;
                },
                .ambiguous => reached[1] += 1,
                .out_of_scope => reached[2] += 1,
                .none => reached[3] += 1,
            }
        }
    }
    try out.print("\nWhere one declared supertype link reaches\n", .{});
    try out.print("  {s:<24} {d} ({d} of them an interface)\n", .{ "an indexed declaration", reached[0], reached_interface });
    try out.print("  {s:<24} {d}\n", .{ "ambiguous", reached[1] });
    try out.print("  {s:<24} {d}\n", .{ "out of scope", reached[2] });
    try out.print("  {s:<24} {d}\n", .{ "nothing indexed", reached[3] });
    try out.print("\n", .{});
}

const GuardResult = struct {
    references: GuardTally = .{},
    receivers: GuardTally = .{},
    unqualified: GuardTally = .{},
};

fn tallyOf(result: *GuardResult, which: usize) *GuardTally {
    return switch (which) {
        0 => &result.references,
        1 => &result.receivers,
        else => &result.unqualified,
    };
}

fn reportGuardFamily(
    out: anytype,
    gpa: std.mem.Allocator,
    snapshot: *const semidx.Snapshot,
    world: *const World,
    walker: *Walker,
    top: usize,
) !GuardResult {
    var result: GuardResult = .{};

    // Fan-out inputs, over the two families the gate is measured on.
    var depth_histogram = [_]usize{0} ** (max_chain_depth + 2);
    var visited_histogram: std.AutoHashMapUnmanaged(u32, usize) = .empty;
    defer visited_histogram.deinit(gpa);
    // For each declaration a walk visited, the distinct reader units that
    // walked through it. This is the fan-out Plan 014 D7 would hint.
    var readers: std.AutoHashMapUnmanaged(u32, std.AutoHashMapUnmanaged(u32, void)) = .empty;
    defer {
        var values = readers.valueIterator();
        while (values.next()) |set| set.deinit(gpa);
        readers.deinit(gpa);
    }

    var path_to_unit: std.StringHashMapUnmanaged(u32) = .empty;
    defer path_to_unit.deinit(gpa);
    for (world.units, 0..) |unit, at| {
        try path_to_unit.put(gpa, unit.path, @intCast(at));
    }

    for (snapshot.assertions) |assertion| {
        if (snapshot.assertionFreshness(assertion) != .current) continue;
        const explanation = switch (assertion.resolution) {
            .unresolved => |unresolved| unresolved.explanation,
            else => continue,
        };
        const relationship = assertion.relationship() orelse continue;
        const which: usize = switch (relationship.kind) {
            .references => if (std.mem.indexOf(u8, explanation, guard_reference_words) != null) 0 else continue,
            .calls => if (std.mem.indexOf(u8, explanation, guard_receiver_words) != null)
                1
            else if (std.mem.indexOf(u8, explanation, guard_unqualified_words) != null)
                2
            else
                continue,
            else => continue,
        };
        const tally = tallyOf(&result, which);
        tally.total += 1;

        const source = snapshot.entityById(relationship.source) orelse {
            tally.no_enclosing_type += 1;
            continue;
        };
        const evidence = source.evidence orelse {
            tally.no_enclosing_type += 1;
            continue;
        };
        const view = snapshot.unit(evidence.unit) orelse {
            tally.no_enclosing_type += 1;
            continue;
        };
        const unit_index = path_to_unit.get(view.path) orelse {
            tally.no_enclosing_type += 1;
            continue;
        };
        const class_name = if (std.mem.eql(u8, source.identity.role, "class"))
            source.identity.name orelse {
                tally.no_enclosing_type += 1;
                continue;
            }
        else if (source.identity.container_path.len != 0)
            source.identity.container_path[0]
        else {
            tally.no_enclosing_type += 1;
            continue;
        };

        const start = findTopLevel(world, unit_index, class_name) orelse {
            tally.no_enclosing_type += 1;
            continue;
        };
        if (world.decls[start].supertypes.len == 0) {
            tally.no_supertypes += 1;
            continue;
        }

        walker.strict = false;
        const lenient = try walker.walk(start);
        if (lenient.closed()) {
            tally.lenient_closed += 1;
            if (lenient.uses_interface) tally.lenient_closed_with_interface += 1;
        } else {
            tally.lenient_reasons[@intFromEnum(lenient.reason)] += 1;
        }

        // Fan-out is measured over the walk that Gate A is measured on, for the
        // two families the gate counts.
        if (which != 2) {
            depth_histogram[@min(lenient.depth, max_chain_depth + 1)] += 1;
            const slot = try visited_histogram.getOrPut(gpa, lenient.visited);
            if (!slot.found_existing) slot.value_ptr.* = 0;
            slot.value_ptr.* += 1;
            for (walker.visited.items) |visited| {
                const reader_slot = try readers.getOrPut(gpa, visited);
                if (!reader_slot.found_existing) reader_slot.value_ptr.* = .empty;
                try reader_slot.value_ptr.put(gpa, unit_index, {});
            }
        }

        walker.strict = true;
        const strict = try walker.walk(start);
        if (strict.closed()) {
            tally.strict_closed += 1;
            if (strict.uses_interface) tally.strict_closed_with_interface += 1;
        } else {
            tally.strict_reasons[@intFromEnum(strict.reason)] += 1;
        }
    }

    try out.print("Guard-declined claims, whole graph\n\n", .{});
    try out.print("{s:<26} {s:>9} {s:>9} {s:>9}\n", .{ "", "reference", "receiver", "unqualif." });
    const rows = [_]struct { label: []const u8, values: [3]usize }{
        .{ .label = "total", .values = .{
            result.references.total,
            result.receivers.total,
            result.unqualified.total,
        } },
        .{ .label = "enclosing type not found", .values = .{
            result.references.no_enclosing_type,
            result.receivers.no_enclosing_type,
            result.unqualified.no_enclosing_type,
        } },
        .{ .label = "no supertypes in source", .values = .{
            result.references.no_supertypes,
            result.receivers.no_supertypes,
            result.unqualified.no_supertypes,
        } },
        .{ .label = "chain closed (lenient)", .values = .{
            result.references.lenient_closed,
            result.receivers.lenient_closed,
            result.unqualified.lenient_closed,
        } },
        .{ .label = "  of those, interfaces", .values = .{
            result.references.lenient_closed_with_interface,
            result.receivers.lenient_closed_with_interface,
            result.unqualified.lenient_closed_with_interface,
        } },
        .{ .label = "chain closed (strict)", .values = .{
            result.references.strict_closed,
            result.receivers.strict_closed,
            result.unqualified.strict_closed,
        } },
        .{ .label = "  of those, interfaces", .values = .{
            result.references.strict_closed_with_interface,
            result.receivers.strict_closed_with_interface,
            result.unqualified.strict_closed_with_interface,
        } },
    };
    for (rows) |row| {
        try out.print("{s:<26} {d:>9} {d:>9} {d:>9}\n", .{
            row.label,
            row.values[0],
            row.values[1],
            row.values[2],
        });
    }

    try out.print("\nWhy a chain stayed open (lenient / strict)\n", .{});
    try out.print("{s:<26} {s:>19} {s:>19} {s:>19}\n", .{ "", "reference", "receiver", "unqualif." });
    for (std.enums.values(ChainReason)) |reason| {
        if (reason == .closed) continue;
        const at = @intFromEnum(reason);
        try out.print("{s:<26} {d:>8} /{d:>9} {d:>8} /{d:>9} {d:>8} /{d:>9}\n", .{
            reason.tag(),
            result.references.lenient_reasons[at],
            result.references.strict_reasons[at],
            result.receivers.lenient_reasons[at],
            result.receivers.strict_reasons[at],
            result.unqualified.lenient_reasons[at],
            result.unqualified.strict_reasons[at],
        });
    }

    try out.print("\nFan-out inputs, over the reference and receiver families\n", .{});
    try out.print("  Chain depth reached\n", .{});
    for (depth_histogram, 0..) |count, depth| {
        if (count == 0) continue;
        if (depth > max_chain_depth) {
            try out.print("    {s:>10}  {d}\n", .{ "capped", count });
        } else {
            try out.print("    {d:>10}  {d}\n", .{ depth, count });
        }
    }

    try out.print("  Distinct types one walk visits\n", .{});
    var visited_keys: std.ArrayList(u32) = .empty;
    defer visited_keys.deinit(gpa);
    var visited_entries = visited_histogram.iterator();
    while (visited_entries.next()) |entry| try visited_keys.append(gpa, entry.key_ptr.*);
    std.mem.sort(u32, visited_keys.items, {}, lessU32);
    for (visited_keys.items) |key| {
        try out.print("    {d:>10}  {d}\n", .{ key, visited_histogram.get(key).? });
    }

    var fanout: std.ArrayList(Fanout) = .empty;
    defer fanout.deinit(gpa);
    var reader_entries = readers.iterator();
    while (reader_entries.next()) |entry| {
        try fanout.append(gpa, .{ .decl = entry.key_ptr.*, .readers = entry.value_ptr.count() });
    }
    std.mem.sort(Fanout, fanout.items, {}, largerFanout);
    const shown = fanout.items[0..@min(top, fanout.items.len)];
    try out.print("  Types a walk visited: {d}; the {d} with the most reader units\n", .{
        fanout.items.len,
        shown.len,
    });
    for (shown) |entry| {
        const decl = world.decls[entry.decl];
        try out.print("    {d:>10}  {s} {s} ({s})\n", .{
            entry.readers,
            decl.kind.tag(),
            decl.name,
            world.units[decl.unit].path,
        });
    }
    try out.print("\n", .{});

    return result;
}

const Fanout = struct { decl: u32, readers: usize };

fn largerFanout(_: void, a: Fanout, b: Fanout) bool {
    if (a.readers != b.readers) return a.readers > b.readers;
    return a.decl < b.decl;
}

fn lessU32(_: void, a: u32, b: u32) bool {
    return a < b;
}

fn findTopLevel(world: *const World, unit: u32, name: []const u8) ?u32 {
    for (world.units[unit].types) |index| {
        if (std.mem.eql(u8, world.decls[index].name, name)) return index;
    }
    return null;
}

fn reportGateA(out: anytype, guard: GuardResult) !void {
    const closable = guard.references.lenient_closed + guard.receivers.lenient_closed;
    const interfaced = guard.references.lenient_closed_with_interface +
        guard.receivers.lenient_closed_with_interface;
    const strict = guard.references.strict_closed + guard.receivers.strict_closed;

    try out.print("Gate A (Plan 014 D12)\n", .{});
    try out.print("  A1  interface-dependent closable claims: {d} of {d}\n", .{ interfaced, closable });
    try out.print("      verdict: {s}\n", .{if (interfaced * 2 >= closable and closable != 0) "PASS" else "FAIL"});
    try out.print("  A2  closed-hierarchy upper bound: {d} (floor 1000)\n", .{closable});
    try out.print("      verdict: {s}\n", .{if (closable >= 1000) "PASS" else "FAIL"});
    try out.print("  For reference, the strict bound today's `resolveType` shape rule would give: {d}\n", .{strict});
}

// -- the value-receiver family --------------------------------------------

fn reportValueReceivers(
    out: anytype,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    snapshot: *const semidx.Snapshot,
    world: *const World,
    walker: *Walker,
    found: semidx.source.SourceScan,
) !void {
    var path_to_unit: std.StringHashMapUnmanaged(u32) = .empty;
    defer path_to_unit.deinit(gpa);
    for (world.units, 0..) |unit, at| try path_to_unit.put(gpa, unit.path, @intCast(at));

    // Claims grouped by the unit they were read in, so each unit is parsed once.
    var pending = try gpa.alloc(std.ArrayList(PendingCall), world.units.len);
    defer {
        for (pending) |*list| list.deinit(gpa);
        gpa.free(pending);
    }
    for (pending) |*list| list.* = .empty;

    var total: usize = 0;
    var unplaced: usize = 0;
    for (snapshot.assertions) |assertion| {
        if (snapshot.assertionFreshness(assertion) != .current) continue;
        const explanation = switch (assertion.resolution) {
            .unresolved => |unresolved| unresolved.explanation,
            else => continue,
        };
        const relationship = assertion.relationship() orelse continue;
        if (relationship.kind != .calls) continue;
        if (std.mem.indexOf(u8, explanation, receiver_bound_words) == null) continue;
        total += 1;

        const designator = switch (relationship.target) {
            .designator => |name| name,
            .entity => {
                unplaced += 1;
                continue;
            },
        };
        const evidence = assertion.evidence orelse {
            unplaced += 1;
            continue;
        };
        const view = snapshot.unit(evidence.unit) orelse {
            unplaced += 1;
            continue;
        };
        const unit_index = path_to_unit.get(view.path) orelse {
            unplaced += 1;
            continue;
        };
        const receiver = receiverNameOf(explanation) orelse {
            unplaced += 1;
            continue;
        };
        try pending[unit_index].append(gpa, .{
            .start_byte = evidence.range.start_byte,
            .method = try arena.dupe(u8, designator.name),
            .receiver = try arena.dupe(u8, receiver),
        });
    }

    var today = [_]usize{0} ** stop_count;
    var relaxed = [_]usize{0} ** stop_count;

    var parser = try ts.Parser.init(java.grammar);
    defer parser.deinit();

    for (found.units) |unit| {
        if (unit.language != .java) continue;
        const unit_index = path_to_unit.get(unit.path) orelse continue;
        if (pending[unit_index].items.len == 0) continue;

        var tree = parser.parse(unit.bytes, null) catch continue;
        defer tree.deinit();
        const tree_root = tree.root();
        if (tree_root.hasError()) continue;

        var classifier: Classifier = .{
            .world = world,
            .walker = walker,
            .gpa = gpa,
            .unit = unit_index,
            .source = unit.bytes,
            .pending = pending[unit_index].items,
            .today = &today,
            .relaxed = &relaxed,
        };
        try classifier.run(tree_root);
    }

    for (pending) |list| {
        for (list.items) |call| {
            if (!call.located) {
                today[@intFromEnum(ReceiverStop.invocation_not_located)] += 1;
                relaxed[@intFromEnum(ReceiverStop.invocation_not_located)] += 1;
            }
        }
    }

    try out.print("Value-receiver calls: {d} claims, {d} with no location to classify\n\n", .{
        total,
        unplaced,
    });
    try out.print("{s:<30} {s:>10} {s:>10}\n", .{ "where the call stops", "today", "relaxed" });
    var today_sum: usize = 0;
    var relaxed_sum: usize = 0;
    for (std.enums.values(ReceiverStop)) |stop| {
        const at = @intFromEnum(stop);
        today_sum += today[at];
        relaxed_sum += relaxed[at];
        try out.print("{s:<30} {d:>10} {d:>10}\n", .{ stop.tag(), today[at], relaxed[at] });
    }
    try out.print("{s:<30} {d:>10} {d:>10}\n", .{ "sum", today_sum, relaxed_sum });
    if (today_sum + unplaced != total) {
        try out.print(
            "MISMATCH: {d} classified plus {d} unplaced is not {d} claims.\n",
            .{ today_sum, unplaced, total },
        );
    }

    const addressable = relaxed[@intFromEnum(ReceiverStop.addressable)];
    try out.print("\nGate C input (measured here on today's graph, not after Stage 3)\n", .{});
    try out.print("  value-receiver calls addressable under D10: {d} today, {d} with the guard relaxed (floor 1000)\n", .{
        today[@intFromEnum(ReceiverStop.addressable)],
        addressable,
    });
    try out.print("\n", .{});
}

const Classifier = struct {
    world: *const World,
    walker: *Walker,
    gpa: std.mem.Allocator,
    unit: u32,
    source: []const u8,
    pending: []PendingCall,
    today: *[stop_count]usize,
    relaxed: *[stop_count]usize,

    fn run(self: *Classifier, tree_root: ts.Node) !void {
        var top_level = tree_root.namedChildren();
        while (top_level.next()) |node| {
            if (!std.mem.eql(u8, node.kind(), "class_declaration")) continue;
            const name_node = node.childByFieldName("name") orelse continue;
            const class_index = findTopLevel(self.world, self.unit, name_node.text(self.source)) orelse continue;
            const body = node.childByFieldName("body") orelse continue;

            var fields: std.ArrayList(Binding) = .empty;
            defer fields.deinit(self.gpa);
            var members = body.namedChildren();
            while (members.next()) |member| {
                if (!std.mem.eql(u8, member.kind(), "field_declaration")) continue;
                try appendDeclarators(self.gpa, &fields, member, self.source, .field);
            }

            members = body.namedChildren();
            while (members.next()) |member| {
                if (!std.mem.eql(u8, member.kind(), "method_declaration")) continue;
                const method_body = member.childByFieldName("body") orelse continue;

                var bindings: std.ArrayList(Binding) = .empty;
                defer bindings.deinit(self.gpa);
                try bindings.appendSlice(self.gpa, fields.items);
                try collectMethodBindings(self.gpa, &bindings, member, self.source, 0);

                var locals: std.ArrayList(Binding) = .empty;
                defer locals.deinit(self.gpa);

                try self.walk(method_body, node, member, class_index, &bindings, &locals, false, 0);
            }
        }
    }

    fn walk(
        self: *Classifier,
        node: ts.Node,
        class_node: ts.Node,
        method_node: ts.Node,
        class_index: u32,
        bindings: *std.ArrayList(Binding),
        locals: *std.ArrayList(Binding),
        nested: bool,
        depth: u32,
    ) !void {
        if (depth >= max_walk_depth) return;
        if (std.mem.eql(u8, node.kind(), "method_invocation")) {
            try self.classify(node, class_node, method_node, class_index, bindings, locals, nested);
        }
        const inner = nested or isTypeBody(node.kind());
        const mark = locals.items.len;
        defer locals.shrinkRetainingCapacity(mark);

        var children = node.namedChildren();
        while (children.next()) |child| {
            try self.walk(child, class_node, method_node, class_index, bindings, locals, inner, depth + 1);
            if (std.mem.eql(u8, child.kind(), "local_variable_declaration")) {
                try appendDeclarators(self.gpa, locals, child, self.source, .local);
            }
        }
    }

    fn classify(
        self: *Classifier,
        node: ts.Node,
        class_node: ts.Node,
        method_node: ts.Node,
        class_index: u32,
        bindings: *std.ArrayList(Binding),
        locals: *std.ArrayList(Binding),
        nested: bool,
    ) !void {
        const start = node.startByte();
        var call: ?*PendingCall = null;
        for (self.pending) |*candidate| {
            if (candidate.located) continue;
            if (candidate.start_byte != start) continue;
            call = candidate;
            break;
        }
        const pending = call orelse return;
        pending.located = true;

        const stops = self.decide(pending.*, class_node, method_node, class_index, bindings, locals, nested);
        self.today[@intFromEnum(stops[0])] += 1;
        self.relaxed[@intFromEnum(stops[1])] += 1;
    }

    /// The conditions Plan 014 D10 lists, asked in order, twice: as the guard
    /// stands and as it would stand relaxed. The only difference between the
    /// two is whether the enclosing class's declared supertypes stop the
    /// receiver type from resolving.
    fn decide(
        self: *Classifier,
        call: PendingCall,
        class_node: ts.Node,
        method_node: ts.Node,
        class_index: u32,
        bindings: *std.ArrayList(Binding),
        locals: *std.ArrayList(Binding),
        nested: bool,
    ) [2]ReceiverStop {
        if (nested) return .{ .nested_class_body, .nested_class_body };

        var binding: ?Binding = null;
        var at = locals.items.len;
        while (at > 0) {
            at -= 1;
            if (std.mem.eql(u8, locals.items[at].name, call.receiver)) {
                binding = locals.items[at];
                break;
            }
        }
        if (binding == null) {
            at = bindings.items.len;
            while (at > 0) {
                at -= 1;
                if (std.mem.eql(u8, bindings.items[at].name, call.receiver)) {
                    binding = bindings.items[at];
                    break;
                }
            }
        }
        const bound = binding orelse return .{ .binding_not_found, .binding_not_found };
        if (bound.introducer == .uncovered) return .{ .uncovered_introducer, .uncovered_introducer };
        if (bound.shape != .simple) return .{ .uncovered_type_shape, .uncovered_type_shape };
        // This grammar has no node for `var`: it writes the keyword as a
        // `type_identifier`, so it reaches here looking like a simple type
        // name. It is an inferred type, which Plan 014 D9 leaves uncovered.
        if (std.mem.eql(u8, bound.type_name, "var")) {
            return .{ .uncovered_type_shape, .uncovered_type_shape };
        }

        const name = bound.type_name;
        if (declaresTypeParameter(method_node, self.source, name) or
            declaresTypeParameter(class_node, self.source, name))
        {
            return .{ .type_parameter, .type_parameter };
        }
        for (self.world.decls[class_index].member_types) |member| {
            if (std.mem.eql(u8, member, name)) return .{ .member_type_of_enclosing, .member_type_of_enclosing };
        }

        const target = switch (resolveSimpleName(self.world, self.unit, name)) {
            .none => return .{ .receiver_type_none, .receiver_type_none },
            .ambiguous => return .{ .receiver_type_ambiguous, .receiver_type_ambiguous },
            .out_of_scope => return .{ .receiver_type_out_of_scope, .receiver_type_out_of_scope },
            .decl => |index| index,
        };

        // The one condition the two modes disagree about. It applies only when
        // the receiver type is not declared in this unit: a name the unit
        // declares itself never reaches the guard.
        const guarded = self.world.decls[target].unit != self.unit and
            self.world.decls[class_index].supertypes.len != 0;

        const outcome = self.targetStop(call, target, class_index);
        return .{ if (guarded) .enclosing_supertypes_guard else outcome, outcome };
    }

    fn targetStop(self: *Classifier, call: PendingCall, target: u32, class_index: u32) ReceiverStop {
        const decl = self.world.decls[target];
        if (!decl.kind.inChain()) return .target_not_a_chain_type;

        if (decl.supertypes.len != 0) {
            self.walker.strict = false;
            const chain = self.walker.walk(target) catch return .target_chain_open;
            if (!chain.closed()) return .target_chain_open;
            // The chain rules out; it never selects. A method of the invoked
            // name anywhere in it leaves the call unresolved (Plan 014 D6).
            for (self.walker.visited.items) |visited| {
                if (visited == target) continue;
                for (self.world.decls[visited].methods) |method| {
                    if (std.mem.eql(u8, method.name, call.method)) return .target_name_in_chain;
                }
            }
        }

        var found: ?MethodDecl = null;
        var count: u32 = 0;
        for (decl.methods) |method| {
            if (!std.mem.eql(u8, method.name, call.method)) continue;
            if (count == 0) found = method;
            count += 1;
        }
        if (count == 0) return .target_no_method;
        if (count > 1) return .target_overloaded;

        const only = found.?;
        if (only.access != .public and target != class_index) return .target_inaccessible;
        // Every other condition holds; the target being an interface is the
        // one thing standing between this call and a fact, and it is exactly
        // what Stage 1 removes. It is its own row rather than folded into
        // `addressable`, because today an interface is not a definition.
        if (decl.kind == .interface) return .target_is_interface;
        return .addressable;
    }
};
