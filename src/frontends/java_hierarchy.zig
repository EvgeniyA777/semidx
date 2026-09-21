//! Java type hierarchy: what a top-level class or interface currently extends
//! and implements, read from the claims its own analysis recorded.
//!
//! This is a projection for the analyzer, exactly as `java_packages` and
//! `java_members` are. It creates no entity, no inheritance kind, and no
//! relationship, it resolves no name, and it decides nothing about a Java
//! program: it walks claims that already exist and reports either the types it
//! reached or the first condition that stopped it, re-read from the graph on
//! every call.
//!
//! Its whole purpose is to let a caller **rule out** — to establish that no type
//! reachable from here declares a name. It never selects an inherited member,
//! and it never names a target
//! ([ADR 011](../../docs/adr/011_java_hierarchy_from_indexed_source.md), D4-D6).
//!
//! A declared supertype is an ordinary `references` claim. It is told apart from
//! a field's type — which is also a `references` claim out of the same entity —
//! by the prefix the Java frontend writes in front of its own resolution words,
//! `java.supertype_claim.prefix`. A relationship carries no extension payload,
//! so that prefix is the only place a claim can say which position it was read
//! in, and both ends name the one constant.

const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("semidx_core");
const java = @import("java.zig");
const java_members = @import("java_members.zig");

const model = core.model;
const Graph = core.Graph;

/// The hard depth cap of a walk (ADR 011 D5). Reaching it is a decline with its
/// own reason, never a longer walk and never a hang.
pub const max_depth: u32 = 16;

/// Why a hierarchy is not closed in indexed source.
///
/// Each value is a distinct condition a caller may have to explain to a user,
/// so they stay apart rather than collapsing into "not closed".
pub const OpenReason = enum {
    /// A declared supertype's name resolved to nothing. The claim itself says
    /// why, in `resolveType`'s own words behind the supertype prefix.
    supertype_unresolved,
    /// A declared supertype resolved to something that is not a live top-level
    /// Java class or interface.
    supertype_not_a_type,
    /// It resolved to one, but the unit that declares it is not currently
    /// analyzed, so what it declares is not a current fact.
    supertype_provider_stale,
    /// The declared hierarchy contains a cycle. Legal syntax, illegal program;
    /// the answer is unresolved rather than a fact and rather than a hang.
    cycle,
    /// The walk reached `max_depth`.
    depth_cap,

    pub fn tag(self: OpenReason) []const u8 {
        return @tagName(self);
    }
};

pub const Closure = union(enum) {
    /// Every type reachable from the start, the start itself first, each once.
    closed,
    open: OpenReason,

    pub fn isClosed(self: Closure) bool {
        return self == .closed;
    }
};

/// The types `id` directly extends or implements, appended to `out`.
///
/// Returns null when every declared supertype of `id` is a current fact naming
/// a current top-level class or interface, and the first failing condition
/// otherwise. A type that declares no supertype succeeds with nothing appended,
/// which is what closes a chain.
pub fn directSupertypes(
    graph: *Graph,
    id: model.EntityId,
    gpa: Allocator,
    out: *std.ArrayList(model.EntityId),
) Allocator.Error!?OpenReason {
    var claims: std.ArrayList(model.Assertion) = .empty;
    defer claims.deinit(gpa);
    try graph.currentRelationshipsFrom(id, &claims, gpa);

    for (claims.items) |claim| {
        const relationship = claim.claim.relationship;
        if (relationship.kind != .references) continue;
        const words = switch (claim.resolution) {
            .fact => |established| established.method,
            .unresolved => |declined| declined.explanation,
            .approximate => |guess| guess.basis,
        };
        if (!java.supertype_claim.marks(words)) continue;

        const target = switch (relationship.target) {
            .entity => |entity| entity,
            // A designator is a name that resolved to nothing. The claim keeps
            // its own explanation; the chain is open.
            .designator => return .supertype_unresolved,
        };
        if (!claim.resolution.isFact()) return .supertype_unresolved;

        const found = graph.entity(target) orelse return .supertype_not_a_type;
        if (!found.isLive()) return .supertype_not_a_type;
        if (found.kind != .definition or
            found.identity.language != .java or
            !java.isTypeRole(found.identity.role) or
            found.identity.container_path.len != 0) return .supertype_not_a_type;

        // A type whose unit is no longer current declares nothing this walk may
        // rely on, and that is a different answer from not being a type at all.
        if (java_members.classShapeOf(graph, target) == null) return .supertype_provider_stale;

        if (std.mem.indexOfScalar(model.EntityId, out.items, target) == null) {
            try out.append(gpa, target);
        }
    }
    return null;
}

/// Every type reachable from `id` through declared supertypes, `id` first.
///
/// `out` holds what the walk visited whatever the verdict, so a caller that has
/// to declare a dependency on everything it read can do so even when the chain
/// turned out to be open (ADR 011 D7).
pub fn closureOf(
    graph: *Graph,
    id: model.EntityId,
    gpa: Allocator,
    out: *std.ArrayList(model.EntityId),
) Allocator.Error!Closure {
    var path: std.ArrayList(model.EntityId) = .empty;
    defer path.deinit(gpa);
    var direct: std.ArrayList(model.EntityId) = .empty;
    defer direct.deinit(gpa);
    return descend(graph, id, gpa, out, &path, &direct, 0);
}

