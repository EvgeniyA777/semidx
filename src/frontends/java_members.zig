//! Java class shape: the methods a top-level class currently declares, and the
//! modifiers a static call must check before it can name one.
//!
//! This is a projection for the analyzer, exactly as `java_packages` is. It
//! creates no entity, no signature kind, and no inheritance relationship, and it
//! decides nothing: it hands the Java frontend candidates to check under
//! [ADR 009](../../docs/adr/009_java_static_calls.md), re-read from the graph on
//! every call.
//!
//! What it reads is what the frontend wrote. A unit is analyzed from its own
//! source, so another class's modifiers reach it only as the extension labels
//! that class's own analysis recorded — never by re-parsing the provider, which
//! would make every lookup a parse and put a second reader of Java syntax in the
//! pipeline.
//!
//! The one thing kept between calls is a hint: which units have read which
//! `Class.method` pair. It exists so that a provider edit reaches the callers it
//! can change without reanalyzing a package, and it is a superset — a hinted
//! unit that no longer mentions the pair is reanalyzed for nothing, which costs
//! a pass and changes no claim.

const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("semidx_core");
const java = @import("java.zig");

const model = core.model;
const Graph = core.Graph;

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
        if (std.mem.eql(u8, value, java.method_access.public)) return .public;
        if (std.mem.eql(u8, value, java.method_access.protected)) return .protected;
        if (std.mem.eql(u8, value, java.method_access.package_private)) return .package_private;
        if (std.mem.eql(u8, value, java.method_access.private)) return .private;
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
        if (std.mem.eql(u8, value, java.class_shape.none)) return .none;
        if (std.mem.eql(u8, value, java.class_shape.declared)) return .declared;
        return .unknown;
    }
};

/// One method a class currently declares. Strings are borrowed from the graph.
pub const Method = struct {
    name: []const u8,
    entity: model.EntityId,
    access: Access,
    is_static: bool,
};

/// What a class currently is, for a reader deciding a static call.
pub const ClassShape = struct {
    name: []const u8,
    entity: model.EntityId,
    unit: model.SourceUnitId,
    package: []const u8,
    supertypes: Supertypes,
};

fn isJavaFact(graph: *Graph, id: model.EntityId) bool {
    const fact = graph.currentDefinitionFact(id) orelse return false;
    return std.mem.eql(u8, fact.producer.name, java.capabilities.producer.name);
}

fn isTopLevelClass(entity: model.Entity) bool {
    return entity.kind == .definition and
        entity.identity.language == .java and
        std.mem.eql(u8, entity.identity.role, "class") and
        entity.identity.container_path.len == 0 and
        entity.identity.name != null;
}

fn isMethodOf(entity: model.Entity, class_name: []const u8) bool {
    if (entity.kind != .definition or entity.identity.language != .java) return false;
    if (!std.mem.eql(u8, entity.identity.role, "method")) return false;
    if (entity.identity.container_path.len != 1) return false;
    if (entity.identity.name == null) return false;
    return std.mem.eql(u8, entity.identity.container_path[0], class_name);
}

/// The class `id` names, when it is a current top-level Java class fact.
///
/// A stale or failed unit yields nothing: what it once declared is not a current
/// fact, and a call must not resolve against a class the working copy may no
/// longer contain.
pub fn classShapeOf(graph: *Graph, id: model.EntityId) ?ClassShape {
    const entity = graph.entity(id) orelse return null;
    if (!entity.isLive() or !isTopLevelClass(entity)) return null;
    if (!isJavaFact(graph, id)) return null;
    const evidence = entity.evidence orelse return null;
    const record = graph.unit(evidence.unit) orelse return null;
    if (!record.isLive()) return null;
    return .{
        .name = entity.identity.name.?,
        .entity = id,
        .unit = evidence.unit,
        .package = entity.extension.get("java.package") orelse "",
        .supertypes = if (entity.extension.get(java.class_shape.key)) |value|
            Supertypes.fromLabel(value)
        else
            .unknown,
    };
}

