//! Fixture-scoped Java frontend.
//!
//! It reads Java parse nodes and contributes shared-core assertions. Java's own
//! vocabulary stays in extension payloads: the shared core learns that a
//! definition exists and what it refers to, never what a `method_declaration`
//! is. Constructs outside the declared coverage are reported as unsupported
//! rather than silently omitted.

const std = @import("std");
const builtin = @import("builtin");

const core = @import("semidx_core");
const ts = @import("semidx_tree_sitter");

const model = core.model;
const contract = core.contract;

pub const grammar: ts.Grammar = .java;

pub const version = std.fmt.comptimePrint("slice-001+ts-abi{d}", .{ts.runtime_abi_version});

pub const capabilities: contract.Capabilities = .{
    .language = .java,
    .producer = .{ .name = "frontend.java", .version = version },
    .entity_roles = &.{ "class", "interface", "method" },
    .relationship_kinds = &.{ .defines, .references, .calls },
    .coverage_note = "top-level classes and interfaces, their methods, method " ++
        "return types, class field types, declared supertypes, and invocations " ++
        "inside method bodies. A simple type name not declared in the unit " ++
        "resolves to the one current top-level class or interface in the same " ++
        "visibility scope, unless a type parameter, member type, supertype " ++
        "chain, import, or uncovered type declaration could give the name " ++
        "another meaning; declared supertypes are recorded as references under " ++
        "that same rule. An unqualified invocation resolves to the enclosing " ++
        "type's one method of that name when the call is not inside a nested " ++
        "class body and any declared supertype chain is closed in indexed " ++
        "source and declares no method of that name. An invocation qualified " ++
        "by a simple name resolves as a class-qualified static call when no " ++
        "binding, on-demand static import, or inherited field can claim the " ++
        "receiver name, the name resolves to one current top-level class or " ++
        "interface, the target declares exactly one accessible static method, " ++
        "and any required enclosing or target chain is closed. A call through " ++
        "`this` or a covered value receiver resolves when the receiver's " ++
        "declared simple type resolves, the target declares exactly one " ++
        "accessible method, and a closed target chain declares no method of " ++
        "that name; `super`, inherited targets, dispatch, overload selection, " ++
        "non-simple, generic, array, and inferred receiver types stay outside " ++
        "coverage. An interface method with no access modifier is recorded as " ++
        "`public`, as Java defines it; interface constants, and enum, record, " ++
        "and annotation type declarations, stay outside this coverage",
};

/// Guards against unbounded recursion on pathological input. Exceeding it is
/// reported as an unsupported construct, never as an absence of invocations.
const max_depth: u32 = 64;

/// What a unit analyzing a call must know about a class it does not read.
///
/// A unit is analyzed from its own source and the graph; another unit's bytes
/// and parse tree are not available to it, and re-reading them per lookup would
/// make every answer a parse. So the Java frontend records the shape of what it
/// declares as extension labels on the definitions themselves, and a later
/// analysis reads them back as graph facts
/// ([ADR 009](../../docs/adr/009_java_static_calls.md)).
///
/// They are labels rather than a shared-core kind because every one of them is
/// a Java rule: what `static` selects, what `protected` reaches, and what a
/// declared supertype may hide are Java's questions and no other language's.
pub const class_shape = struct {
    pub const key = "java.supertypes";
    /// The type declares no superclass and no interface.
    pub const none = "none";
    /// It declares at least one, so a member it inherits could be the target
    /// and the working copy cannot see that it is not.
    pub const declared = "declared";
};

/// The member types a top-level type declares, as one label.
///
/// A member type is not a definition this frontend records, so a later analysis
/// asking "could an inherited member type of this name shadow it" has nothing to
/// look up. The declaring analysis already knows, so it writes the names down
/// where the graph can carry them. A Java identifier cannot contain a comma, so
/// the separator cannot occur inside a name.
pub const member_types = NameList("java.member_types");

/// The names a top-level type's field declarations bind, as one label.
///
/// A field is not a definition this frontend records either, and a receiver
/// name a field claims is read as a value rather than as a type (JLS 6.4.2).
/// Asking whether a type further up a chain binds a name needs the names
/// written down where the graph can carry them.
pub const field_names = NameList("java.field_names");

/// The simple names a top-level type writes in its `extends` and `implements`
/// clauses, as one label.
///
/// `java.supertypes` says *whether* a type declares any; this says which. A
/// reader that walked a chain has to be reanalyzed when a type in it starts
/// declaring a different supertype, and a boolean cannot report that.
pub const supertype_names = NameList("java.supertype_names");

/// One label holding several Java names. A Java identifier cannot contain a
/// comma, so the separator cannot occur inside a name.
fn NameList(comptime label_key: []const u8) type {
    return struct {
        pub const key = label_key;
        pub const separator = ',';

        pub fn contains(value: []const u8, name: []const u8) bool {
            if (name.len == 0) return false;
            var names = std.mem.splitScalar(u8, value, separator);
            while (names.next()) |candidate| {
                if (std.mem.eql(u8, candidate, name)) return true;
            }
            return false;
        }

        pub fn appendTo(gpa: std.mem.Allocator, out: *std.ArrayList([]const u8), value: []const u8) !void {
            if (value.len == 0) return;
            var names = std.mem.splitScalar(u8, value, separator);
            while (names.next()) |candidate| {
                if (candidate.len == 0) continue;
                try out.append(gpa, candidate);
            }
        }
    };
}

pub const method_access = struct {
    pub const key = "java.access";
    pub const public = "public";
    pub const protected = "protected";
    pub const package_private = "package_private";
    pub const private = "private";
};

pub const method_static = struct {
    pub const key = "java.static";
    pub const yes = "true";
    pub const no = "false";
};

/// The declared access of a method, as its own analysis recorded it.
///
/// `unknown` is a real answer, not a default: a definition without the label was
/// recorded by something other than the current Java frontend, and a static call
/// must decline rather than assume the permissive case.
pub const Access = enum {
    public,
    protected,
    package_private,
    private,
    unknown,

    pub fn fromLabel(value: []const u8) Access {
        if (std.mem.eql(u8, value, method_access.public)) return .public;
        if (std.mem.eql(u8, value, method_access.protected)) return .protected;
        if (std.mem.eql(u8, value, method_access.package_private)) return .package_private;
        if (std.mem.eql(u8, value, method_access.private)) return .private;
        return .unknown;
    }

    pub fn label(self: Access) []const u8 {
        return switch (self) {
            .public => method_access.public,
            .protected => method_access.protected,
            .package_private => method_access.package_private,
            .private => method_access.private,
            .unknown => "unrecorded",
        };
    }
};

/// Whether a method declares `static`, as its own analysis recorded it.
///
/// `unknown` is the same kind of answer as `Access.unknown`. A definition
/// without the label was recorded by something other than the current Java
/// frontend, and a call must decline saying the modifier is unrecorded rather
/// than saying the method is an instance method, which is a claim about the
/// source the graph does not hold.
pub const Static = enum {
    yes,
    no,
    unknown,

    pub fn fromLabel(value: []const u8) Static {
        if (std.mem.eql(u8, value, method_static.yes)) return .yes;
        if (std.mem.eql(u8, value, method_static.no)) return .no;
        return .unknown;
    }
};

/// Whether a class declares a superclass or an interface. `unknown` is the same
/// kind of answer as `Access.unknown`, and declines the same way.
pub const Supertypes = enum {
    none,
    declared,
    unknown,

    pub fn fromLabel(value: []const u8) Supertypes {
        if (std.mem.eql(u8, value, class_shape.none)) return .none;
        if (std.mem.eql(u8, value, class_shape.declared)) return .declared;
        return .unknown;
    }
};

/// Whether a role names a Java type declaration this frontend records.
///
/// The roles are this frontend's vocabulary, so the answer lives with them
/// rather than being spelled out again in each projection that asks. A
/// projection that compared against `"class"` alone would silently stop seeing
/// interfaces the moment they became definitions, which is the failure this
/// exists to make impossible.
pub fn isTypeRole(role: []const u8) bool {
    return std.mem.eql(u8, role, "class") or std.mem.eql(u8, role, "interface");
}

const Modifiers = struct {
    access: []const u8,
    is_static: bool,
};

/// The declared modifiers of a member, as written, with the defaults Java
/// applies to what is not written.
///
/// A class member with no access keyword is package-private. A member declared
/// in an interface body with no access keyword is `public`, which is the same
/// kind of decision: Java states it, so recording the absent modifier literally
/// would say something about the source that is false, and would make every
/// interface method look inaccessible to
/// [ADR 009](../../docs/adr/009_java_static_calls.md)'s access check.
///
/// `default` and `abstract` are neither an access keyword nor `static`, so
/// neither changes an answer here.
fn modifiersOf(node: ts.Node, in_interface: bool) Modifiers {
    var found: Modifiers = .{
        .access = if (in_interface) method_access.public else method_access.package_private,
        .is_static = false,
    };
    var index: u32 = 0;
    while (index < node.childCount()) : (index += 1) {
        const child = node.childAt(index) orelse continue;
        if (!std.mem.eql(u8, child.kind(), "modifiers")) continue;
        var keyword: u32 = 0;
        while (keyword < child.childCount()) : (keyword += 1) {
            const token = child.childAt(keyword) orelse continue;
            const text = token.kind();
            if (std.mem.eql(u8, text, "public")) {
                found.access = method_access.public;
            } else if (std.mem.eql(u8, text, "protected")) {
                found.access = method_access.protected;
            } else if (std.mem.eql(u8, text, "private")) {
                found.access = method_access.private;
            } else if (std.mem.eql(u8, text, "static")) {
                found.is_static = true;
            }
        }
        break;
    }
    return found;
}

/// Test-only counters for the work deciding one invocation's target costs.
///
/// The same reason `core.graph.work` exists: what an answer costs is a property
/// this project asserts rather than hopes for. A call resolved by scanning every
/// method in the repository is the same answer as one resolved from a bounded
/// candidate table, and only a counter tells them apart — deterministically,
/// where a wall clock would make the lane unreliable and prove less.
///
/// It counts candidates examined, not invocations answered, because the term at
/// risk is the one inside the decision.
///
/// Outside a test build every call here compiles away.
pub const work = struct {
    /// Method candidates examined while deciding invocation targets.
    pub var method_candidates: usize = 0;

    pub fn reset() void {
        method_candidates = 0;
    }

    inline fn candidate() void {
        if (!builtin.is_test) return;
        method_candidates += 1;
    }
};

/// What a simple type name can mean among the other source units of one
/// explicit Java package, as read from current graph facts.
pub const Binding = union(enum) {
    /// Exactly one current top-level class of this name, in another unit the
    /// analyzed unit can see.
    unique: contract.ExternalTarget,
    /// More than one visible, counted. The name does not identify a class, and
    /// no candidate is preferred.
    ambiguous: u32,
    /// None visible, but the package declares the name elsewhere, counted. The
    /// reference is unresolved for a different reason than a name nothing
    /// declares, and a consumer must be able to tell the two apart.
    out_of_scope: u32,
};

pub const TypeBinding = struct {
    name: []const u8,
    binding: Binding,
};

/// One method a class outside the analyzed unit currently declares, with the
/// modifiers ADR 009 makes a static call check before it can name one.
pub const MethodCandidate = struct {
    name: []const u8,
    target: contract.ExternalTarget,
    access: Access,
    static: Static,
};

