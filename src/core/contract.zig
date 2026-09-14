//! The contract by which a language frontend contributes assertions.
//!
//! A frontend never allocates graph identity and never writes to the graph. It
//! describes what it found in one source unit, in shared-core terms, with
//! language-specific meaning confined to extension payloads. Whether a
//! frontend used tree-sitter, a compiler, or an index is invisible here.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");

pub const SourceUnit = struct {
    id: model.SourceUnitId,
    /// Repository-relative path. Stable across edits to the unit's contents.
    path: []const u8,
    language: model.Language,
    bytes: []const u8,
};

/// A parser's own state from the previous analysis of the same unit, passed
/// back when the parser supports incremental parsing. The pointer is owned and
/// interpreted by the parser adapter; the shared core never dereferences it.
pub const PreviousParse = struct {
    adapter: []const u8,
    handle: ?*anyopaque,
};

pub const FrontendInput = struct {
    unit: SourceUnit,
    previous: ?PreviousParse = null,
};

/// What a frontend declares it can produce. Coverage differs across frontends;
/// what must not differ is the meaning of the kinds they do produce.
pub const Capabilities = struct {
    language: model.Language,
    producer: model.Producer,
    entity_roles: []const []const u8,
    relationship_kinds: []const model.RelationshipKind,
    coverage_note: []const u8,
};

/// A relationship endpoint inside one batch.
///
/// `unit_container` names the source container for the unit being analyzed.
/// The frontend refers to it without knowing its entity id, because source
/// containers are established by source ingestion, not by a frontend.
pub const LocalRef = union(enum) {
    unit_container,
    entity: u32,
};

/// A definition another source unit established, as the frontend was handed it.
///
/// The frontend does not allocate this id and cannot discover it by itself: it
/// only ever sees one unit. Whoever builds its analysis context reads the id
/// from the graph together with the unit that introduced it, and integration
/// re-checks both against the graph before anything is recorded.
pub const ExternalTarget = struct {
    entity: model.EntityId,
    /// The unit whose analysis established the target. The batch must also
    /// declare a dependency on it, so a change there reaches this unit.
    provider: model.SourceUnitId,
};

pub const DraftTarget = union(enum) {
    /// Resolved inside the analyzed unit.
    local: u32,
    /// Resolved to a definition established outside the analyzed unit.
    external: ExternalTarget,
    /// A name read from source that the frontend could not resolve.
    designator: []const u8,
};

pub const DraftEntity = struct {
    kind: model.EntityKind,
    identity: model.IdentityEvidence,
    evidence: model.SourceEvidence,
    extension: model.ExtensionPayload,
    /// How far the frontend established that this entity exists. The core does
    /// not decide this on a frontend's behalf.
    resolution: model.Resolution,
};

pub const DraftRelationship = struct {
    kind: model.RelationshipKind,
    source: LocalRef,
    target: DraftTarget,
    evidence: model.SourceEvidence,
    resolution: model.Resolution,
};

/// A declaration that this unit's analysis read something about another unit.
///
/// A frontend can name another unit only through what its analysis context
/// handed it, so a dependency accompanies every `ExternalTarget` it records.
pub const DraftDependency = struct {
    provider: model.SourceUnitId,
    /// Why, in the producer's own words.
    reason: []const u8,
};

pub const DraftDiagnostic = struct {
    kind: model.DiagnosticKind,
    message: []const u8,
};

/// One frontend's complete account of one source unit.
///
/// An empty `entities` list means "the frontend found nothing" only when no
/// diagnostic says otherwise; `analysis_unavailable` and `analysis_failed`
/// exist so that failure never reads as absence.
pub const FrontendBatch = struct {
    unit: model.SourceUnitId,
    capabilities: Capabilities,
    entities: []const DraftEntity,
    relationships: []const DraftRelationship,
    diagnostics: []const DraftDiagnostic,
    dependencies: []const DraftDependency,

    pub fn hasBlockingDiagnostic(self: FrontendBatch) bool {
        for (self.diagnostics) |diagnostic| {
            switch (diagnostic.kind) {
                .analysis_unavailable, .analysis_failed => return true,
                .unsupported_construct, .confirmed_absence => {},
            }
        }
        return false;
    }
};