/// The methods `class` currently declares, in declaration order.
///
/// Overloads are returned as what they are — more than one entry of one name —
/// because selecting between them needs argument types this frontend does not
/// have, and a projection that silently returned the first would be deciding.
pub fn methodsOf(
    graph: *Graph,
    class: ClassShape,
    gpa: Allocator,
    out: *std.ArrayList(Method),
) Allocator.Error!void {
    var definitions: std.ArrayList(model.EntityId) = .empty;
    defer definitions.deinit(gpa);
    try graph.definitionsInUnit(class.unit, &definitions, gpa);

    for (definitions.items) |id| {
        const entity = graph.entity(id).?;
        if (!entity.isLive() or !isMethodOf(entity, class.name)) continue;
        if (!isJavaFact(graph, id)) continue;
        try out.append(gpa, .{
            .name = entity.identity.name.?,
            .entity = id,
            .access = if (entity.extension.get(java.method_access.key)) |value|
                Access.fromLabel(value)
            else
                .unknown,
            .is_static = if (entity.extension.get(java.method_static.key)) |value|
                std.mem.eql(u8, value, java.method_static.yes)
            else
                false,
        });
    }
}

/// What one method name means in one class right now.
pub const Selection = union(enum) {
    /// No method of that name is declared there.
    missing,
    /// More than one, counted. Which one a call means needs argument types.
    overloaded: u32,
    /// Exactly one, with the modifiers a static call must check.
    unique: Method,
};

pub fn select(methods: []const Method, name: []const u8) Selection {
    var found: ?Method = null;
    var count: u32 = 0;
    for (methods) |method| {
        if (!std.mem.eql(u8, method.name, name)) continue;
        if (count == 0) found = method;
        count += 1;
    }
    if (count == 0) return .missing;
    if (count > 1) return .{ .overloaded = count };
    return .{ .unique = found.? };
}

/// One thing a unit exposes that a static call's answer can depend on.
///
/// Two granularities, and they are not the same question. A method aspect
/// changes when that one name's selection changes in that class. A class aspect
/// — `method` empty — changes when the class appears, disappears, or starts or
/// stops declaring supertypes, which can change the answer for *every* method
/// name in it. Keeping them apart is what makes a one-method edit cost the
/// readers of that method rather than the readers of the class.
pub const Aspect = struct {
    class: []const u8,
    /// Empty for the class-level aspect.
    method: []const u8,
    /// How many methods of `method` the class declares. Zero for a class aspect.
    count: u32,
    access: Access,
    is_static: bool,
    supertypes: Supertypes,

    /// Whether two aspects speak about the same thing.
    pub fn sameKey(a: Aspect, b: Aspect) bool {
        return std.mem.eql(u8, a.class, b.class) and std.mem.eql(u8, a.method, b.method);
    }

    /// Whether they also say the same thing about it.
    pub fn eql(a: Aspect, b: Aspect) bool {
        return a.sameKey(b) and
            a.count == b.count and
            a.access == b.access and
            a.is_static == b.is_static and
            a.supertypes == b.supertypes;
    }
};

/// Everything `unit` currently exposes to a static-call reader.
///
/// Cost is the unit's own classes and methods, which is what an edit to it
/// already costs to analyze. A unit that is stale, failed, or not Java exposes
/// nothing, and the difference against what it exposed before is then every
/// aspect it had — which is correct: a reader of any of them may have to change
/// its answer.
pub fn aspectsOf(
    graph: *Graph,
    unit: model.SourceUnitId,
    gpa: Allocator,
    out: *std.ArrayList(Aspect),
) Allocator.Error!void {
    const record = graph.unit(unit) orelse return;
    if (!record.isLive() or record.language != .java) return;

    var definitions: std.ArrayList(model.EntityId) = .empty;
    defer definitions.deinit(gpa);
    try graph.definitionsInUnit(unit, &definitions, gpa);

    var methods: std.ArrayList(Method) = .empty;
    defer methods.deinit(gpa);

    for (definitions.items) |id| {
        const class = classShapeOf(graph, id) orelse continue;
        if (class.unit != unit) continue;

        try out.append(gpa, .{
            .class = class.name,
            .method = "",
            .count = 0,
            .access = .unknown,
            .is_static = false,
            .supertypes = class.supertypes,
        });

        methods.clearRetainingCapacity();
        try methodsOf(graph, class, gpa, &methods);
        for (methods.items) |method| {
            // One aspect per distinct name, holding that name's whole selection.
            var seen = false;
            for (out.items) |existing| {
                if (std.mem.eql(u8, existing.class, class.name) and
                    std.mem.eql(u8, existing.method, method.name))
                {
                    seen = true;
                    break;
                }
            }
            if (seen) continue;
            const selection = select(methods.items, method.name);
            try out.append(gpa, switch (selection) {
                .missing => unreachable, // the name came from this list
                .overloaded => |count| .{
                    .class = class.name,
                    .method = method.name,
                    .count = count,
                    .access = .unknown,
                    .is_static = false,
                    .supertypes = class.supertypes,
                },
                .unique => |only| .{
                    .class = class.name,
                    .method = only.name,
                    .count = 1,
                    .access = only.access,
                    .is_static = only.is_static,
                    .supertypes = class.supertypes,
                },
            });
        }
    }
}