/// What a class outside the analyzed unit currently is, for a receiver naming
/// it.
///
/// `methods` holds only the names this unit writes after a `.` on that class,
/// including every overload of them: the analyzer knows which pairs the unit
/// asks about, so the candidate table is the size of the question rather than
/// the size of the provider.
pub const ClassMembers = struct {
    /// The simple name the analyzed unit writes.
    name: []const u8,
    supertypes: Supertypes,
    methods: []const MethodCandidate,
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
    /// What each simple name the unit's single-type imports bring in currently
    /// means, read under the same visibility rule as `types`.
    imports: []const TypeBinding = &.{},
    /// What the classes this unit's receivers name currently declare, for the
    /// `Name.method(...)` pairs it writes. A name with no entry either resolves
    /// to a class the unit declares itself, or to no class at all.
    members: []const ClassMembers = &.{},
    /// What each name this unit writes as a supertype reaches. A name with no
    /// entry either names a type the unit declares itself — whose chain the
    /// frontend walks from its own source — or no type at all.
    hierarchies: []const Hierarchy = &.{},

    pub const empty: Context = .{ .package = "", .types = &.{}, .imports = &.{} };

    /// A binding is only an answer for the package it was read for.
    pub fn lookup(self: Context, package: []const u8, name: []const u8) ?Binding {
        if (package.len == 0 or !std.mem.eql(u8, self.package, package)) return null;
        for (self.types) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.binding;
        }
        return null;
    }

    /// What a single-type import of `name` currently names, or null when the
    /// unit imports no such name or nothing indexed declares it.
    pub fn importLookup(self: Context, name: []const u8) ?Binding {
        for (self.imports) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.binding;
        }
        return null;
    }

    /// What the class `name` reaches currently declares, when the analyzer read
    /// it for this unit.
    pub fn memberLookup(self: Context, name: []const u8) ?ClassMembers {
        for (self.members) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry;
        }
        return null;
    }

    /// What the supertype `name` reaches, when the analyzer read it.
    pub fn hierarchyLookup(self: Context, name: []const u8) ?Hierarchy {
        for (self.hierarchies) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry;
        }
        return null;
    }
};

/// One `Name.method(...)` a source unit writes, as written.
pub const Receiver = struct {
    class: []const u8,
    method: []const u8,
};

/// What one type this unit names as a supertype reaches, as the analyzer read
/// it from the graph.
///
/// It is a projection and carries no authority: it says what a walk over
/// recorded claims found, and the frontend decides what that means. The three
/// name lists are what a chain is walked to **rule out** — never to select, so
/// no entity of the closure appears here
/// ([ADR 011](../../docs/adr/011_java_hierarchy_from_indexed_source.md), D6).
pub const Hierarchy = struct {
    /// The simple name the unit writes in an `extends` or `implements` clause.
    name: []const u8,
    /// Null when everything reachable from it is a current fact naming a
    /// current top-level Java class or interface; otherwise the condition that
    /// stopped the walk, in this frontend's own words.
    open: ?[]const u8,
    /// Every member type name declared anywhere in the closure.
    member_types: []const []const u8 = &.{},
    /// Every field name bound anywhere in the closure.
    fields: []const []const u8 = &.{},
    /// Every method name declared anywhere in the closure.
    methods: []const []const u8 = &.{},
    /// The same, excluding the type the closure starts at.
    ///
    /// The two questions are different. A guard asking what a *supertype* of
    /// the enclosing type may contribute counts that supertype's own members.
    /// A call asking what a *target* type may inherit must not: the target's
    /// own methods are what the call selects from, and counting them would
    /// make every resolvable call decline.
    inherited_methods: []const []const u8 = &.{},
    /// The names of the types the closure spans, so a reader can be hinted for
    /// every one of them and not only for the one it wrote.
    types: []const []const u8 = &.{},
    /// Every unit the closure spans, so a reader that relies on it can declare
    /// a dependency on all of them.
    providers: []const model.SourceUnitId = &.{},

    pub fn declares(self: Hierarchy, what: Member, name: []const u8) bool {
        return containsName(switch (what) {
            .member_type => self.member_types,
            .field => self.fields,
            .method => self.methods,
        }, name);
    }

    /// Whether anything *above* the type the closure starts at declares a
    /// method of this name.
    pub fn inherits(self: Hierarchy, name: []const u8) bool {
        return containsName(self.inherited_methods, name);
    }
};

/// What a chain is walked to rule out. Each guard asks about exactly one.
pub const Member = enum { member_type, field, method };

