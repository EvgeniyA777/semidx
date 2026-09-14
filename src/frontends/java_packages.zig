//! Java package bindings: which top-level class a simple type name can mean
//! inside one explicit Java package, read from current graph facts.
//!
//! This is a projection for the analyzer, not a graph model. It creates no
//! package entity, no module, and no import relationship, and the table it
//! builds has no authority beyond handing the Java frontend candidates to check
//! under ADR 004. Everything it returns is re-read from the graph on every call.
//!
//! The one thing kept between calls is a hint: which units have declared
//! classes in which package. It exists so that building one package's table
//! costs what that package holds, not what the repository holds. A hint is never
//! an answer — every hinted unit is read back from the graph, and one that no
//! longer declares anything in the package simply contributes nothing.

const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("semidx_core");
const java = @import("java.zig");

const model = core.model;
const Graph = core.Graph;

/// One top-level class a unit currently establishes in an explicit package.
/// Strings are borrowed from the graph.
pub const Export = struct {
    package: []const u8,
    name: []const u8,
    entity: model.EntityId,
    unit: model.SourceUnitId,

    pub fn eql(a: Export, b: Export) bool {
        return std.mem.eql(u8, a.package, b.package) and std.mem.eql(u8, a.name, b.name);
    }
};

/// Whether a definition is shaped like a top-level Java class declared in an
/// explicit package, and if so its package. Says nothing about whether it is a
/// current fact.
fn exportedPackage(entity: model.Entity) ?[]const u8 {
    if (entity.kind != .definition) return null;
    if (entity.identity.language != .java) return null;
    if (!std.mem.eql(u8, entity.identity.role, "class")) return null;
    if (entity.identity.container_path.len != 0) return null;
    if (entity.identity.name == null) return null;
    if (!std.mem.eql(u8, entity.extension.namespace, "java")) return null;
    const package = entity.extension.get("java.package") orelse return null;
    if (package.len == 0) return null;
    return package;
}

/// The top-level classes `unit` currently establishes in explicit packages: live
/// definitions whose existence the Java frontend recorded as a current fact.
///
/// A unit whose analysis is stale or failed exports nothing, because nothing it
/// once declared is a current fact.
pub fn exportsOf(
    graph: *Graph,
    unit: model.SourceUnitId,
    gpa: Allocator,
    out: *std.ArrayList(Export),
) Allocator.Error!void {
    const record = graph.unit(unit) orelse return;
    if (!record.isLive() or record.language != .java) return;

    var definitions: std.ArrayList(model.EntityId) = .empty;
    defer definitions.deinit(gpa);
    try graph.definitionsInUnit(unit, &definitions, gpa);

    for (definitions.items) |id| {
        const entity = graph.entity(id).?;
        const package = exportedPackage(entity) orelse continue;
        const fact = graph.currentDefinitionFact(id) orelse continue;
        if (!std.mem.eql(u8, fact.producer.name, java.capabilities.producer.name)) continue;
        try out.append(gpa, .{
            .package = package,
            .name = entity.identity.name.?,
            .entity = id,
            .unit = unit,
        });
    }
}

pub const Packages = struct {
    gpa: Allocator,
    /// Owns the package names used as keys.
    names: std.heap.ArenaAllocator,
    /// Units that have declared a top-level class in each package, in the order
    /// they were first seen. A superset of the current truth.
    units: std.StringHashMapUnmanaged(std.ArrayList(model.SourceUnitId)),

    pub fn init(gpa: Allocator) Packages {
        return .{
            .gpa = gpa,
            .names = std.heap.ArenaAllocator.init(gpa),
            .units = .empty,
        };
    }

    pub fn deinit(self: *Packages) void {
        var entries = self.units.valueIterator();
        while (entries.next()) |list| list.deinit(self.gpa);
        self.units.deinit(self.gpa);
        self.names.deinit();
        self.* = undefined;
    }

    /// Remembers the packages a just-analyzed unit declared classes in.
    ///
    /// Read from the unit's definitions only, so a unit whose analysis did not
    /// apply is remembered by what it declared last time — which is harmless,
    /// because a hint is re-read before it is used.
    pub fn note(self: *Packages, graph: *Graph, unit: model.SourceUnitId) Allocator.Error!void {
        var definitions: std.ArrayList(model.EntityId) = .empty;
        defer definitions.deinit(self.gpa);
        try graph.definitionsInUnit(unit, &definitions, self.gpa);

        for (definitions.items) |id| {
            const package = exportedPackage(graph.entity(id).?) orelse continue;
            const slot = try self.units.getOrPut(self.gpa, package);
            if (!slot.found_existing) {
                slot.key_ptr.* = try self.names.allocator().dupe(u8, package);
                slot.value_ptr.* = .empty;
            }
            if (std.mem.indexOfScalar(model.SourceUnitId, slot.value_ptr.items, unit) == null) {
                try slot.value_ptr.append(self.gpa, unit);
            }
        }
    }

    /// Units that may declare classes in `package`. Read each one back before
    /// relying on it.
    pub fn candidates(self: *const Packages, package: []const u8) []const model.SourceUnitId {
        const list = self.units.getPtr(package) orelse return &.{};
        return list.items;
    }

    /// Builds the binding table for `package` as the unit `analyzed` should see
    /// it: every current top-level class other units declare there, with names
    /// declared more than once marked ambiguous instead of resolved to one.
    ///
    /// The analyzed unit's own previous classes are left out. It is being read
    /// again, and what it declares now is its own business.
    pub fn context(
        self: *const Packages,
        graph: *Graph,
        package: []const u8,
        analyzed: model.SourceUnitId,
        allocator: Allocator,
    ) Allocator.Error!java.Context {
        if (package.len == 0) return .empty;

        var exports: std.ArrayList(Export) = .empty;
        for (self.candidates(package)) |unit| {
            if (unit == analyzed) continue;
            try exportsOf(graph, unit, allocator, &exports);
        }

        var types: std.ArrayList(java.TypeBinding) = .empty;
        var positions: std.StringHashMapUnmanaged(usize) = .empty;
        for (exports.items) |candidate| {
            if (!std.mem.eql(u8, candidate.package, package)) continue;
            const slot = try positions.getOrPut(allocator, candidate.name);
            if (!slot.found_existing) {
                slot.value_ptr.* = types.items.len;
                try types.append(allocator, .{
                    .name = candidate.name,
                    .binding = .{ .unique = .{ .entity = candidate.entity, .provider = candidate.unit } },
                });
                continue;
            }
            const binding = &types.items[slot.value_ptr.*].binding;
            binding.* = switch (binding.*) {
                .unique => .{ .ambiguous = 2 },
                .ambiguous => |count| .{ .ambiguous = count + 1 },
            };
        }

        return .{ .package = package, .types = types.items };
    }
};