/// Which units have read which `Class.method` pair.
///
/// A unit whose call is unresolved has no dependency to propagate along — it
/// read nothing — so nothing else can reach it when the method it asked about
/// finally appears. That is what this is for, and it is why the key is the pair
/// as written rather than a resolved provider: the reader could not resolve one.
pub const Members = struct {
    gpa: Allocator,
    /// Owns the keys.
    names: std.heap.ArenaAllocator,
    /// Readers of one `Class.method` pair, keyed by "class\\x00method".
    pairs: std.StringHashMapUnmanaged(std.ArrayList(model.SourceUnitId)),
    /// Readers of any method of a class, keyed by the class name. A class-level
    /// change reaches all of them.
    classes: std.StringHashMapUnmanaged(std.ArrayList(model.SourceUnitId)),

    pub fn init(gpa: Allocator) Members {
        return .{
            .gpa = gpa,
            .names = std.heap.ArenaAllocator.init(gpa),
            .pairs = .empty,
            .classes = .empty,
        };
    }

    pub fn deinit(self: *Members) void {
        var pairs = self.pairs.valueIterator();
        while (pairs.next()) |list| list.deinit(self.gpa);
        self.pairs.deinit(self.gpa);
        var classes = self.classes.valueIterator();
        while (classes.next()) |list| list.deinit(self.gpa);
        self.classes.deinit(self.gpa);
        self.names.deinit();
        self.* = undefined;
    }

    fn add(
        self: *Members,
        table: *std.StringHashMapUnmanaged(std.ArrayList(model.SourceUnitId)),
        key: []const u8,
        unit: model.SourceUnitId,
    ) Allocator.Error!void {
        const slot = try table.getOrPut(self.gpa, key);
        if (!slot.found_existing) {
            slot.key_ptr.* = try self.names.allocator().dupe(u8, key);
            slot.value_ptr.* = .empty;
        }
        if (std.mem.indexOfScalar(model.SourceUnitId, slot.value_ptr.items, unit) == null) {
            try slot.value_ptr.append(self.gpa, unit);
        }
    }

    /// Remembers that `unit` asked what `class.method` means, whatever answer it
    /// got. Both granularities are recorded, because a class-level change can
    /// change the answer for a pair the class does not even declare.
    pub fn noteReader(
        self: *Members,
        unit: model.SourceUnitId,
        class: []const u8,
        method: []const u8,
    ) Allocator.Error!void {
        if (class.len == 0 or method.len == 0) return;
        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(self.gpa);
        try buffer.appendSlice(self.gpa, class);
        try buffer.append(self.gpa, 0);
        try buffer.appendSlice(self.gpa, method);
        try self.add(&self.pairs, buffer.items, unit);
        try self.add(&self.classes, class, unit);
    }

    /// Units that may read `class.method`. Read each one back before relying on
    /// it; this is a hint, not an answer.
    pub fn readersOf(
        self: *const Members,
        class: []const u8,
        method: []const u8,
        gpa: Allocator,
    ) Allocator.Error![]const model.SourceUnitId {
        if (method.len == 0) {
            const list = self.classes.getPtr(class) orelse return &.{};
            return list.items;
        }
        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(gpa);
        try buffer.appendSlice(gpa, class);
        try buffer.append(gpa, 0);
        try buffer.appendSlice(gpa, method);
        const list = self.pairs.getPtr(buffer.items) orelse return &.{};
        return list.items;
    }
};