/// One name bound where an invocation is written, and what its declaration
/// says its type is.
///
/// The covered introducers are Plan 012's list unchanged — a field, a formal
/// parameter, a local variable declarator — and every other construct that
/// binds a name records itself here as uncovered, so the name is poisoned for
/// its lexical region rather than silently read as something it is not
/// ([ADR 012](../../docs/adr/012_java_value_receiver_calls.md), D9).
const BoundName = struct {
    name: []const u8,
    /// The simple type name the declaration writes. Empty unless `why` is
    /// `covered`.
    type_name: []const u8 = "",
    /// The node that name was read from, so resolving it asks about the type
    /// the source wrote rather than about the declaration around it.
    type_node: ?ts.Node = null,
    why: enum {
        covered,
        /// A construct outside the covered list bound the name.
        uncovered_introducer,
        /// A covered introducer bound it, and wrote a type this frontend does
        /// not read: generic, array, wildcard, or inferred.
        uncovered_type,
    } = .covered,
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

/// One `import a.b.C;`: a type named by its package and its simple name.
pub const SingleTypeImport = struct {
    package: []const u8,
    name: []const u8,
};

/// The single-type imports a Java source unit declares.
///
/// A static import names a member, an on-demand import names a scope, and an
/// unqualified import places nothing, so none of them appears here. Each name is
/// rebuilt from its identifiers, so layout inside it cannot change it.
pub fn singleTypeImports(
    allocator: std.mem.Allocator,
    root: ts.Node,
    source: []const u8,
) ![]const SingleTypeImport {
    var found: std.ArrayList(SingleTypeImport) = .empty;
    errdefer found.deinit(allocator);

    var top_level = root.namedChildren();
    while (top_level.next()) |node| {
        if (!std.mem.eql(u8, node.kind(), "import_declaration")) continue;
        if (importsStatically(node)) continue;

        var named = node.namedChildren();
        var qualified: ?ts.Node = null;
        var on_demand = false;
        while (named.next()) |child| {
            const kind = child.kind();
            if (std.mem.eql(u8, kind, "asterisk")) on_demand = true;
            if (isName(kind)) qualified = child;
        }
        if (on_demand) continue;
        const name_node = qualified orelse continue;
        // `import C;` names no package, so there is nowhere to look for it.
        if (!std.mem.eql(u8, name_node.kind(), "scoped_identifier")) continue;

        const scope = name_node.childByFieldName("scope") orelse continue;
        const simple = name_node.childByFieldName("name") orelse continue;
        var package: std.ArrayList(u8) = .empty;
        errdefer package.deinit(allocator);
        if (!try appendName(allocator, &package, scope, source, 0)) {
            package.deinit(allocator);
            continue;
        }
        try found.append(allocator, .{
            .package = try package.toOwnedSlice(allocator),
            .name = simple.text(source),
        });
    }
    return found.toOwnedSlice(allocator);
}

/// Every distinct `Name.method(...)` the unit writes, as written.
///
/// A lexical pre-pass and not a decision: whether `Name` is a class at all is
/// decided during analysis, by the obscuring rule. The analyzer reads it to
/// remember that this unit asked about those pairs, and to offer the candidates
/// an answer needs — so the set it returns is deliberately a superset of the
/// receivers that turn out to be classes.
pub fn staticCallReceivers(
    allocator: std.mem.Allocator,
    root: ts.Node,
    source: []const u8,
) ![]const Receiver {
    var found: std.ArrayList(Receiver) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    try collectReceivers(allocator, root, source, &found, &seen, 0);
    return found.items;
}

fn collectReceivers(
    allocator: std.mem.Allocator,
    node: ts.Node,
    source: []const u8,
    found: *std.ArrayList(Receiver),
    seen: *std.StringHashMapUnmanaged(void),
    depth: u32,
) !void {
    if (depth >= max_depth) return;
    if (std.mem.eql(u8, node.kind(), "method_invocation")) {
        if (node.childByFieldName("object")) |object| {
            if (std.mem.eql(u8, object.kind(), "identifier")) {
                if (node.childByFieldName("name")) |name| {
                    const receiver: Receiver = .{
                        .class = object.text(source),
                        .method = name.text(source),
                    };
                    const key = try std.fmt.allocPrint(
                        allocator,
                        "{s}.{s}",
                        .{ receiver.class, receiver.method },
                    );
                    const slot = try seen.getOrPut(allocator, key);
                    if (!slot.found_existing) try found.append(allocator, receiver);
                }
            }
        }
    }
    var children = node.namedChildren();
    while (children.next()) |child| {
        try collectReceivers(allocator, child, source, found, seen, depth + 1);
    }
}

/// Every `<declared type>.<method>` pair this unit writes through a receiver
/// that is a value of a covered binding.
///
/// A lexical pre-pass and not a decision, exactly as `staticCallReceivers` is,
/// and deliberately a superset: it collects every covered declaration in a
/// method's subtree without deciding which of them is in scope where. The
/// analyzer reads it to offer the candidates an answer needs and to remember
/// that this unit asked; the frontend decides what is actually bound.
pub fn valueReceiverPairs(
    allocator: std.mem.Allocator,
    root: ts.Node,
    source: []const u8,
) ![]const Receiver {
    var found: std.ArrayList(Receiver) = .empty;
    var declared: std.ArrayList(BoundName) = .empty;
    defer declared.deinit(allocator);

    var top_level = root.namedChildren();
    while (top_level.next()) |node| {
        if (!isCoveredTypeDeclaration(node.kind())) continue;
        const body = node.childByFieldName("body") orelse continue;

        declared.clearRetainingCapacity();
        try collectCoveredDeclarations(allocator, &declared, body, source, 0);
        if (declared.items.len == 0) continue;
        try collectValuePairs(allocator, &found, declared.items, body, source, 0);
    }
    return found.items;
}

/// Every covered declaration in a subtree, whatever its scope. A field, a
/// formal parameter, and a local variable declarator write one the same way.
fn collectCoveredDeclarations(
    gpa: std.mem.Allocator,
    into: *std.ArrayList(BoundName),
    node: ts.Node,
    source: []const u8,
    depth: u32,
) !void {
    if (depth >= max_depth) return;
    const kind = node.kind();
    if (std.mem.eql(u8, kind, "field_declaration") or
        std.mem.eql(u8, kind, "constant_declaration") or
        std.mem.eql(u8, kind, "local_variable_declaration"))
    {
        try appendDeclaredBindings(gpa, into, node, source);
    } else if (std.mem.eql(u8, kind, "formal_parameter")) {
        if (node.childByFieldName("name")) |name| {
            if (node.childByFieldName("dimensions") == null) {
                if (simpleTypeNameOf(node, source)) |type_node| {
                    try into.append(gpa, .{
                        .name = name.text(source),
                        .type_name = type_node.text(source),
                        .type_node = type_node,
                    });
                }
            }
        }
    }
    var children = node.namedChildren();
    while (children.next()) |child| try collectCoveredDeclarations(gpa, into, child, source, depth + 1);
}

fn collectValuePairs(
    gpa: std.mem.Allocator,
    into: *std.ArrayList(Receiver),
    declared: []const BoundName,
    node: ts.Node,
    source: []const u8,
    depth: u32,
) !void {
    if (depth >= max_depth) return;
    if (std.mem.eql(u8, node.kind(), "method_invocation")) {
        if (node.childByFieldName("object")) |object| {
            if (std.mem.eql(u8, object.kind(), "identifier")) {
                if (node.childByFieldName("name")) |name| {
                    const receiver = object.text(source);
                    const invoked = name.text(source);
                    // Every covered declaration of the name, not the first:
                    // two methods may both declare `value` with two types, and
                    // this pre-pass does not decide which one is in scope here.
                    for (declared) |bound| {
                        if (bound.why != .covered) continue;
                        if (!std.mem.eql(u8, bound.name, receiver)) continue;
                        if (alreadyPaired(into.items, bound.type_name, invoked)) continue;
                        try into.append(gpa, .{ .class = bound.type_name, .method = invoked });
                    }
                }
            }
        }
    }
    var children = node.namedChildren();
    while (children.next()) |child| try collectValuePairs(gpa, into, declared, child, source, depth + 1);
}

fn alreadyPaired(pairs: []const Receiver, class: []const u8, method: []const u8) bool {
    for (pairs) |pair| {
        if (std.mem.eql(u8, pair.class, class) and std.mem.eql(u8, pair.method, method)) return true;
    }
    return false;
}

/// Every type node a top-level declaration writes in a supertype position.
///
/// A class writes them in the `superclass` and `interfaces` fields; an
/// interface writes them in an `extends_interfaces` child, which carries no
/// field name. `superclass` holds its type directly, the other two hold a
/// `type_list` of them.
pub fn collectSupertypeNodes(
    gpa: std.mem.Allocator,
    declaration: ts.Node,
    out: *std.ArrayList(ts.Node),
) !void {
    if (declaration.childByFieldName("superclass")) |superclass| {
        try appendSupertypeNodes(gpa, superclass, out);
    }
    if (declaration.childByFieldName("interfaces")) |interfaces| {
        try appendSupertypeNodes(gpa, interfaces, out);
    }
    var children = declaration.namedChildren();
    while (children.next()) |child| {
        if (!std.mem.eql(u8, child.kind(), "extends_interfaces")) continue;
        try appendSupertypeNodes(gpa, child, out);
    }
}

fn appendSupertypeNodes(
    gpa: std.mem.Allocator,
    holder: ts.Node,
    out: *std.ArrayList(ts.Node),
) !void {
    var children = holder.namedChildren();
    while (children.next()) |child| {
        const kind = child.kind();
        if (std.mem.eql(u8, kind, "annotation") or std.mem.eql(u8, kind, "marker_annotation")) continue;
        if (std.mem.eql(u8, kind, "type_list")) {
            var types = child.namedChildren();
            while (types.next()) |entry| try out.append(gpa, entry);
            continue;
        }
        try out.append(gpa, child);
    }
}

/// Every distinct simple name this unit writes in a supertype position.
///
/// A lexical pre-pass and not a decision, exactly as `staticCallReceivers` is:
/// whether the name reaches a type at all is decided during analysis. The
/// analyzer reads it to remember that this unit asked about those types, and to
/// offer what each of them reaches. A name written generically or qualified is
/// left out, because `resolveType` declines it and an open chain needs no
/// closure.
pub fn supertypeNames(
    allocator: std.mem.Allocator,
    root: ts.Node,
    source: []const u8,
) ![]const []const u8 {
    var nodes: std.ArrayList(ts.Node) = .empty;
    defer nodes.deinit(allocator);
    var found: std.ArrayList([]const u8) = .empty;

    var top_level = root.namedChildren();
    while (top_level.next()) |node| {
        if (!isCoveredTypeDeclaration(node.kind())) continue;
        nodes.clearRetainingCapacity();
        try collectSupertypeNodes(allocator, node, &nodes);
        for (nodes.items) |supertype| {
            if (!std.mem.eql(u8, supertype.kind(), "type_identifier")) continue;
            const name = supertype.text(source);
            if (containsName(found.items, name)) continue;
            try found.append(allocator, name);
        }
    }
    return found.items;
}

/// Whether an import declaration carries the `static` keyword, which is an
/// anonymous token and so is invisible to a named-child walk.
fn importsStatically(node: ts.Node) bool {
    var index: u32 = 0;
    while (index < node.childCount()) : (index += 1) {
        const child = node.childAt(index) orelse continue;
        if (std.mem.eql(u8, child.kind(), "static")) return true;
    }
    return false;
}

/// Whether an import declaration ends in `.*`, which names a scope rather than
/// a member and so brings in no name this frontend can enumerate.
fn importsOnDemand(node: ts.Node) bool {
    var children = node.namedChildren();
    while (children.next()) |child| {
        if (std.mem.eql(u8, child.kind(), "asterisk")) return true;
    }
    return false;
}

/// The Java source root a unit sits in, or null when it has none.
///
/// It is what remains of `path` once the directories the declared package spells
/// and the file name are removed from the end: `a/b/src/main/java/demo/X.java`
/// declaring `package demo` has source root `a/b/src/main/java`. A path that does
/// not end the way its package says is not evidence of anything, so it has no
/// source root and the unit resolves nothing beyond itself
/// ([ADR 008](../../docs/adr/008_java_visibility_boundaries.md)).
///
/// The returned slice borrows from `path`.
pub fn sourceRoot(path: []const u8, package: []const u8) ?[]const u8 {
    if (package.len == 0) return null;
    const cut = std.mem.lastIndexOfScalar(u8, path, '/');
    const directory = if (cut) |index| path[0..index] else "";

    // The package spells its own directories, so it is compared segment by
    // segment from the end rather than as one string: a package `demo` must not
    // match a directory ending in `mydemo`.
    var remaining = directory;
    var segments = std.mem.splitBackwardsScalar(u8, package, '.');
    while (segments.next()) |segment| {
        if (segment.len == 0) return null;
        if (!std.mem.endsWith(u8, remaining, segment)) return null;
        remaining = remaining[0 .. remaining.len - segment.len];
        if (remaining.len == 0) break;
        if (remaining[remaining.len - 1] != '/') return null;
        remaining = remaining[0 .. remaining.len - 1];
    }
    // Every segment matched only if the walk consumed the whole package.
    if (segments.next() != null) return null;
    return remaining;
}

/// Whether a unit in source root `referring` may resolve a simple type name to a
/// top-level class another unit declares in source root `provider`.
///
/// One root is one visibility scope. The single exception is the standard
/// directory layout every Java build tool in common use imposes: a test source
/// root reads its own module's main source root, and never the other way round,
/// because main sources are compiled without test sources on the classpath.
pub fn sharesScope(referring: []const u8, provider: []const u8) bool {
    if (std.mem.eql(u8, referring, provider)) return true;

    // `<base>/src/test/<lang>` may read `<base>/src/main/<lang>`.
    const cut = std.mem.lastIndexOfScalar(u8, referring, '/');
    const language_directory = if (cut) |index| referring[index + 1 ..] else return false;
    const above = referring[0..cut.?];
    const base = if (std.mem.eql(u8, above, "src/test"))
        ""
    else if (std.mem.endsWith(u8, above, "/src/test"))
        above[0 .. above.len - "/src/test".len]
    else
        return false;

    if (!std.mem.startsWith(u8, provider, base)) return false;
    const tail = provider[base.len..];
    const expected = if (base.len == 0) "src/main/" else "/src/main/";
    if (!std.mem.startsWith(u8, tail, expected)) return false;
    return std.mem.eql(u8, tail[expected.len..], language_directory);
}

/// One top-level type declaration this frontend covers: a class or an
/// interface.
///
/// Both are declarations the graph holds
/// ([ADR 011](../../docs/adr/011_java_hierarchy_from_indexed_source.md)), and
/// every rule below that asks what a name in this unit may mean asks it of both:
/// an interface obscures a simple type name exactly as a class does, declares
/// methods a call may select exactly as a class does, and may declare
/// supertypes exactly as a class does.
const ClassInfo = struct {
    index: u32,
    name: []const u8,
    node: ts.Node,
    body: ?ts.Node,
    /// Whether it was written as an interface. It decides the role recorded, the
    /// construct label, and the access an unmodified member declares.
    is_interface: bool,
    /// The names its field declarations bind and the types they write — an
    /// interface's constants included, because a constant obscures a type of
    /// the same name inside a `default` or `static` method exactly as a field
    /// does (JLS 6.4.2). A receiver name one of them claims is read as a value
    /// of that type, not as a type name.
    fields: []const BoundName,
    /// Whether it declares a superclass or an interface, from which a method of
    /// an invoked name could be inherited.
    has_supertypes: bool,
};

const MethodInfo = struct {
    index: u32,
    name: []const u8,
    class_index: u32,
    class_name: []const u8,
    /// Whether the enclosing class declares a superclass or interfaces, from
    /// which a method of the invoked name could be inherited.
    class_has_supertypes: bool,
    /// The modifiers it declares, as the labels on its definition record them.
    access: Access,
    is_static: bool,
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
    var static_imported: std.ArrayList([]const u8) = .empty;
    defer static_imported.deinit(gpa);
    var other_types: std.ArrayList([]const u8) = .empty;
    defer other_types.deinit(gpa);
    var static_on_demand = false;

    // Pass 1: definitions. A relationship can only be expressed once every
    // definition in the unit has a batch-local index.
    var top_level = root.namedChildren();
    while (top_level.next()) |node| {
        const kind = node.kind();

        if (std.mem.eql(u8, kind, "package_declaration")) continue;
        if (std.mem.eql(u8, kind, "import_declaration")) {
            if (importedName(node, source)) |name| {
                const into = if (importsStatically(node)) &static_imported else &imported;
                try into.append(gpa, name);
            } else if (importsStatically(node) and importsOnDemand(node)) {
                static_on_demand = true;
            }
        } else if (isTypeDeclaration(kind)) {
            if (node.childByFieldName("name")) |name_node| {
                if (!isCoveredTypeDeclaration(kind)) try other_types.append(gpa, name_node.text(source));
            }
        }
        if (!isCoveredTypeDeclaration(kind)) {
            try builder.addDiagnostic(.unsupported_construct, try builder.print(
                "`{s}` at the top level is outside this frontend's coverage",
                .{kind},
            ));
            continue;
        }

        const is_interface = std.mem.eql(u8, kind, "interface_declaration");
        const name_node = node.childByFieldName("name") orelse {
            try builder.addDiagnostic(
                .unsupported_construct,
                "a type declaration without a name is outside this frontend's coverage",
            );
            continue;
        };
        const name = try builder.dupe(name_node.text(source));
        const has_supertypes = declaresSupertypes(node);
        const body_for_labels = node.childByFieldName("body");
        const declared_member_types = try memberTypeNames(builder, body_for_labels, source);
        const declared_fields = try fieldNames(builder, body_for_labels, source);
        const declared_supertypes = try declaredSupertypeNames(builder, node, source);

        const index = try builder.addEntity(.{
            .kind = .definition,
            .identity = .{
                .scope = scope,
                .language = .java,
                .role = if (is_interface) "interface" else "class",
                .name = name,
                .signature = name,
                .container_path = &.{},
            },
            .evidence = evidenceOf(builder, node, name),
            .extension = .{
                .namespace = "java",
                .labels = try builder.labels(&.{
                    .{ .key = "java.construct", .value = kind },
                    .{ .key = "java.package", .value = package },
                    .{
                        .key = class_shape.key,
                        .value = if (has_supertypes) class_shape.declared else class_shape.none,
                    },
                    .{ .key = member_types.key, .value = declared_member_types },
                    .{ .key = field_names.key, .value = declared_fields },
                    .{ .key = supertype_names.key, .value = declared_supertypes },
                }),
            },
            .resolution = .{ .fact = .{
                .method = if (is_interface)
                    "interface declaration in the analyzed source unit"
                else
                    "class declaration in the analyzed source unit",
            } },
        });

        const body = node.childByFieldName("body");
        try classes.append(gpa, .{
            .index = index,
            .name = name,
            .node = node,
            .body = body,
            .is_interface = is_interface,
            .fields = &.{},
            .has_supertypes = has_supertypes,
        });
        const class_slot = classes.items.len - 1;

        var fields: std.ArrayList(BoundName) = .empty;
        defer fields.deinit(gpa);

        const class_body = body orelse continue;
        var members = class_body.namedChildren();
        while (members.next()) |member| {
            const member_kind = member.kind();
            // An interface writes its fields as `constant_declaration`. They are
            // outside this frontend's coverage exactly as a class field is, and
            // they obscure a type of the same name exactly as a class field
            // does, so they are collected here and reported below.
            if (std.mem.eql(u8, member_kind, "field_declaration") or
                std.mem.eql(u8, member_kind, "constant_declaration"))
            {
                try appendDeclaredBindings(gpa, &fields, member, source);
            }
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
            const modifiers = modifiersOf(member, is_interface);

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
                        .{ .key = method_access.key, .value = modifiers.access },
                        .{
                            .key = method_static.key,
                            .value = if (modifiers.is_static) method_static.yes else method_static.no,
                        },
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
                .class_has_supertypes = has_supertypes,
                .access = Access.fromLabel(modifiers.access),
                .is_static = modifiers.is_static,
                .node = member,
            });
        }

        classes.items[class_slot].fields = try builder.arena.allocator().dupe(BoundName, fields.items);
    }

    if (classes.items.len == 0) {
        try builder.addDiagnostic(
            .confirmed_absence,
            "the source unit parsed and declares no class or interface within this frontend's coverage",
        );
    }

    const unit_scope: UnitScope = .{
        .package = package,
        .classes = classes.items,
        .imported = imported.items,
        .static_imported = static_imported.items,
        .static_on_demand = static_on_demand,
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

        try emitSupertypeReferences(builder, source, class, unit_scope);

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
        var bindings: Bindings = .{};
        defer bindings.deinit(gpa);
        try emitInvocations(builder, source, .{
            .unit = unit_scope,
            .class = classByIndex(classes.items, method.class_index),
            .method = method,
            .methods = methods.items,
            .bindings = &bindings,
        }, body, false, 0);
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
    /// Simple names brought in by single-type imports.
    imported: []const []const u8,
    /// Simple names brought in by single static imports. A static import names a
    /// member, so it is a reason to decline, never a target.
    static_imported: []const []const u8,
    /// Whether the unit writes `import static a.b.C.*;`.
    ///
    /// Such a declaration brings every accessible static member of `C` into
    /// scope, including its fields, and a variable obscures a type of the same
    /// name (JLS 6.4.2) whichever way the type reached the unit — its own
    /// package or a single-type import. The names it binds cannot be
    /// enumerated: this frontend does not record fields as definitions, so
    /// `C`'s static field names are not in the graph even when `C` is indexed,
    /// and `C` is usually a dependency that is not indexed at all. What cannot
    /// be enumerated cannot be disproved, so a simple-name receiver in such a
    /// unit is declined the way an enclosing class with supertypes is declined
    /// ([ADR 009](../../docs/adr/009_java_static_calls.md), condition 2).
    ///
    /// It says nothing about a type position: there no variable competes for
    /// the name, so `resolveType` is left alone.
    static_on_demand: bool,
    /// Top-level enums, records, and annotation types. This frontend does not
    /// cover them, but they still claim their names. Interfaces are no longer
    /// here: since [ADR 011](../../docs/adr/011_java_hierarchy_from_indexed_source.md)
    /// a top-level interface is a declaration this unit holds, so it is found in
    /// `classes` and resolves rather than declining.
    other_types: []const []const u8,
    context: Context,
};

