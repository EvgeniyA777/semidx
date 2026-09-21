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

/// Whether any type in `closure` declares a member of `name` that could give an
/// inherited meaning to it.
///
/// It rules out and never selects: the answer is a boolean about the whole
/// closure, and no entity is returned, so no caller can turn it into a target.
pub fn declaresMethod(
    graph: *Graph,
    closure: []const model.EntityId,
    skip: model.EntityId,
    name: []const u8,
    gpa: Allocator,
) Allocator.Error!bool {
    var methods: std.ArrayList(java_members.Method) = .empty;
    defer methods.deinit(gpa);

    for (closure) |id| {
        if (id == skip) continue;
        const shape = java_members.classShapeOf(graph, id) orelse continue;
        methods.clearRetainingCapacity();
        try java_members.methodsOf(graph, shape, gpa, &methods);
        for (methods.items) |method| {
            if (std.mem.eql(u8, method.name, name)) return true;
        }
    }
    return false;
}

/// Whether any type in `closure` declares a member type of `name`.
///
/// A member type is not a definition this frontend records, so the question is
/// answered from the label its declaring analysis wrote rather than from
/// definitions that do not exist.
pub fn declaresMemberType(
    graph: *Graph,
    closure: []const model.EntityId,
    skip: model.EntityId,
    name: []const u8,
) bool {
    for (closure) |id| {
        if (id == skip) continue;
        const found = graph.entity(id) orelse continue;
        const declared = found.extension.get(java.member_types.key) orelse continue;
        if (java.member_types.contains(declared, name)) return true;
    }
    return false;
}
