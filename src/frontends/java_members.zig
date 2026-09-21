//! Java class shape: the methods a top-level class or interface currently
//! declares, and the modifiers a static call must check before it can name one.
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

/// The Java frontend owns this vocabulary: it writes the labels these read, and
/// it is the one that decides what each value permits. The projection only
/// carries them back.
pub const Access = java.Access;
pub const Supertypes = java.Supertypes;
pub const Static = java.Static;

/// One method a class currently declares. Strings are borrowed from the graph.
pub const Method = struct {
    name: []const u8,
    entity: model.EntityId,
    access: Access,
    static: Static,
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

/// A top-level class or interface. Both declare methods a call may select, and
/// ADR 009's conditions decide between them without needing to know which it
/// was ([ADR 011](../../docs/adr/011_java_hierarchy_from_indexed_source.md)):
/// an interface method is `static` only when it says so, and an interface with
/// no `extends` declares no supertypes exactly as a class with no `extends`
/// does.
fn isTopLevelType(entity: model.Entity) bool {
    return entity.kind == .definition and
        entity.identity.language == .java and
        java.isTypeRole(entity.identity.role) and
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

/// The type `id` names, when it is a current top-level Java class or interface
/// fact.
///
/// A stale or failed unit yields nothing: what it once declared is not a current
/// fact, and a call must not resolve against a type the working copy may no
/// longer contain.
pub fn classShapeOf(graph: *Graph, id: model.EntityId) ?ClassShape {
    const entity = graph.entity(id) orelse return null;
    if (!entity.isLive() or !isTopLevelType(entity)) return null;
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
            .static = if (entity.extension.get(java.method_static.key)) |value|
                Static.fromLabel(value)
            else
                .unknown,
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

/// What the classes a unit's receivers name currently declare, for the pairs it
/// writes.
///
/// The receivers are the question, so they bound the answer: a name is looked up
/// in the order the frontend would look it up — a single-type import before the
/// unit's own package — and only the methods of the invoked names are carried,
/// overloads included. Nothing here decides anything; a class that resolves to
/// candidates still has to pass every ADR 009 condition inside the frontend.
///
/// A name that reaches no unique class gets no entry: the frontend resolves it
/// against the unit's own classes, or declines with `resolveType`'s reason.
pub fn membersFor(
    graph: *Graph,
    context: java.Context,
    receivers: []const java.Receiver,
    allocator: Allocator,
) Allocator.Error![]const java.ClassMembers {
    var found: std.ArrayList(java.ClassMembers) = .empty;
    var methods: std.ArrayList(Method) = .empty;
    defer methods.deinit(allocator);
    var carried: std.ArrayList(java.MethodCandidate) = .empty;
    defer carried.deinit(allocator);

    var at: usize = 0;
    while (at < receivers.len) : (at += 1) {
        const class_name = receivers[at].class;
        // One pass per class, however many of its methods the unit invokes.
        if (indexOfClass(found.items, class_name) != null) continue;

        const binding = context.importLookup(class_name) orelse
            context.lookup(context.package, class_name) orelse continue;
        const class_target = switch (binding) {
            .unique => |target| target,
            .ambiguous, .out_of_scope => continue,
        };

        const class = classShapeOf(graph, class_target.entity) orelse {
            // The binding named a class the graph no longer answers for. The
            // frontend is told that rather than told it has no methods.
            try found.append(allocator, .{
                .name = class_name,
                .supertypes = .unknown,
                .methods = &.{},
            });
            continue;
        };

        methods.clearRetainingCapacity();
        try methodsOf(graph, class, allocator, &methods);

        carried.clearRetainingCapacity();
        for (methods.items) |method| {
            if (!invokedHere(receivers, class_name, method.name)) continue;
            try carried.append(allocator, .{
                .name = method.name,
                .target = .{ .entity = method.entity, .provider = class.unit },
                .access = method.access,
                .static = method.static,
            });
        }
        try found.append(allocator, .{
            .name = class_name,
            .supertypes = class.supertypes,
            .methods = try allocator.dupe(java.MethodCandidate, carried.items),
        });
    }
    return found.items;
}

fn indexOfClass(entries: []const java.ClassMembers, name: []const u8) ?usize {
    for (entries, 0..) |entry, at| {
        if (std.mem.eql(u8, entry.name, name)) return at;
    }
    return null;
}

/// Whether the unit writes `class.method(...)` anywhere, which is what decides
/// that the method belongs in the candidate table at all.
fn invokedHere(receivers: []const java.Receiver, class: []const u8, method: []const u8) bool {
    for (receivers) |receiver| {
        if (std.mem.eql(u8, receiver.class, class) and
            std.mem.eql(u8, receiver.method, method)) return true;
    }
    return false;
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
    static: Static,
    supertypes: Supertypes,
    /// The class-level aspect only, from the type's own labels: which
    /// supertypes it declares, which member types, and which fields. A reader
    /// that walked a chain can change its answer when any of them changes, and
    /// `supertypes` being a boolean cannot report that a type now extends
    /// something else (ADR 011 D7).
    supertype_names: []const u8 = "",
    member_types: []const u8 = "",
    field_names: []const u8 = "",
    /// Whether the chain above this type is closed, and if not why, in the
    /// hierarchy projection's own words. Filled by `java_hierarchy`, because
    /// the answer is a walk over claims rather than a label.
    ///
    /// It is here because nothing else can report it: a type whose own
    /// supertype appears elsewhere in the repository changes no byte and no
    /// label of its own, and every reader that walked through it has to hear
    /// about it.
    chain: []const u8 = "",
    /// Which entity the class-level aspect speaks about, so the chain can be
    /// walked for it. Never compared: an entity keeps its id across an edit,
    /// and a new class is already a new key.
    entity: ?model.EntityId = null,

    /// Whether two aspects speak about the same thing.
    pub fn sameKey(a: Aspect, b: Aspect) bool {
        return std.mem.eql(u8, a.class, b.class) and std.mem.eql(u8, a.method, b.method);
    }

    /// Whether they also say the same thing about it.
    pub fn eql(a: Aspect, b: Aspect) bool {
        return a.sameKey(b) and
            a.count == b.count and
            a.access == b.access and
            a.static == b.static and
            a.supertypes == b.supertypes and
            std.mem.eql(u8, a.supertype_names, b.supertype_names) and
            std.mem.eql(u8, a.member_types, b.member_types) and
            std.mem.eql(u8, a.field_names, b.field_names) and
            std.mem.eql(u8, a.chain, b.chain);
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

        const entity = graph.entity(id).?;
        try out.append(gpa, .{
            .class = class.name,
            .method = "",
            .count = 0,
            .access = .unknown,
            .static = .unknown,
            .supertypes = class.supertypes,
            .supertype_names = entity.extension.get(java.supertype_names.key) orelse "",
            .member_types = entity.extension.get(java.member_types.key) orelse "",
            .field_names = entity.extension.get(java.field_names.key) orelse "",
            .entity = id,
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
                    .static = .unknown,
                    .supertypes = class.supertypes,
                },
                .unique => |only| .{
                    .class = class.name,
                    .method = only.name,
                    .count = 1,
                    .access = only.access,
                    .static = only.static,
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

    /// Remembers that `unit` read the class-level shape of `class` — which is
    /// what walking a supertype chain does. It is the same channel
    /// `noteReader` feeds, at the granularity a chain change moves.
    pub fn noteTypeReader(
        self: *Members,
        unit: model.SourceUnitId,
        class: []const u8,
    ) Allocator.Error!void {
        if (class.len == 0) return;
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