/// Where in a type declaration a name was written.
///
/// It decides one thing, and only one: whether the enclosing type's own
/// supertypes may give the name another meaning. Inside the body they may — a
/// member type could be inherited. In the `extends` or `implements` clause they
/// may not, because the scope of a member declared in or inherited by a type is
/// the *body* of that type (JLS 6.3), and the header is not the body. A type
/// cannot inherit a name before it has said what it inherits from.
const Position = enum { body, supertype };

/// Where one type reference sits.
const TypeScope = struct {
    unit: UnitScope,
    class: ClassInfo,
    /// The method whose return type is being read, if any.
    method: ?ts.Node,
    position: Position = .body,
};

/// What every claim a declared supertype makes carries in front of
/// `resolveType`'s own words, on the resolved and the unresolved path alike.
///
/// A relationship carries no extension payload, so this prefix is how a claim
/// says which position it was read in. `java_hierarchy` reads it back to walk
/// the hierarchy and nothing else; both ends name this one constant, so the two
/// cannot drift apart.
pub const supertype_claim = struct {
    pub const prefix = "declared supertype: ";

    pub fn marks(words: []const u8) bool {
        return std.mem.startsWith(u8, words, prefix);
    }
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
        .resolution = switch (scope.position) {
            .body => resolved.resolution,
            .supertype => try markSupertype(builder, resolved.resolution),
        },
    });
    if (resolved.provider) |provider| try declareProvider(
        builder,
        provider,
        "resolved a simple type name to a top-level class declared in the same Java package",
    );
}

/// The same answer, saying which position it was read in.
///
/// `resolveType`'s own words are kept verbatim behind the prefix. A supertype
/// that does not resolve therefore still says exactly why, which is what makes
/// an open chain visible as an unresolved name rather than as an absence.
fn markSupertype(
    builder: *contract.BatchBuilder,
    resolution: model.Resolution,
) !model.Resolution {
    return switch (resolution) {
        .fact => |established| .{ .fact = .{
            .method = try builder.print("{s}{s}", .{ supertype_claim.prefix, established.method }),
        } },
        .unresolved => |declined| .{ .unresolved = .{
            .missing = declined.missing,
            .explanation = try builder.print("{s}{s}", .{ supertype_claim.prefix, declined.explanation }),
        } },
        // This frontend records none, and inventing one here would be the first.
        .approximate => resolution,
    };
}

/// Emits one `references` claim per declared supertype, from the declaring
/// type's own entity, resolved in the declaring unit's scope.
///
/// That scope is the only correct one: what `Foo` means in an `extends` clause
/// is decided by the imports and package of the unit that wrote it, never by a
/// unit that later walks the chain
/// ([ADR 011](../../docs/adr/011_java_hierarchy_from_indexed_source.md), D3).
fn emitSupertypeReferences(
    builder: *contract.BatchBuilder,
    source: []const u8,
    class: ClassInfo,
    unit: UnitScope,
) !void {
    const scope: TypeScope = .{
        .unit = unit,
        .class = class,
        .method = null,
        .position = .supertype,
    };
    if (class.node.childByFieldName("superclass")) |superclass| {
        try emitSupertypeList(builder, source, class.index, superclass, scope);
    }
    if (class.node.childByFieldName("interfaces")) |interfaces| {
        try emitSupertypeList(builder, source, class.index, interfaces, scope);
    }
    var children = class.node.namedChildren();
    while (children.next()) |child| {
        if (!std.mem.eql(u8, child.kind(), "extends_interfaces")) continue;
        try emitSupertypeList(builder, source, class.index, child, scope);
    }
}

/// A `superclass` holds its type directly; a `super_interfaces` and an
/// `extends_interfaces` hold a `type_list` of them.
fn emitSupertypeList(
    builder: *contract.BatchBuilder,
    source: []const u8,
    from: u32,
    holder: ts.Node,
    scope: TypeScope,
) !void {
    var children = holder.namedChildren();
    while (children.next()) |child| {
        const kind = child.kind();
        if (std.mem.eql(u8, kind, "annotation") or std.mem.eql(u8, kind, "marker_annotation")) continue;
        if (std.mem.eql(u8, kind, "type_list")) {
            var types = child.namedChildren();
            while (types.next()) |entry| {
                try emitTypeReference(builder, source, from, entry, scope);
            }
            continue;
        }
        try emitTypeReference(builder, source, from, child, scope);
    }
}

/// Resolves a type name the way ADR 004 and ADR 008 permit and no further.
///
/// A name declared in the unit is a local fact, as before. Otherwise only a
/// simple name in a unit with an explicit package may reach another unit, and
/// only after ruling out everything Java would let take precedence: a type
/// parameter, a member type (declared or inherited), a static import, and a type
/// declared in this unit. What remains is decided in Java's own order — a
/// single-type import beats the unit's own package — and only ever inside the
/// unit's visibility scope. When one of those cannot be ruled out the name stays
/// unresolved and says why, because a match that ignored them would be a string
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
    if (!isSimpleTypeName(kind)) {
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
    // The guard reads the enclosing type's recorded shape rather than two class
    // fields, so an interface's `extends` counts exactly as a class's does. It
    // lifts only where the chain above the type is closed in indexed source and
    // nothing it reaches declares a member type of this name (ADR 011 D4, D6).
    if (scope.position == .body and scope.class.has_supertypes) {
        try declareChainProviders(builder, unit, scope.class, source, builder.gpa);
        if (try chainRulesOut(builder, unit, scope.class, source, name, .member_type)) |reason| {
            return unresolvedType(name, reason);
        }
    }
    if (containsName(unit.static_imported, name)) {
        return unresolvedType(name, "a static import names this type, and a static import " ++
            "names a member this frontend does not resolve");
    }
    if (containsName(unit.other_types, name)) {
        return unresolvedType(name, "the analyzed source unit declares a non-class type of this name, " ++
            "which this frontend does not cover");
    }

    // A single-type import beats the unit's own package, so it is asked first
    // and its answer is final either way: a name Java takes from an import does
    // not fall back to the package.
    if (unit.context.importLookup(name)) |binding| return switch (binding) {
        .unique => |target| .{
            .target = .{ .external = target },
            .resolution = .{ .fact = .{
                .method = "the single-type import of this name, and the only current top-level " ++
                    "class of it in the imported package",
            } },
            .provider = target.provider,
        },
        .ambiguous => |count| unresolvedType(name, try builder.print(
            "the single-type import of this name reaches {d} current top-level classes of it, " ++
                "so the name is ambiguous",
            .{count},
        )),
        .out_of_scope => |count| unresolvedType(name, try builder.print(
            "the single-type import of this name reaches {d} current top-level " ++
                "{s} of it, none in a Java source root this unit can see",
            .{ count, if (count == 1) "class" else "classes" },
        )),
    };
    if (containsName(unit.imported, name)) {
        return unresolvedType(name, "a single-type import names this type, and no indexed " ++
            "source unit declares it in the package the import names");
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
        .out_of_scope => |count| unresolvedType(name, try builder.print(
            "package `{s}` declares {d} current top-level {s} of this name, " ++
                "none of them in a Java source root this unit can see",
            .{ unit.package, count, if (count == 1) "class" else "classes" },
        )),
    };
}