/// Scratch storage a frontend fills while analyzing one unit.
///
/// The builder owns every string it hands out. The graph interns what it keeps
/// during integration, so the builder can be released immediately afterwards.
pub const BatchBuilder = struct {
    gpa: Allocator,
    arena: std.heap.ArenaAllocator,
    unit: model.SourceUnitId,
    capabilities: Capabilities,
    entities: std.ArrayList(DraftEntity),
    relationships: std.ArrayList(DraftRelationship),
    diagnostics: std.ArrayList(DraftDiagnostic),
    dependencies: std.ArrayList(DraftDependency),

    pub fn init(gpa: Allocator, unit: model.SourceUnitId, capabilities: Capabilities) BatchBuilder {
        return .{
            .gpa = gpa,
            .arena = std.heap.ArenaAllocator.init(gpa),
            .unit = unit,
            .capabilities = capabilities,
            .entities = .empty,
            .relationships = .empty,
            .diagnostics = .empty,
            .dependencies = .empty,
        };
    }

    pub fn deinit(self: *BatchBuilder) void {
        self.entities.deinit(self.gpa);
        self.relationships.deinit(self.gpa);
        self.diagnostics.deinit(self.gpa);
        self.dependencies.deinit(self.gpa);
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn allocator(self: *BatchBuilder) Allocator {
        return self.arena.allocator();
    }

    pub fn dupe(self: *BatchBuilder, value: []const u8) Allocator.Error![]const u8 {
        return self.arena.allocator().dupe(u8, value);
    }

    pub fn dupeSlice(
        self: *BatchBuilder,
        values: []const []const u8,
    ) Allocator.Error![]const []const u8 {
        const owned = try self.arena.allocator().alloc([]const u8, values.len);
        for (values, owned) |value, *slot| slot.* = try self.dupe(value);
        return owned;
    }

    pub fn print(
        self: *BatchBuilder,
        comptime fmt: []const u8,
        args: anytype,
    ) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(self.arena.allocator(), fmt, args);
    }

    pub fn labels(
        self: *BatchBuilder,
        values: []const model.ExtensionLabel,
    ) Allocator.Error![]const model.ExtensionLabel {
        const owned = try self.arena.allocator().alloc(model.ExtensionLabel, values.len);
        for (values, owned) |label, *slot| {
            slot.* = .{ .key = try self.dupe(label.key), .value = try self.dupe(label.value) };
        }
        return owned;
    }

    /// Returns the batch-local index of the new entity, which relationships in
    /// the same batch use to refer to it.
    pub fn addEntity(self: *BatchBuilder, entity: DraftEntity) Allocator.Error!u32 {
        const index: u32 = @intCast(self.entities.items.len);
        try self.entities.append(self.gpa, entity);
        return index;
    }

    pub fn addRelationship(
        self: *BatchBuilder,
        relationship: DraftRelationship,
    ) Allocator.Error!void {
        try self.relationships.append(self.gpa, relationship);
    }

    pub fn addDiagnostic(
        self: *BatchBuilder,
        kind: model.DiagnosticKind,
        message: []const u8,
    ) Allocator.Error!void {
        try self.diagnostics.append(self.gpa, .{ .kind = kind, .message = try self.dupe(message) });
    }

    pub fn addDependency(
        self: *BatchBuilder,
        provider: model.SourceUnitId,
        reason: []const u8,
    ) Allocator.Error!void {
        try self.dependencies.append(self.gpa, .{
            .provider = provider,
            .reason = try self.dupe(reason),
        });
    }

    pub fn batch(self: *const BatchBuilder) FrontendBatch {
        return .{
            .unit = self.unit,
            .capabilities = self.capabilities,
            .entities = self.entities.items,
            .relationships = self.relationships.items,
            .diagnostics = self.diagnostics.items,
            .dependencies = self.dependencies.items,
        };
    }
};

const testing = std.testing;

test "a batch reporting unavailable analysis is not an empty result" {
    const capabilities: Capabilities = .{
        .language = .java,
        .producer = .{ .name = "frontend.java", .version = "slice-001" },
        .entity_roles = &.{"method"},
        .relationship_kinds = &.{ .defines, .references, .calls },
        .coverage_note = "fixture scope only",
    };

    var empty = BatchBuilder.init(testing.allocator, @enumFromInt(0), capabilities);
    defer empty.deinit();
    try testing.expectEqual(@as(usize, 0), empty.batch().entities.len);
    try testing.expect(!empty.batch().hasBlockingDiagnostic());

    var failed = BatchBuilder.init(testing.allocator, @enumFromInt(0), capabilities);
    defer failed.deinit();
    try failed.addDiagnostic(.analysis_unavailable, "no parser for this unit");
    try testing.expectEqual(@as(usize, 0), failed.batch().entities.len);
    try testing.expect(failed.batch().hasBlockingDiagnostic());
}

test "an unsupported construct does not make the rest of the batch unavailable" {
    const capabilities: Capabilities = .{
        .language = .clojure,
        .producer = .{ .name = "frontend.clojure", .version = "slice-001" },
        .entity_roles = &.{"defn"},
        .relationship_kinds = &.{.defines},
        .coverage_note = "fixture scope only",
    };
    var builder = BatchBuilder.init(testing.allocator, @enumFromInt(0), capabilities);
    defer builder.deinit();
    try builder.addDiagnostic(.unsupported_construct, "defmacro is outside fixture coverage");
    try testing.expect(!builder.batch().hasBlockingDiagnostic());
}