fn descend(
    graph: *Graph,
    at: model.EntityId,
    gpa: Allocator,
    out: *std.ArrayList(model.EntityId),
    path: *std.ArrayList(model.EntityId),
    scratch: *std.ArrayList(model.EntityId),
    depth: u32,
) Allocator.Error!Closure {
    if (depth >= max_depth) return .{ .open = .depth_cap };
    if (std.mem.indexOfScalar(model.EntityId, path.items, at) != null) return .{ .open = .cycle };
    if (std.mem.indexOfScalar(model.EntityId, out.items, at) == null) try out.append(gpa, at);

    const mark = scratch.items.len;
    defer scratch.shrinkRetainingCapacity(mark);
    if (try directSupertypes(graph, at, gpa, scratch)) |reason| return .{ .open = reason };

    try path.append(gpa, at);
    defer _ = path.pop();

    // The slice is taken once: `scratch` is shared with deeper frames, which
    // append past `mark` and truncate back to it, so the parent's own entries
    // never move.
    var index = mark;
    while (index < scratch.items.len) : (index += 1) {
        const next = scratch.items[index];
        const outcome = try descend(graph, next, gpa, out, path, scratch, depth + 1);
        if (!outcome.isClosed()) return outcome;
    }
    return .closed;
}

/// Fills in the chain verdict of every class-level aspect.
///
/// It is separate from `java_members.aspectsOf` so the two projections stay
/// separate: one reports what a type declares, the other what a walk over
/// claims finds. The verdict belongs in the aspect because nothing else can
/// report it — a type whose supertype appears elsewhere in the repository
/// changes no byte and no label of its own, and every reader that walked
/// through it has to hear about that (ADR 011 D7).
pub fn annotateChains(
    graph: *Graph,
    aspects: []java_members.Aspect,
    gpa: Allocator,
) Allocator.Error!void {
    var closure: std.ArrayList(model.EntityId) = .empty;
    defer closure.deinit(gpa);

    for (aspects) |*aspect| {
        if (aspect.method.len != 0) continue;
        const id = aspect.entity orelse continue;
        closure.clearRetainingCapacity();
        aspect.chain = switch (try closureOf(graph, id, gpa, &closure)) {
            .closed => "closed",
            .open => |reason| reason.tag(),
        };
    }
}

/// What each name a unit writes in a supertype position reaches.
///
/// The names are the question, so they bound the answer: each is looked up in
/// the order the frontend would look it up — a single-type import before the
/// unit's own package — and only what a closure holds is carried. A name that
/// reaches no unique type gets no entry; the frontend resolves it against the
/// unit's own declarations, or declines with `resolveType`'s reason.
///
/// Nothing here decides anything. The lists are what a chain is walked to rule
/// out, and no entity of the closure leaves this function.
pub fn hierarchiesFor(
    graph: *Graph,
    context: java.Context,
    names: []const []const u8,
    allocator: Allocator,
) Allocator.Error![]const java.Hierarchy {
    var found: std.ArrayList(java.Hierarchy) = .empty;
    var closure: std.ArrayList(model.EntityId) = .empty;
    defer closure.deinit(allocator);
    var methods: std.ArrayList(java_members.Method) = .empty;
    defer methods.deinit(allocator);

    for (names) |name| {
        if (indexOfName(found.items, name) != null) continue;

        const binding = context.importLookup(name) orelse
            context.lookup(context.package, name) orelse continue;
        const target = switch (binding) {
            .unique => |unique| unique,
            .ambiguous, .out_of_scope => continue,
        };
        if (java_members.classShapeOf(graph, target.entity) == null) {
            try found.append(allocator, .{ .name = name, .open = java.chain.provider_stale });
            continue;
        }

        closure.clearRetainingCapacity();
        const outcome = try closureOf(graph, target.entity, allocator, &closure);
        const open: ?[]const u8 = switch (outcome) {
            .closed => null,
            .open => |reason| switch (reason) {
                .supertype_unresolved => java.chain.unresolved_above,
                .supertype_not_a_type => java.chain.not_a_type,
                .supertype_provider_stale => java.chain.provider_stale,
                .cycle => java.chain.cycle,
                .depth_cap => java.chain.too_deep,
            },
        };

        var member_types: std.ArrayList([]const u8) = .empty;
        var fields: std.ArrayList([]const u8) = .empty;
        var method_names: std.ArrayList([]const u8) = .empty;
        var inherited: std.ArrayList([]const u8) = .empty;
        var type_names: std.ArrayList([]const u8) = .empty;
        var providers: std.ArrayList(model.SourceUnitId) = .empty;

        // What the walk visited is carried even when it failed. A reader owes a
        // dependency and a hint to every type it read, and an open chain is
        // read exactly as far as the condition that stopped it (ADR 011 D7).
        for (closure.items) |id| {
            const shape = java_members.classShapeOf(graph, id) orelse continue;
            try type_names.append(allocator, shape.name);
            if (std.mem.indexOfScalar(model.SourceUnitId, providers.items, shape.unit) == null) {
                try providers.append(allocator, shape.unit);
            }
            const entity = graph.entity(id).?;
            if (entity.extension.get(java.member_types.key)) |value| {
                try java.member_types.appendTo(allocator, &member_types, value);
            }
            if (entity.extension.get(java.field_names.key)) |value| {
                try java.field_names.appendTo(allocator, &fields, value);
            }
            methods.clearRetainingCapacity();
            try java_members.methodsOf(graph, shape, allocator, &methods);
            for (methods.items) |method| {
                try method_names.append(allocator, method.name);
                if (id != target.entity) try inherited.append(allocator, method.name);
            }
        }

        try found.append(allocator, .{
            .name = name,
            .open = open,
            .member_types = member_types.items,
            .fields = fields.items,
            .methods = method_names.items,
            .inherited_methods = inherited.items,
            .types = type_names.items,
            .providers = providers.items,
        });
    }
    return found.items;
}

fn indexOfName(entries: []const java.Hierarchy, name: []const u8) ?usize {
    for (entries, 0..) |entry, at| {
        if (std.mem.eql(u8, entry.name, name)) return at;
    }
    return null;
}