/// What a chain walk answers, and the words each answer is declined with.
///
/// Every condition is its own sentence. A widened rule that collapsed six
/// declines into one would make the families that this plan converts
/// indistinguishable from the families it does not, which is the failure the
/// counters exist to make impossible.
pub const chain = struct {
    pub const depth_cap: u32 = 16;

    /// What each guard walks the chain to rule out. It is named in every
    /// decline, so a reader can tell a reference's answer from a receiver's
    /// even where the condition that failed is the same one.
    pub fn ruledOut(what: Member) []const u8 {
        return switch (what) {
            .member_type => "a member type it may inherit under this name",
            .field => "a field it may inherit under this name",
            .method => "a method of this name it may inherit",
        };
    }

    /// The conditions that leave a chain open, each a contiguous phrase that
    /// does not mention what was being ruled out — so one counter can hold a
    /// condition across all three guards, and the sentence still says both.
    pub const unresolved_here = "one of them is not resolved";
    pub const ambiguous = "one of them is ambiguous";
    pub const out_of_scope = "one of them is declared outside this unit's visibility scope";
    pub const not_read = "this analysis did not read what one of them reaches";
    pub const unresolved_above = "a supertype somewhere in its chain is not resolved";
    pub const not_a_type = "a supertype somewhere in its chain is not a Java class or interface";
    pub const provider_stale = "a type in its chain is declared in a unit whose analysis is not current";
    pub const cycle = "its declared chain contains a cycle";
    pub const too_deep = "its declared chain is deeper than this analysis walks";

    pub fn openWords(
        builder: *contract.BatchBuilder,
        condition: []const u8,
        what: Member,
    ) ![]const u8 {
        return builder.print(
            "the enclosing type has supertypes and {s}, so {s} is not ruled out",
            .{ condition, ruledOut(what) },
        );
    }

    pub fn declaresWords(builder: *contract.BatchBuilder, what: Member) ![]const u8 {
        return builder.print(
            "a type in the enclosing type's supertype chain declares {s} of this name",
            .{switch (what) {
                .member_type => "a member type",
                .field => "a field",
                .method => "a method",
            }},
        );
    }
};

/// Whether the chain above `class` is closed in indexed source and nothing it
/// reaches declares `name`.
///
/// Returns null when the chain rules the name out, and the condition that
/// failed otherwise. It never returns an entity: the chain is walked to rule
/// out and never to select (ADR 011 D6), so no caller can turn this into a
/// target.
///
/// The local half is walked from this unit's own source, because a type this
/// unit declares is one the frontend can read directly. The external half is
/// one lookup: the analyzer already walked the whole closure of every supertype
/// name this unit writes and summarised it.
fn chainRulesOut(
    builder: *contract.BatchBuilder,
    unit: UnitScope,
    class: ClassInfo,
    source: []const u8,
    name: []const u8,
    what: Member,
) !?[]const u8 {
    const gpa = builder.gpa;
    var path: std.ArrayList(u32) = .empty;
    defer path.deinit(gpa);
    var nodes: std.ArrayList(ts.Node) = .empty;
    defer nodes.deinit(gpa);
    return walkChain(builder, unit, class, source, name, what, &path, &nodes, 0);
}

fn walkChain(
    builder: *contract.BatchBuilder,
    unit: UnitScope,
    class: ClassInfo,
    source: []const u8,
    name: []const u8,
    what: Member,
    path: *std.ArrayList(u32),
    nodes: *std.ArrayList(ts.Node),
    depth: u32,
) !?[]const u8 {
    const gpa = builder.gpa;
    if (depth >= chain.depth_cap) return try chain.openWords(builder, chain.too_deep, what);
    if (std.mem.indexOfScalar(u32, path.items, class.index) != null) {
        return try chain.openWords(builder, chain.cycle, what);
    }

    const mark = nodes.items.len;
    defer nodes.shrinkRetainingCapacity(mark);
    try collectSupertypeNodes(gpa, class.node, nodes);
    // Taken once: deeper frames append past this mark and truncate back to it,
    // so these entries never move.
    const count = nodes.items.len - mark;

    try path.append(gpa, class.index);
    defer _ = path.pop();

    var at: usize = 0;
    while (at < count) : (at += 1) {
        const supertype = nodes.items[mark + at];
        // A supertype written generically, qualified, or as anything but a bare
        // name is what `resolveType` declines, so the chain is open there.
        if (!std.mem.eql(u8, supertype.kind(), "type_identifier")) {
            return try chain.openWords(builder, chain.unresolved_here, what);
        }
        const supertype_name = supertype.text(source);

        if (findClassInfo(unit.classes, supertype_name)) |local| {
            if (declaresLocally(local, source, name, what)) return try chain.declaresWords(builder, what);
            if (try walkChain(builder, unit, local, source, name, what, path, nodes, depth + 1)) |reason| {
                return reason;
            }
            continue;
        }

        const reached = unit.context.hierarchyLookup(supertype_name) orelse {
            // No entry means the analyzer read nothing for the name. Why it
            // read nothing is a question the same bindings answer, in the same
            // terms `resolveType` would use.
            const binding = unit.context.importLookup(supertype_name) orelse
                unit.context.lookup(unit.package, supertype_name);
            const condition = if (binding) |found| switch (found) {
                .unique => chain.not_read,
                .ambiguous => chain.ambiguous,
                .out_of_scope => chain.out_of_scope,
            } else chain.unresolved_here;
            return try chain.openWords(builder, condition, what);
        };
        if (reached.open) |condition| return try chain.openWords(builder, condition, what);
        if (reached.declares(what, name)) return try chain.declaresWords(builder, what);
    }
    return null;
}

/// Whether a type this unit declares itself binds `name` in the way `what` asks
/// about. Its methods are not read here: an unqualified invocation is the only
/// guard that asks about a method, and it reads the unit's own method list.
fn declaresLocally(class: ClassInfo, source: []const u8, name: []const u8, what: Member) bool {
    return switch (what) {
        .member_type => declaresMemberType(class.body, source, name),
        .field => bindsName(class.fields, name),
        .method => declaresMethodNamed(class.body, source, name),
    };
}

fn declaresMethodNamed(body: ?ts.Node, source: []const u8, name: []const u8) bool {
    const type_body = body orelse return false;
    var members = type_body.namedChildren();
    while (members.next()) |member| {
        if (!std.mem.eql(u8, member.kind(), "method_declaration")) continue;
        const declared = member.childByFieldName("name") orelse continue;
        if (std.mem.eql(u8, declared.text(source), name)) return true;
    }
    return false;
}

fn findClassInfo(classes: []const ClassInfo, name: []const u8) ?ClassInfo {
    for (classes) |class| {
        if (std.mem.eql(u8, class.name, name)) return class;
    }
    return null;
}

/// Declares a dependency on every unit a used chain spans, so an edit to any
/// type in it reanalyzes this reader (ADR 011 D7).
fn declareChainProviders(
    builder: *contract.BatchBuilder,
    unit: UnitScope,
    class: ClassInfo,
    source: []const u8,
    gpa: std.mem.Allocator,
) !void {
    var nodes: std.ArrayList(ts.Node) = .empty;
    defer nodes.deinit(gpa);
    try collectSupertypeNodes(gpa, class.node, &nodes);
    for (nodes.items) |supertype| {
        if (!std.mem.eql(u8, supertype.kind(), "type_identifier")) continue;
        const reached = unit.context.hierarchyLookup(supertype.text(source)) orelse continue;
        for (reached.providers) |provider| {
            try declareProvider(
                builder,
                provider,
                "walked the declared supertype chain of the enclosing type",
            );
        }
    }
}

/// How a simple type name can be written where this frontend reads one.
///
/// A type position writes it as `type_identifier`. A receiver that may be a
/// class name writes the same name as `identifier`, because the parser cannot
/// know which it is — that is the question ADR 009 makes the frontend answer.
/// Both spell one name, and the rules that decide what it means are the same,
/// so `resolveType` accepts either and no existing answer moves: no type
/// position parses as an `identifier`.
fn isSimpleTypeName(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "type_identifier") or std.mem.eql(u8, kind, "identifier");
}

/// A type reference keeps the name the source wrote, unsplit.
///
/// [ADR 010](../../docs/adr/010_designator_is_a_structured_name.md) leaves type
/// syntax out of its rewrite: a type name is already a name in the dominant
/// case, and generic and qualified type syntax is a separate decision with its
/// own evidence.
fn unresolvedType(name: []const u8, explanation: []const u8) TypeResolution {
    return .{
        .target = .{ .designator = .{ .name = name } },
        .resolution = .{ .unresolved = .{ .missing = .target_entity, .explanation = explanation } },
    };
}

/// Declares that this unit's analysis read another unit, once per provider.
///
/// One declaration per provider is what the write path needs: it invalidates by
/// unit, so a second reason would add a row and change nothing. The first
/// reason recorded is the one kept, and it names a real thing this unit read.
fn declareProvider(
    builder: *contract.BatchBuilder,
    provider: model.SourceUnitId,
    reason: []const u8,
) !void {
    for (builder.dependencies.items) |declared| {
        if (declared.provider == provider) return;
    }
    try builder.addDependency(provider, reason);
}

/// The two type declarations this frontend records as definitions.
///
/// An enum, a record, and an annotation type are deliberately not here. None of
/// them can appear in a supertype chain, so admitting them would widen this
/// frontend into general Java type coverage without answering the question
/// interfaces answer
/// ([ADR 011](../../docs/adr/011_java_hierarchy_from_indexed_source.md)). They
/// keep their `unsupported_construct` diagnostic and keep claiming their names.
fn isCoveredTypeDeclaration(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "class_declaration") or
        std.mem.eql(u8, kind, "interface_declaration");
}

/// Whether a type declaration writes any supertype.
///
/// A class writes them in the `superclass` and `interfaces` fields. An interface
/// writes them in an `extends_interfaces` child, which carries no field name and
/// so is reachable only by walking the children.
fn declaresSupertypes(node: ts.Node) bool {
    if (node.childByFieldName("superclass") != null) return true;
    if (node.childByFieldName("interfaces") != null) return true;
    var children = node.namedChildren();
    while (children.next()) |child| {
        if (std.mem.eql(u8, child.kind(), "extends_interfaces")) return true;
    }
    return false;
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

/// The names of the type declarations directly inside a type body, joined for
/// the `java.member_types` label. Empty when it declares none.
fn memberTypeNames(
    builder: *contract.BatchBuilder,
    body: ?ts.Node,
    source: []const u8,
) ![]const u8 {
    const type_body = body orelse return "";
    var joined: std.ArrayList(u8) = .empty;
    defer joined.deinit(builder.gpa);

    var members = type_body.namedChildren();
    while (members.next()) |member| {
        if (!isTypeDeclaration(member.kind())) continue;
        const name = member.childByFieldName("name") orelse continue;
        if (joined.items.len != 0) try joined.append(builder.gpa, member_types.separator);
        try joined.appendSlice(builder.gpa, name.text(source));
    }
    return builder.dupe(joined.items);
}

/// The names a type's field declarations bind, joined for the
/// `java.field_names` label. An interface's constants are fields here, as they
/// are everywhere else in this frontend.
fn fieldNames(
    builder: *contract.BatchBuilder,
    body: ?ts.Node,
    source: []const u8,
) ![]const u8 {
    const type_body = body orelse return "";
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(builder.gpa);

    var members = type_body.namedChildren();
    while (members.next()) |member| {
        const kind = member.kind();
        if (!std.mem.eql(u8, kind, "field_declaration") and
            !std.mem.eql(u8, kind, "constant_declaration")) continue;
        try appendDeclaredNames(builder.gpa, &names, member, source);
    }
    return joinNames(builder, names.items, field_names.separator);
}

/// The simple names a type writes in a supertype position, joined for the
/// `java.supertype_names` label. A name written generically or qualified is
/// kept as written, because the label exists to change when the declaration
/// changes, not to be resolved.
fn declaredSupertypeNames(
    builder: *contract.BatchBuilder,
    declaration: ts.Node,
    source: []const u8,
) ![]const u8 {
    var nodes: std.ArrayList(ts.Node) = .empty;
    defer nodes.deinit(builder.gpa);
    try collectSupertypeNodes(builder.gpa, declaration, &nodes);

    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(builder.gpa);
    for (nodes.items) |node| try names.append(builder.gpa, node.text(source));
    return joinNames(builder, names.items, supertype_names.separator);
}

fn joinNames(
    builder: *contract.BatchBuilder,
    names: []const []const u8,
    separator: u8,
) ![]const u8 {
    var joined: std.ArrayList(u8) = .empty;
    defer joined.deinit(builder.gpa);
    for (names) |name| {
        if (joined.items.len != 0) try joined.append(builder.gpa, separator);
        try joined.appendSlice(builder.gpa, name);
    }
    return builder.dupe(joined.items);
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

/// What deciding one invocation reads: the unit it is written in, the class and
/// method it is written in, and the names bound around it.
const CallScope = struct {
    unit: UnitScope,
    class: ClassInfo,
    method: MethodInfo,
    /// Every method the unit declares, which is what an unqualified invocation
    /// selects from.
    methods: []const MethodInfo,
    bindings: *Bindings,
};

/// The names bound where an invocation is written.
///
/// Java lets a variable obscure a type of the same name, so a receiver that is
/// a simple name names a class only where nothing else claims that name
/// ([ADR 009](../../docs/adr/009_java_static_calls.md)). Proving it needs the
/// set of names bound at the invocation and never their types, which is why
/// this frontend can answer it without a type environment over method bodies.
///
/// Two tiers, because Java scopes them differently and only one difference
/// changes an answer this project measured:
///
/// - `method` holds what is bound for the whole method: its parameters, the
///   enclosing class's fields, and every construct whose binding reaches past
///   its own subtree — a `for` variable, a `catch` parameter, a
///   try-with-resources resource, a lambda parameter, a type or record
///   pattern. Reading those as bound everywhere in the method declines a call
///   written before the binding. That is a decline and never a wrong fact.
/// - `locals` holds local variables, which Java binds from their declarator to
///   the end of their block. That rule is followed exactly, because the
///   method-wide approximation would read a class name as a variable that does
///   not exist yet where the call is written.
const Bindings = struct {
    method: std.ArrayList(BoundName) = .empty,
    /// Whether `method` has been collected. It is collected on the first
    /// simple-name receiver the method contains, because collecting walks the
    /// whole method and a method with no such receiver never asks.
    collected: bool = false,
    locals: std.ArrayList(BoundName) = .empty,

    fn deinit(self: *Bindings, gpa: std.mem.Allocator) void {
        self.method.deinit(gpa);
        self.locals.deinit(gpa);
    }
};

/// `nested` is set once the walk enters a type body declared inside the method,
/// such as an anonymous or local class: there an unqualified name may mean a
/// method of that type rather than of the enclosing class, and a declaration of
/// that body may give a receiver name another meaning.
fn emitInvocations(
    builder: *contract.BatchBuilder,
    source: []const u8,
    scope: CallScope,
    node: ts.Node,
    nested: bool,
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
        try emitInvocation(builder, source, scope, node, nested);
    }

    const inner = nested or isTypeBody(node.kind());
    // A local variable is bound from its declarator to the end of the block it
    // is written in: it claims its name for the siblings that follow it, and
    // for nothing before them.
    const mark = scope.bindings.locals.items.len;
    defer scope.bindings.locals.shrinkRetainingCapacity(mark);

    var children = node.namedChildren();
    while (children.next()) |child| {
        try emitInvocations(builder, source, scope, child, inner, depth + 1);
        if (std.mem.eql(u8, child.kind(), "local_variable_declaration")) {
            try appendDeclaredBindings(builder.gpa, &scope.bindings.locals, child, source);
        }
    }
}

fn isTypeBody(kind: []const u8) bool {
    const kinds = [_][]const u8{ "class_body", "interface_body", "enum_body", "annotation_type_body" };
    for (kinds) |candidate| {
        if (std.mem.eql(u8, kind, candidate)) return true;
    }
    return false;
}

fn emitInvocation(
    builder: *contract.BatchBuilder,
    source: []const u8,
    scope: CallScope,
    node: ts.Node,
    nested: bool,
) !void {
    const name_node = node.childByFieldName("name") orelse return;
    const name = try builder.dupe(name_node.text(source));

    // The invocation names a method, and the name it names it by is the `name`
    // field — whatever the receiver turns out to be. What the source wrote
    // around that name is the evidence, which is why the written text is read
    // here and handed to `evidenceOf` rather than being the designator.
    const written = try builder.dupe(node.text(source));
    const receiver = node.childByFieldName("object");
    const target = if (receiver) |object|
        try qualifiedTarget(builder, source, scope, object, name, nested)
    else
        try invocationTarget(builder, source, scope, name, nested);

    try builder.addRelationship(.{
        .kind = .calls,
        .source = .{ .entity = scope.method.index },
        .target = if (target.index) |index|
            .{ .local = index }
        else if (target.external) |external|
            .{ .external = external }
        else
            .{ .designator = .{ .name = name, .qualifier = target.qualifier } },
        .evidence = evidenceOf(builder, node, written),
        .resolution = target.resolution,
    });
    if (target.external) |external| try declareProvider(
        builder,
        external.provider,
        "resolved a class-qualified invocation to a static method that class declares",
    );
}

const InvocationTarget = struct {
    /// Set when the target is a definition in the analyzed unit.
    index: ?u32 = null,
    /// Set when the target is a definition another unit established, which the
    /// batch must also declare a dependency on.
    external: ?contract.ExternalTarget = null,
    /// The receiver name, set only where this frontend established that the
    /// receiver names a class and then declined to pick a method of it. A
    /// receiver it reads as a value, or does not read at all, leaves this
    /// absent: a qualifier is a scope the source named, never an expression it
    /// happened to write ([ADR 010](../../docs/adr/010_designator_is_a_structured_name.md)).
    qualifier: ?[]const u8 = null,
    resolution: model.Resolution,
};

/// Decides an invocation's target the way Java would select it, or leaves it
/// unresolved with the reason.
///
/// Java picks among every method of the invoked name the enclosing class has,
/// declared or inherited, by argument types. This frontend does not type
/// arguments or read supertypes, so an unqualified invocation is a fact only
/// when there is exactly one candidate to pick: one method of that name, in a
/// class with no supertypes, invoked from the class's own scope. Anything else
/// names a method without establishing which one.
fn invocationTarget(
    builder: *contract.BatchBuilder,
    source: []const u8,
    scope: CallScope,
    name: []const u8,
    nested: bool,
) !InvocationTarget {
    if (nested) return unresolvedInvocation("the invocation is inside a class body declared in the method, " ++
        "where the name may mean a method of that class");

    var found: ?u32 = null;
    var count: u32 = 0;
    for (scope.methods) |candidate| {
        work.candidate();
        if (!std.mem.eql(u8, candidate.class_name, scope.method.class_name)) continue;
        if (!std.mem.eql(u8, candidate.name, name)) continue;
        found = candidate.index;
        count += 1;
    }
    if (count == 0) return unresolvedInvocation("no method of this name is declared in the enclosing class");
    if (count > 1) return unresolvedInvocation(try builder.print(
        "{d} methods of this name are declared in the enclosing class, and overloads are not resolved",
        .{count},
    ));
    if (scope.method.class_has_supertypes) {
        try declareChainProviders(builder, scope.unit, scope.class, source, builder.gpa);
        if (try chainRulesOut(builder, scope.unit, scope.class, source, name, .method)) |reason| {
            return unresolvedInvocation(reason);
        }
    }
    return .{
        .index = found,
        .resolution = .{ .fact = .{
            .method = unqualified_call_method,
        } },
    };
}

/// Decides what the receiver of a qualified invocation is, which is as far as
/// this frontend goes today: which method of that class the invocation names is
/// not decided here, so no qualified invocation is a fact yet.
///
/// The order the conditions are asked in is the order in which an answer stops
/// being available. A receiver that is not a simple name carries no name to
/// read; a name a binding claims is a value, whatever else exists; a class that
/// declares supertypes may inherit a field nobody here can see, so the name
/// cannot be cleared even when nothing visible claims it. Only then is the name
/// a candidate for `resolveType`, which decides what a simple name means under
/// ADR 004 and ADR 008 and keeps its own explanations when it declines.
fn qualifiedTarget(
    builder: *contract.BatchBuilder,
    source: []const u8,
    scope: CallScope,
    receiver: ts.Node,
    method: []const u8,
    nested: bool,
) !InvocationTarget {
    if (std.mem.eql(u8, receiver.kind(), "this")) {
        if (nested) return unresolvedInvocation("the invocation is inside a class body declared in the method, " ++
            "where `this` is that class rather than the enclosing one");
        // The enclosing type is known exactly, so `this.m()` is decided on the
        // same terms a covered binding of that type is
        // ([ADR 012](../../docs/adr/012_java_value_receiver_calls.md), D10).
        return ownTypeTarget(builder, source, scope, scope.class, method);
    }
    if (!std.mem.eql(u8, receiver.kind(), "identifier")) {
        // `super.m()` is here, and stays here: naming the method it reaches
        // would be selecting an inherited member, which ADR 011 D6 forbids.
        return unresolvedInvocation("the invocation is qualified by a receiver this frontend does not resolve");
    }
    if (nested) return unresolvedInvocation("the invocation is inside a class body declared in the method, " ++
        "where a declaration of that class body may give the receiver name another meaning");

    const name = receiver.text(source);
    if (try boundName(builder.gpa, source, scope, name)) |bound| {
        return valueReceiverTarget(builder, source, scope, bound, method);
    }
    if (scope.unit.static_on_demand) {
        return unresolvedInvocation(try builder.print(
            "the unit imports static members on demand, which may bind `{s}` to a field that obscures " ++
                "a class of that name, and the members such an import brings in cannot be enumerated here",
            .{name},
        ));
    }
    if (scope.class.has_supertypes) {
        try declareChainProviders(builder, scope.unit, scope.class, source, builder.gpa);
        if (try chainRulesOut(builder, scope.unit, scope.class, source, name, .field)) |reason| {
            return unresolvedInvocation(reason);
        }
    }

    // Duped once: from here on the name may become a designator's qualifier,
    // which outlives the source buffer the node points into.
    const class_name = try builder.dupe(name);
    const resolved = try resolveType(builder, source, receiver, class_name, .{
        .unit = scope.unit,
        .class = scope.class,
        .method = scope.method.node,
    });
    switch (resolved.resolution) {
        .fact => {},
        .unresolved => |reason| return unresolvedInvocation(try builder.print(
            "the receiver is not read as a class: {s}",
            .{reason.explanation},
        )),
        .approximate => return unresolvedInvocation(
            "the receiver is not read as a class, and this frontend records no approximate target",
        ),
    }

    return switch (resolved.target) {
        .local => |index| localStaticTarget(builder, scope, index, class_name, method),
        .external => externalStaticTarget(builder, scope, class_name, method),
        // `resolveType` answers a fact with a target it established.
        .designator => unreachable,
    };
}

/// The method a receiver that is a value of a known declared type selects.
///
/// Every condition ADR 012 D10 lists is asked here, in order, and each failure
/// keeps a reason of its own. Nothing about the binding itself decides the
/// call: the declared type is resolved by the unchanged `resolveType`, and the
/// method is selected by the same candidate table a class-qualified call uses.
fn valueReceiverTarget(
    builder: *contract.BatchBuilder,
    source: []const u8,
    scope: CallScope,
    bound: BoundName,
    method: []const u8,
) !InvocationTarget {
    switch (bound.why) {
        .covered => {},
        .uncovered_introducer => return unresolvedInvocation(try builder.print(
            "the receiver name `{s}` is bound here by a construct this frontend reads no type from",
            .{bound.name},
        )),
        .uncovered_type => return unresolvedInvocation(try builder.print(
            "the receiver name `{s}` is declared here with a type this frontend does not read: " ++
                "generic, array, or inferred",
            .{bound.name},
        )),
    }

    const type_name = try builder.dupe(bound.type_name);
    const resolved = try resolveType(builder, source, bound.type_node.?, type_name, .{
        .unit = scope.unit,
        .class = scope.class,
        .method = scope.method.node,
    });
    switch (resolved.resolution) {
        .fact => {},
        .unresolved => |reason| return unresolvedInvocation(try builder.print(
            "the receiver's declared type `{s}` is not read as a type: {s}",
            .{ type_name, reason.explanation },
        )),
        .approximate => return unresolvedInvocation(
            "the receiver's declared type is not read as a type, and this frontend records no approximate target",
        ),
    }

    return switch (resolved.target) {
        .local => |index| ownTypeTarget(builder, source, scope, classByIndex(scope.unit.classes, index), method),
        .external => externalValueTarget(builder, scope, type_name, method),
        // `resolveType` answers a fact with a target it established.
        .designator => unreachable,
    };
}

/// The method a receiver whose type this unit declares selects — a value of a
/// type in this unit, or `this`.
fn ownTypeTarget(
    builder: *contract.BatchBuilder,
    source: []const u8,
    scope: CallScope,
    target: ClassInfo,
    method: []const u8,
) !InvocationTarget {
    if (target.has_supertypes) {
        try declareChainProviders(builder, scope.unit, target, source, builder.gpa);
        if (try chainRulesOut(builder, scope.unit, target, source, method, .method)) |reason| {
            return unresolvedInvocation(reason);
        }
    }

    var found: ?MethodInfo = null;
    var count: u32 = 0;
    for (scope.methods) |candidate| {
        work.candidate();
        if (!std.mem.eql(u8, candidate.class_name, target.name)) continue;
        if (!std.mem.eql(u8, candidate.name, method)) continue;
        if (count == 0) found = candidate;
        count += 1;
    }
    if (count == 0) return valueNoSuchMethod(builder, target.name);
    if (count > 1) return valueOverloaded(builder, target.name, count);

    const only = found.?;
    // A type reaches whatever it declares; another type in the same unit is as
    // far away as one in another unit.
    if (only.access != .public and target.index != scope.class.index) {
        return valueInaccessible(builder, target.name, method, only.access);
    }
    return .{
        .index = only.index,
        .resolution = .{ .fact = .{ .method = value_call_method } },
    };
}

/// The method a receiver whose declared type another unit declares selects,
/// read from the candidates the analyzer offered for that type.
fn externalValueTarget(
    builder: *contract.BatchBuilder,
    scope: CallScope,
    type_name: []const u8,
    method: []const u8,
) !InvocationTarget {
    const members = scope.unit.context.memberLookup(type_name) orelse
        return unresolvedInvocation(try builder.print(
            "the receiver's declared type `{s}` names a type whose current shape this analysis did not read",
            .{type_name},
        ));
    switch (members.supertypes) {
        .none => {},
        .declared => {
            // The target's own chain has to rule the invoked name out, exactly
            // as the enclosing type's does for a class-name receiver.
            const reached = scope.unit.context.hierarchyLookup(type_name) orelse
                return unresolvedInvocation(try builder.print(
                    "the receiver's declared type `{s}` declares supertypes this analysis did not read",
                    .{type_name},
                ));
            if (reached.open) |condition| return unresolvedInvocation(try builder.print(
                "the receiver's declared type `{s}` declares supertypes and {s}, " ++
                    "so a method of this name it may inherit is not ruled out",
                .{ type_name, condition },
            ));
            if (reached.inherits(method)) return unresolvedInvocation(try builder.print(
                "a type in the declared type `{s}`'s supertype chain declares a method of this name",
                .{type_name},
            ));
            for (reached.providers) |provider| try declareProvider(
                builder,
                provider,
                "walked the declared supertype chain of a receiver's declared type",
            );
        },
        .unknown => return unresolvedInvocation(try builder.print(
            "the receiver's declared type `{s}` carries no record of whether it declares supertypes, " ++
                "so a method of this name it may inherit is not ruled out",
            .{type_name},
        )),
    }

    var found: ?MethodCandidate = null;
    var count: u32 = 0;
    for (members.methods) |candidate| {
        work.candidate();
        if (!std.mem.eql(u8, candidate.name, method)) continue;
        if (count == 0) found = candidate;
        count += 1;
    }
    if (count == 0) return valueNoSuchMethod(builder, type_name);
    if (count > 1) return valueOverloaded(builder, type_name, count);

    const only = found.?;
    if (only.access != .public) return valueInaccessible(builder, type_name, method, only.access);
    return .{
        .external = only.target,
        .resolution = .{ .fact = .{ .method = value_call_method } },
    };
}

/// A value receiver names no scope, so none of these carries a qualifier.
///
/// The source wrote a variable, and this frontend read its declared type. The
/// type is not a name the source put in front of the method
/// ([ADR 010](../../docs/adr/010_designator_is_a_structured_name.md)), so the
/// designator stays the bare method name and the type is named in the words
/// instead.
fn valueNoSuchMethod(builder: *contract.BatchBuilder, type_name: []const u8) !InvocationTarget {
    return unresolvedInvocation(try builder.print(
        "no method of this name is declared by the receiver's declared type `{s}`",
        .{type_name},
    ));
}

fn valueOverloaded(
    builder: *contract.BatchBuilder,
    type_name: []const u8,
    count: u32,
) !InvocationTarget {
    return unresolvedInvocation(try builder.print(
        "{d} methods of this name are declared by the receiver's declared type `{s}`, " ++
            "and overloads are not resolved",
        .{ count, type_name },
    ));
}

fn valueInaccessible(
    builder: *contract.BatchBuilder,
    type_name: []const u8,
    method: []const u8,
    access: Access,
) !InvocationTarget {
    return unresolvedInvocation(try builder.print(
        "`{s}.{s}` is {s}, which is outside the access this frontend resolves through a value receiver",
        .{ type_name, method, access.label() },
    ));
}

pub const value_call_method = "invocation on a receiver whose declared type resolves to the one method " ++
    "of this name that type declares";

/// The static method a receiver naming a class of the analyzed unit selects.
///
/// Both ends are in one batch, so the modifiers are the ones this analysis just
/// read rather than labels from the graph, and the access subset is wider: a
/// class reaches its own private members, which is the one non-public case
/// [ADR 009](../../docs/adr/009_java_static_calls.md) admits.
fn localStaticTarget(
    builder: *contract.BatchBuilder,
    scope: CallScope,
    class_index: u32,
    receiver: []const u8,
    method: []const u8,
) !InvocationTarget {
    const class = classByIndex(scope.unit.classes, class_index);
    if (class.has_supertypes) return targetHasSupertypes(builder, receiver);

    var found: ?MethodInfo = null;
    var count: u32 = 0;
    for (scope.methods) |candidate| {
        work.candidate();
        if (!std.mem.eql(u8, candidate.class_name, class.name)) continue;
        if (!std.mem.eql(u8, candidate.name, method)) continue;
        if (count == 0) found = candidate;
        count += 1;
    }
    if (count == 0) return noSuchMethod(builder, receiver);
    if (count > 1) return overloaded(builder, receiver, count);

    const only = found.?;
    if (!only.is_static) return notStatic(builder, receiver, method);
    // The enclosing class reaches whatever it declares; another class in the
    // same unit is as far away as one in another unit.
    if (only.access != .public and class.index != scope.class.index) {
        return inaccessible(builder, receiver, method, only.access);
    }
    return .{
        .index = only.index,
        .resolution = .{ .fact = .{ .method = static_call_method } },
    };
}

/// The static method a receiver naming a class another unit declares selects,
/// read from the candidates the analyzer offered for that name.
fn externalStaticTarget(
    builder: *contract.BatchBuilder,
    scope: CallScope,
    receiver: []const u8,
    method: []const u8,
) !InvocationTarget {
    // Both branches below are guards against the projection and `resolveType`
    // disagreeing about what a name reaches. While they look a name up in the
    // same order — a single-type import, then the unit's own package — neither
    // is reachable, and `java_members` has a test that pins that order. They
    // stay because the order is two functions' agreement rather than one
    // function's rule, and an unreachable decline is the right answer if it
    // ever breaks.
    const members = scope.unit.context.memberLookup(receiver) orelse
        return classQualifiedDecline(receiver, try builder.print(
            "the receiver names class `{s}`, whose current shape this analysis did not read",
            .{receiver},
        ));
    switch (members.supertypes) {
        .none => {},
        .declared => return targetHasSupertypes(builder, receiver),
        .unknown => return classQualifiedDecline(receiver, try builder.print(
            "class `{s}` carries no record of whether it declares supertypes, " ++
                "so a method of this name it may inherit is not ruled out",
            .{receiver},
        )),
    }

    var found: ?MethodCandidate = null;
    var count: u32 = 0;
    for (members.methods) |candidate| {
        work.candidate();
        if (!std.mem.eql(u8, candidate.name, method)) continue;
        if (count == 0) found = candidate;
        count += 1;
    }
    if (count == 0) return noSuchMethod(builder, receiver);
    if (count > 1) return overloaded(builder, receiver, count);

    const only = found.?;
    switch (only.static) {
        .yes => {},
        .no => return notStatic(builder, receiver, method),
        .unknown => return staticUnrecorded(builder, receiver, method),
    }
    if (only.access != .public) return inaccessible(builder, receiver, method, only.access);
    return .{
        .external = only.target,
        .resolution = .{ .fact = .{ .method = static_call_method } },
    };
}

pub const unqualified_call_method = "unqualified invocation of the only method of this name in a class without supertypes";

pub const static_call_method = "class-qualified invocation of the one `static` method of this name " ++
    "declared in a class without supertypes";

fn targetHasSupertypes(builder: *contract.BatchBuilder, receiver: []const u8) !InvocationTarget {
    return classQualifiedDecline(receiver, try builder.print(
        "class `{s}` declares supertypes, so a method of this name it may inherit, " ++
            "or hide, could be the target",
        .{receiver},
    ));
}

fn noSuchMethod(builder: *contract.BatchBuilder, receiver: []const u8) !InvocationTarget {
    return classQualifiedDecline(receiver, try builder.print(
        "class `{s}` declares no method of this name",
        .{receiver},
    ));
}

fn overloaded(builder: *contract.BatchBuilder, receiver: []const u8, count: u32) !InvocationTarget {
    return classQualifiedDecline(receiver, try builder.print(
        "class `{s}` declares {d} methods of this name, and overloads are not resolved",
        .{ receiver, count },
    ));
}

fn notStatic(
    builder: *contract.BatchBuilder,
    receiver: []const u8,
    method: []const u8,
) !InvocationTarget {
    return classQualifiedDecline(receiver, try builder.print(
        "`{s}.{s}` is not static, so naming it through the class is not a call Java compiles",
        .{ receiver, method },
    ));
}

/// The modifier is not recorded, which is not the same answer as `static` being
/// absent from the declaration. Saying the second when the graph only knows the
/// first would assert something about the source it never read.
fn staticUnrecorded(
    builder: *contract.BatchBuilder,
    receiver: []const u8,
    method: []const u8,
) !InvocationTarget {
    return classQualifiedDecline(receiver, try builder.print(
        "`{s}.{s}` carries no record of whether it is `static`, so a call through the class name is not established",
        .{ receiver, method },
    ));
}

fn inaccessible(
    builder: *contract.BatchBuilder,
    receiver: []const u8,
    method: []const u8,
    access: Access,
) !InvocationTarget {
    return classQualifiedDecline(receiver, try builder.print(
        "`{s}.{s}` is {s}, which is outside the access this frontend resolves across classes",
        .{ receiver, method, access.label() },
    ));
}

/// What binds `name` where the invocation is written, or null when nothing
/// does.
///
/// The method's own bindings are collected on demand, once: a method with no
/// simple-name receiver never pays for the walk, and one with ten receivers
/// pays for it once rather than ten times.
///
/// An uncovered introducer wins over everything. It is a poison, not a
/// candidate: a name any construct outside the covered list binds anywhere in
/// the method is not read as a value of a known type, whichever declaration is
/// lexically nearer. Among covered bindings the innermost wins — a local over a
/// parameter over a field — which is the order Java shadows them in.
fn boundName(
    gpa: std.mem.Allocator,
    source: []const u8,
    scope: CallScope,
    name: []const u8,
) !?BoundName {
    const bindings = scope.bindings;
    if (!bindings.collected) {
        bindings.collected = true;
        try bindings.method.appendSlice(gpa, scope.class.fields);
        try collectMethodBindings(gpa, &bindings.method, scope.method.node, source, 0, false);
    }

    var found: ?BoundName = null;
    for (bindings.method.items) |bound| {
        if (!std.mem.eql(u8, bound.name, name)) continue;
        if (bound.why != .covered) return bound;
        found = bound;
    }
    for (bindings.locals.items) |bound| {
        if (!std.mem.eql(u8, bound.name, name)) continue;
        if (bound.why != .covered) return bound;
        found = bound;
    }
    return found;
}

/// Every name this method binds whose scope reaches past the construct that
/// binds it, so this frontend reads it as bound for the whole method.
///
/// Local variables are deliberately absent: `emitInvocations` binds them where
/// Java does, from their declarator to the end of their block.
fn collectMethodBindings(
    gpa: std.mem.Allocator,
    into: *std.ArrayList(BoundName),
    node: ts.Node,
    source: []const u8,
    depth: u32,
    escaped: bool,
) !void {
    if (depth >= max_depth) return;

    const kind = node.kind();
    if (std.mem.eql(u8, kind, "formal_parameter") and !escaped) {
        // The one covered introducer here. A parameter carrying its own
        // dimensions declares an array whatever its type node reads.
        if (node.childByFieldName("name")) |name| {
            const arrayed = node.childByFieldName("dimensions") != null;
            const declared = if (arrayed) null else simpleTypeNameOf(node, source);
            try into.append(gpa, if (declared) |type_node| .{
                .name = name.text(source),
                .type_name = type_node.text(source),
                .type_node = type_node,
                .why = .covered,
            } else .{
                .name = name.text(source),
                .why = .uncovered_type,
            });
        }
    } else if (std.mem.eql(u8, kind, "formal_parameter") or
        std.mem.eql(u8, kind, "catch_formal_parameter") or
        std.mem.eql(u8, kind, "enhanced_for_statement") or
        std.mem.eql(u8, kind, "resource") or
        // A type pattern, which this grammar writes as a name on the
        // `instanceof` itself rather than as a node of its own.
        std.mem.eql(u8, kind, "instanceof_expression"))
    {
        if (node.childByFieldName("name")) |name| {
            try appendUncoveredBinding(gpa, into, name.text(source));
        }
    } else if (std.mem.eql(u8, kind, "spread_parameter")) {
        var children = node.namedChildren();
        while (children.next()) |child| {
            if (!std.mem.eql(u8, child.kind(), "variable_declarator")) continue;
            const name = child.childByFieldName("name") orelse continue;
            try appendUncoveredBinding(gpa, into, name.text(source));
        }
    } else if (std.mem.eql(u8, kind, "type_pattern") or
        std.mem.eql(u8, kind, "record_pattern_component"))
    {
        // The type is written first and the bound name last, and a component
        // that binds nothing, such as `_`, has no identifier at all.
        if (lastIdentifier(node)) |name| try appendUncoveredBinding(gpa, into, name.text(source));
    } else if (std.mem.eql(u8, kind, "lambda_expression")) {
        // A single inferred parameter is written as the name itself; the other
        // two spellings are nodes this walk reaches on its own.
        if (node.childByFieldName("parameters")) |parameters| {
            if (std.mem.eql(u8, parameters.kind(), "identifier")) {
                try appendUncoveredBinding(gpa, into, parameters.text(source));
            }
        }
    } else if (std.mem.eql(u8, kind, "inferred_parameters")) {
        var names = node.namedChildren();
        while (names.next()) |child| {
            if (std.mem.eql(u8, child.kind(), "identifier")) {
                try appendUncoveredBinding(gpa, into, child.text(source));
            }
        }
    }

    // A lambda's parameters and a nested type body's members bind names inside
    // their own subtree, and this frontend reads bindings for the whole method.
    // Recording one of them as covered would let it give a type to a name
    // written outside it, which is a wrong fact rather than a decline — so past
    // this point every binding is a poison.
    const inner = escaped or std.mem.eql(u8, kind, "lambda_expression") or isTypeBody(kind);
    var children = node.namedChildren();
    while (children.next()) |child| try collectMethodBindings(gpa, into, child, source, depth + 1, inner);
}

fn bindsName(bindings: []const BoundName, name: []const u8) bool {
    for (bindings) |bound| {
        if (std.mem.eql(u8, bound.name, name)) return true;
    }
    return false;
}

/// The names a declaration binds through its declarators. A field, a local
/// variable, and a `...` parameter all write them the same way.
fn appendDeclaredNames(
    gpa: std.mem.Allocator,
    into: *std.ArrayList([]const u8),
    declaration: ts.Node,
    source: []const u8,
) !void {
    var children = declaration.namedChildren();
    while (children.next()) |child| {
        if (!std.mem.eql(u8, child.kind(), "variable_declarator")) continue;
        const name = child.childByFieldName("name") orelse continue;
        try into.append(gpa, name.text(source));
    }
}

/// The simple type name a declaration writes, or empty when it writes anything
/// else.
///
/// Generic, array, qualified, and primitive types are deliberately empty:
/// [Follow-up 014](../../docs/followups/014_java_instance_receiver_calls.md)
/// prices admitting them separately, and a name this frontend cannot resolve as
/// a simple name is not one it may guess at. `var` reaches here as a
/// `type_identifier` because this grammar has no node for it, and is excluded
/// by name: it is an inferred type, not a type called `var`.
fn simpleTypeNameOf(declaration: ts.Node, source: []const u8) ?ts.Node {
    const type_node = declaration.childByFieldName("type") orelse return null;
    if (!std.mem.eql(u8, type_node.kind(), "type_identifier")) return null;
    if (std.mem.eql(u8, type_node.text(source), "var")) return null;
    return type_node;
}

/// The names a declarator list binds, each with the type its declaration
/// writes. A declarator carrying its own dimensions — `String x[]` — declares
/// an array however the type node reads, so it records no type.
fn appendDeclaredBindings(
    gpa: std.mem.Allocator,
    into: *std.ArrayList(BoundName),
    declaration: ts.Node,
    source: []const u8,
) !void {
    const declared = simpleTypeNameOf(declaration, source);
    var children = declaration.namedChildren();
    while (children.next()) |child| {
        if (!std.mem.eql(u8, child.kind(), "variable_declarator")) continue;
        const name = child.childByFieldName("name") orelse continue;
        const arrayed = child.childByFieldName("dimensions") != null;
        const covered = if (arrayed) null else declared;
        try into.append(gpa, if (covered) |node| .{
            .name = name.text(source),
            .type_name = node.text(source),
            .type_node = node,
            .why = .covered,
        } else .{
            .name = name.text(source),
            .why = .uncovered_type,
        });
    }
}

fn appendUncoveredBinding(
    gpa: std.mem.Allocator,
    into: *std.ArrayList(BoundName),
    name: []const u8,
) !void {
    try into.append(gpa, .{ .name = name, .why = .uncovered_introducer });
}

fn lastIdentifier(node: ts.Node) ?ts.Node {
    var found: ?ts.Node = null;
    var children = node.namedChildren();
    while (children.next()) |child| {
        if (std.mem.eql(u8, child.kind(), "identifier")) found = child;
    }
    return found;
}

fn unresolvedInvocation(explanation: []const u8) InvocationTarget {
    return .{
        .resolution = .{ .unresolved = .{ .missing = .target_entity, .explanation = explanation } },
    };
}

/// A decline whose receiver this frontend did establish as a class.
///
/// Only these carry a qualifier. Every other decline either read the receiver
/// as a value or never read it as anything, and a name this frontend could not
/// place is not a scope it may claim the source named.
fn classQualifiedDecline(class: []const u8, explanation: []const u8) InvocationTarget {
    var target = unresolvedInvocation(explanation);
    target.qualifier = class;
    return target;
}

fn findClass(classes: []const ClassInfo, name: []const u8) ?u32 {
    for (classes) |class| {
        if (std.mem.eql(u8, class.name, name)) return class.index;
    }
    return null;
}

const testing = std.testing;

test "a source root is what remains once the declared package and file name are stripped" {
    try testing.expectEqualStrings("a/b/src/main/java", sourceRoot(
        "a/b/src/main/java/org/apache/dubbo/rpc/RpcContext.java",
        "org.apache.dubbo.rpc",
    ).?);
    try testing.expectEqualStrings("", sourceRoot("demo/Greeter.java", "demo").?);
    try testing.expectEqualStrings("one", sourceRoot("one/demo/Greeter.java", "demo").?);
}

test "a path that does not spell its declared package has no source root" {
    // The directory is not the package at all.
    try testing.expect(sourceRoot("one/Helper.java", "demo") == null);
    // A segment only ends with the package segment; `mydemo` is not `demo`.
    try testing.expect(sourceRoot("src/mydemo/Helper.java", "demo") == null);
    // The path is shorter than the package it claims.
    try testing.expect(sourceRoot("sub/Deep.java", "demo.sub") == null);
    // No package at all.
    try testing.expect(sourceRoot("Loose.java", "") == null);
}

test "one source root is one scope, and a test root reads its own main root" {
    const main_root = "dubbo-common/src/main/java";
    const test_root = "dubbo-common/src/test/java";
    const other_main = "dubbo-cluster/src/main/java";

    try testing.expect(sharesScope(main_root, main_root));
    try testing.expect(sharesScope(test_root, main_root));

    // Never the other way round: main sources compile without test sources.
    try testing.expect(!sharesScope(main_root, test_root));
    // Never into another module, in either direction.
    try testing.expect(!sharesScope(main_root, other_main));
    try testing.expect(!sharesScope(test_root, other_main));
    try testing.expect(!sharesScope(test_root, "dubbo-cluster/src/test/java"));
    // The language directory must match too.
    try testing.expect(!sharesScope(test_root, "dubbo-common/src/main/kotlin"));
    // A repository whose roots are the layout itself.
    try testing.expect(sharesScope("src/test/java", "src/main/java"));
    // Two unrelated roots that share a package see nothing of each other.
    try testing.expect(!sharesScope("moduleA/src/main/java", "moduleB/src/main/java"));
}
