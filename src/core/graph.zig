//! The in-memory semantic graph and the only place semantic answers come from.
//!
//! `Graph` is the mutable store. `Snapshot` is what a consumer observes: one
//! complete state, published atomically, with every query reading from it.
//! Nothing here knows how a frontend parsed anything.

const std = @import("std");
const Allocator = std.mem.Allocator;

const model = @import("model.zig");
const contract = @import("contract.zig");
const StringPool = @import("strings.zig").StringPool;

pub const EntityId = model.EntityId;
pub const SourceUnitId = model.SourceUnitId;

pub const GraphError = error{
    UnknownEntity,
    RemovedEntity,
    UnresolvedContainment,
    DuplicateSourceUnitPath,
    UnknownSourceUnit,
    DanglingAssertionEndpoint,
} || model.ValidationError || Allocator.Error;

/// Source ingestion establishes source containers. It is a distinct producer
/// from any frontend, because what it can establish is different.
pub const ingestion: model.Producer = .{ .name = "source-ingestion", .version = "slice-001" };

/// The reconciler establishes identity correspondence between revisions.
pub const reconciler: model.Producer = .{ .name = "reconciler", .version = "slice-001" };

/// What the graph currently knows about a source unit's contents.
///
/// A unit whose contents changed without a successful reanalysis is `stale`,
/// not empty. Withdrawing its assertions would assert an absence nothing
/// observed; presenting them as current would claim they describe source that
/// is no longer there. Neither is honest, so the state is reported instead.
pub const UnitAnalysis = enum { pending, current, stale };

pub const SourceUnitRecord = struct {
    id: SourceUnitId,
    path: []const u8,
    language: model.Language,
    /// Current contents. Owned by the graph and replaced on each edit.
    bytes: []u8,
    /// The `file` entity for this unit.
    entity: EntityId,
    /// The revision at which these contents were established.
    content_revision: u64,
    /// The revision at which a frontend last analyzed this unit successfully,
    /// or 0 if it never has.
    analysis_revision: u64,

    pub fn analysis(self: SourceUnitRecord) UnitAnalysis {
        if (self.analysis_revision == 0) return .pending;
        return if (self.analysis_revision >= self.content_revision) .current else .stale;
    }

    pub fn view(self: SourceUnitRecord) SourceUnitView {
        return .{
            .id = self.id,
            .path = self.path,
            .language = self.language,
            .content_revision = self.content_revision,
            .analysis_revision = self.analysis_revision,
        };
    }
};

/// The part of a source unit a consumer observes. It carries no contents: a
/// snapshot answers questions about the graph, not about source text.
pub const SourceUnitView = struct {
    id: SourceUnitId,
    path: []const u8,
    language: model.Language,
    content_revision: u64,
    analysis_revision: u64,

    pub fn analysis(self: SourceUnitView) UnitAnalysis {
        if (self.analysis_revision == 0) return .pending;
        return if (self.analysis_revision >= self.content_revision) .current else .stale;
    }
};

pub const Graph = struct {
    gpa: Allocator,
    pool: StringPool,
    revision: u64,
    next_assertion: u32,
    repository: EntityId,
    entities: std.ArrayList(model.Entity),
    assertions: std.ArrayList(model.Assertion),
    diagnostics: std.ArrayList(model.Diagnostic),
    identity_events: std.ArrayList(model.IdentityEvent),
    units: std.ArrayList(SourceUnitRecord),

    pub fn init(gpa: Allocator, repository_path: []const u8) GraphError!Graph {
        var self: Graph = .{
            .gpa = gpa,
            .pool = StringPool.init(gpa),
            .revision = 1,
            .next_assertion = 0,
            .repository = @enumFromInt(0),
            .entities = .empty,
            .assertions = .empty,
            .diagnostics = .empty,
            .identity_events = .empty,
            .units = .empty,
        };
        errdefer self.deinit();

        self.repository = try self.addEntity(.{
            .kind = .repository,
            .identity = .{
                .scope = repository_path,
                .language = null,
                .role = "repository",
                .name = repository_path,
                .signature = null,
                .container_path = &.{},
            },
            .evidence = null,
            .extension = model.ExtensionPayload.empty,
        });
        _ = try self.addAssertion(
            .{ .entity_exists = self.repository },
            ingestion,
            null,
            .{ .fact = .{ .method = "indexed source tree root" } },
        );
        return self;
    }

    pub fn deinit(self: *Graph) void {
        for (self.units.items) |record| self.gpa.free(record.bytes);
        self.units.deinit(self.gpa);
        self.entities.deinit(self.gpa);
        self.assertions.deinit(self.gpa);
        self.diagnostics.deinit(self.gpa);
        self.identity_events.deinit(self.gpa);
        self.pool.deinit();
        self.* = undefined;
    }

    /// Opens a new revision. Every mutation until the next call is attributed
    /// to it, and a snapshot published afterwards observes it as one state.
    pub fn beginRevision(self: *Graph) u64 {
        self.revision += 1;
        return self.revision;
    }

    // -- source ingestion ---------------------------------------------------

    pub fn addSourceUnit(
        self: *Graph,
        path: []const u8,
        language: model.Language,
        bytes: []const u8,
    ) GraphError!SourceUnitId {
        if (self.unitByPath(path) != null) return error.DuplicateSourceUnitPath;

        const id: SourceUnitId = @enumFromInt(@as(u32, @intCast(self.units.items.len)));
        const interned_path = try self.pool.intern(path);
        const owned_bytes = try self.gpa.dupe(u8, bytes);

        const file_entity = self.addEntity(.{
            .kind = .file,
            .identity = .{
                .scope = interned_path,
                .language = language,
                .role = "file",
                .name = interned_path,
                .signature = null,
                .container_path = &.{},
            },
            .evidence = .{
                .unit = id,
                .range = wholeUnitRange(bytes),
                .text = interned_path,
            },
            .extension = model.ExtensionPayload.empty,
        }) catch |err| {
            self.gpa.free(owned_bytes);
            return err;
        };

        self.units.append(self.gpa, .{
            .id = id,
            .path = interned_path,
            .language = language,
            .bytes = owned_bytes,
            .entity = file_entity,
            .content_revision = self.revision,
            .analysis_revision = 0,
        }) catch |err| {
            self.gpa.free(owned_bytes);
            return err;
        };

        try self.recordUnitIngestion(self.units.items[id.index()]);
        return id;
    }

    /// Applies an edit in its own revision: replaces one unit's contents and
    /// re-establishes what source ingestion claims about it, so the source
    /// container's extent describes the new contents rather than the old.
    ///
    /// The unit's frontend assertions are left exactly as they were and become
    /// stale, because nothing has yet read the new contents. A successful
    /// `Graph.markAnalyzed` for a later revision is what makes them current
    /// again. Every other unit is untouched.
    pub fn setSourceUnitBytes(
        self: *Graph,
        id: SourceUnitId,
        bytes: []const u8,
    ) GraphError!u64 {
        const index = id.index();
        if (index >= self.units.items.len) return error.UnknownSourceUnit;

        const revision = self.beginRevision();
        const owned = try self.gpa.dupe(u8, bytes);
        {
            const record = &self.units.items[index];
            self.gpa.free(record.bytes);
            record.bytes = owned;
            record.content_revision = revision;
        }

        const record = self.units.items[index];
        try self.refreshEntity(record.entity, .{
            .unit = record.id,
            .range = wholeUnitRange(record.bytes),
            .text = record.path,
        }, model.ExtensionPayload.empty);

        self.dropIngestionAssertionsForUnit(id);
        try self.recordUnitIngestion(record);
        return revision;
    }

    /// Records what source ingestion establishes about a unit's current
    /// contents: that the source container exists, and that the indexed source
    /// tree contains it. Both carry the unit's current extent.
    fn recordUnitIngestion(self: *Graph, record: SourceUnitRecord) GraphError!void {
        const evidence: model.SourceEvidence = .{
            .unit = record.id,
            .range = wholeUnitRange(record.bytes),
            .text = record.path,
        };
        _ = try self.addAssertion(
            .{ .entity_exists = record.entity },
            ingestion,
            evidence,
            .{ .fact = .{ .method = "source unit presented to analysis" } },
        );
        _ = try self.addRelationship(
            .{ .kind = .defines, .source = self.repository, .target = .{ .entity = record.entity } },
            ingestion,
            evidence,
            .{ .fact = .{ .method = "source unit belongs to the indexed source tree" } },
        );
    }

    /// Records that a frontend has analyzed this unit's current contents.
    pub fn markAnalyzed(self: *Graph, id: SourceUnitId) GraphError!void {
        const record = self.unitMut(id) orelse return error.UnknownSourceUnit;
        record.analysis_revision = self.revision;
    }

    pub fn unitByPath(self: *const Graph, path: []const u8) ?SourceUnitId {
        for (self.units.items) |record| {
            if (std.mem.eql(u8, record.path, path)) return record.id;
        }
        return null;
    }

    pub fn unit(self: *const Graph, id: SourceUnitId) ?SourceUnitRecord {
        const index = id.index();
        if (index >= self.units.items.len) return null;
        return self.units.items[index];
    }

    fn unitMut(self: *Graph, id: SourceUnitId) ?*SourceUnitRecord {
        const index = id.index();
        if (index >= self.units.items.len) return null;
        return &self.units.items[index];
    }

    pub fn frontendInput(self: *const Graph, id: SourceUnitId) ?contract.FrontendInput {
        const record = self.unit(id) orelse return null;
        return .{ .unit = .{
            .id = record.id,
            .path = record.path,
            .language = record.language,
            .bytes = record.bytes,
        } };
    }

    // -- entities -----------------------------------------------------------

    /// Allocating an entity does not assert that it exists. The producer that
    /// observed it records that separately, with its own provenance and
    /// resolution, so an existence claim is never manufactured by the store.
    pub const NewEntity = struct {
        kind: model.EntityKind,
        identity: model.IdentityEvidence,
        evidence: ?model.SourceEvidence,
        extension: model.ExtensionPayload,
    };

    pub fn addEntity(self: *Graph, spec: NewEntity) GraphError!EntityId {
        try model.validateIdentityEvidence(spec.identity);

        const id: EntityId = @enumFromInt(@as(u32, @intCast(self.entities.items.len)));
        const identity = try self.internIdentity(spec.identity);
        const evidence = try self.internEvidence(spec.evidence);
        const extension = try self.internExtension(spec.extension);

        try self.entities.append(self.gpa, .{
            .id = id,
            .kind = spec.kind,
            .identity = identity,
            .evidence = evidence,
            .extension = extension,
            .created_revision = self.revision,
            .observed_revision = self.revision,
            .removed_revision = null,
        });
        return id;
    }

    /// Refreshes the projections of an entity that kept its identity. The id,
    /// the kind, and the identity evidence are not touched.
    pub fn refreshEntity(
        self: *Graph,
        id: EntityId,
        evidence: ?model.SourceEvidence,
        extension: model.ExtensionPayload,
    ) GraphError!void {
        const record = self.entityMut(id) orelse return error.UnknownEntity;
        if (!record.isLive()) return error.RemovedEntity;
        record.evidence = try self.internEvidence(evidence);
        record.extension = try self.internExtension(extension);
        record.observed_revision = self.revision;
    }

    pub fn removeEntity(self: *Graph, id: EntityId) GraphError!void {
        const record = self.entityMut(id) orelse return error.UnknownEntity;
        if (!record.isLive()) return error.RemovedEntity;
        record.removed_revision = self.revision;
    }

    pub fn entity(self: *const Graph, id: EntityId) ?model.Entity {
        const index = id.index();
        if (index >= self.entities.items.len) return null;
        return self.entities.items[index];
    }

    fn entityMut(self: *Graph, id: EntityId) ?*model.Entity {
        const index = id.index();
        if (index >= self.entities.items.len) return null;
        return &self.entities.items[index];
    }

    /// Live definitions whose source evidence lies in the given unit. This is
    /// the affected semantic region of an edit to that unit.
    pub fn definitionsInUnit(
        self: *const Graph,
        id: SourceUnitId,
        out: *std.ArrayList(EntityId),
        gpa: Allocator,
    ) Allocator.Error!void {
        for (self.entities.items) |item| {
            if (item.kind != .definition or !item.isLive()) continue;
            const evidence = item.evidence orelse continue;
            if (evidence.unit == id) try out.append(gpa, item.id);
        }
    }

    // -- assertions ---------------------------------------------------------

    pub fn addAssertion(
        self: *Graph,
        claim: model.Claim,
        producer: model.Producer,
        evidence: ?model.SourceEvidence,
        resolution: model.Resolution,
    ) GraphError!model.AssertionId {
        try model.validateAssertion(claim, producer, evidence, resolution);
        try self.checkEndpoints(claim);

        const id: model.AssertionId = @enumFromInt(self.next_assertion);
        self.next_assertion += 1;

        try self.assertions.append(self.gpa, .{
            .id = id,
            .claim = claim,
            .producer = .{
                .name = try self.pool.intern(producer.name),
                .version = try self.pool.intern(producer.version),
            },
            .evidence = try self.internEvidence(evidence),
            .resolution = try self.internResolution(resolution),
            .revision = self.revision,
        });
        return id;
    }

    pub fn addRelationship(
        self: *Graph,
        claim: model.RelationshipClaim,
        producer: model.Producer,
        evidence: model.SourceEvidence,
        resolution: model.Resolution,
    ) GraphError!model.AssertionId {
        return self.addAssertion(.{ .relationship = claim }, producer, evidence, resolution);
    }

    /// Drops every assertion observed in one source unit. Used before a unit's
    /// assertions are re-derived; assertions from other units are untouched.
    pub fn dropAssertionsForUnit(self: *Graph, id: SourceUnitId) void {
        var write: usize = 0;
        for (self.assertions.items) |assertion| {
            const keep = blk: {
                const evidence = assertion.evidence orelse break :blk true;
                if (evidence.unit != id) break :blk true;
                // What source ingestion established about the unit itself
                // survives an edit to the unit's contents. Only analysis
                // derived from those contents is re-run.
                break :blk std.mem.eql(u8, assertion.producer.name, ingestion.name);
            };
            if (keep) {
                self.assertions.items[write] = assertion;
                write += 1;
            }
        }
        self.assertions.shrinkRetainingCapacity(write);
    }

    /// Drops what source ingestion previously claimed about one unit, so the
    /// claims can be re-established against its new contents.
    pub fn dropIngestionAssertionsForUnit(self: *Graph, id: SourceUnitId) void {
        var write: usize = 0;
        for (self.assertions.items) |assertion| {
            const keep = blk: {
                const evidence = assertion.evidence orelse break :blk true;
                if (evidence.unit != id) break :blk true;
                break :blk !std.mem.eql(u8, assertion.producer.name, ingestion.name);
            };
            if (keep) {
                self.assertions.items[write] = assertion;
                write += 1;
            }
        }
        self.assertions.shrinkRetainingCapacity(write);
    }

    pub fn dropDiagnosticsForUnit(self: *Graph, id: SourceUnitId) void {
        var write: usize = 0;
        for (self.diagnostics.items) |diagnostic| {
            const keep = diagnostic.unit == null or diagnostic.unit.? != id;
            if (keep) {
                self.diagnostics.items[write] = diagnostic;
                write += 1;
            }
        }
        self.diagnostics.shrinkRetainingCapacity(write);
    }

    pub fn addDiagnostic(
        self: *Graph,
        kind: model.DiagnosticKind,
        id: ?SourceUnitId,
        producer: model.Producer,
        message: []const u8,
    ) GraphError!void {
        try self.diagnostics.append(self.gpa, .{
            .kind = kind,
            .unit = id,
            .producer = .{
                .name = try self.pool.intern(producer.name),
                .version = try self.pool.intern(producer.version),
            },
            .message = try self.pool.intern(message),
            .revision = self.revision,
        });
    }

    pub fn addIdentityEvent(
        self: *Graph,
        kind: model.IdentityEventKind,
        id: EntityId,
        replacement: ?EntityId,
        reason: []const u8,
    ) GraphError!void {
        try self.identity_events.append(self.gpa, .{
            .kind = kind,
            .entity = id,
            .replacement = replacement,
            .reason = try self.pool.intern(reason),
            .revision = self.revision,
        });
    }

    // -- publication --------------------------------------------------------

    /// Publishes the current state as one immutable observable snapshot.
    ///
    /// The snapshot borrows interned strings from this graph, so it must be
    /// released before the graph is. Its entity and assertion arrays are its
    /// own: later mutation of the graph cannot be observed through it.
    pub fn publish(self: *Graph) GraphError!Snapshot {
        try self.checkInvariants();

        var entities: std.ArrayList(model.Entity) = .empty;
        errdefer entities.deinit(self.gpa);
        for (self.entities.items) |item| {
            if (item.isLive()) try entities.append(self.gpa, item);
        }

        var units: std.ArrayList(SourceUnitView) = .empty;
        errdefer units.deinit(self.gpa);
        for (self.units.items) |record| try units.append(self.gpa, record.view());

        return .{
            .gpa = self.gpa,
            .revision = self.revision,
            .entities = try entities.toOwnedSlice(self.gpa),
            .assertions = try self.gpa.dupe(model.Assertion, self.assertions.items),
            .diagnostics = try self.gpa.dupe(model.Diagnostic, self.diagnostics.items),
            .identity_events = try self.gpa.dupe(model.IdentityEvent, self.identity_events.items),
            .units = try units.toOwnedSlice(self.gpa),
        };
    }

    /// Refuses to publish a state whose assertions point at entities that are
    /// not there, rather than letting a query quietly skip them.
    pub fn checkInvariants(self: *const Graph) GraphError!void {
        for (self.assertions.items) |assertion| {
            switch (assertion.claim) {
                .entity_exists => |id| try self.expectLive(id),
                .relationship => |rel| {
                    try self.expectLive(rel.source);
                    switch (rel.target) {
                        .entity => |id| try self.expectLive(id),
                        .designator => {},
                    }
                },
                .identity_correspondence => |corr| {
                    try self.expectLive(corr.current);
                    if (self.entity(corr.previous) == null) return error.DanglingAssertionEndpoint;
                },
            }
        }
    }

    fn expectLive(self: *const Graph, id: EntityId) GraphError!void {
        const found = self.entity(id) orelse return error.DanglingAssertionEndpoint;
        if (!found.isLive()) return error.DanglingAssertionEndpoint;
    }

    fn checkEndpoints(self: *const Graph, claim: model.Claim) GraphError!void {
        switch (claim) {
            .entity_exists => {},
            .relationship => |rel| {
                const source = self.entity(rel.source) orelse return error.UnknownEntity;
                if (!source.isLive()) return error.RemovedEntity;
                switch (rel.target) {
                    .entity => |id| {
                        const target = self.entity(id) orelse return error.UnknownEntity;
                        if (!target.isLive()) return error.RemovedEntity;
                    },
                    .designator => if (rel.kind == .defines) return error.UnresolvedContainment,
                }
            },
            .identity_correspondence => |corr| {
                const current = self.entity(corr.current) orelse return error.UnknownEntity;
                if (!current.isLive()) return error.RemovedEntity;
                if (self.entity(corr.previous) == null) return error.UnknownEntity;
            },
        }
    }

    // -- interning ----------------------------------------------------------

    fn internIdentity(self: *Graph, value: model.IdentityEvidence) Allocator.Error!model.IdentityEvidence {
        return .{
            .scope = try self.pool.intern(value.scope),
            .language = value.language,
            .role = try self.pool.intern(value.role),
            .name = try self.pool.internOptional(value.name),
            .signature = try self.pool.internOptional(value.signature),
            .container_path = try self.pool.internSlice(value.container_path),
        };
    }

    fn internEvidence(self: *Graph, value: ?model.SourceEvidence) Allocator.Error!?model.SourceEvidence {
        const observed = value orelse return null;
        return .{
            .unit = observed.unit,
            .range = observed.range,
            .text = try self.pool.intern(observed.text),
        };
    }

    fn internExtension(self: *Graph, value: model.ExtensionPayload) Allocator.Error!model.ExtensionPayload {
        if (value.labels.len == 0) {
            return .{ .namespace = try self.pool.intern(value.namespace), .labels = &.{} };
        }
        const labels = try self.pool.allocator().alloc(model.ExtensionLabel, value.labels.len);
        for (value.labels, labels) |label, *slot| {
            slot.* = .{
                .key = try self.pool.intern(label.key),
                .value = try self.pool.intern(label.value),
            };
        }
        return .{ .namespace = try self.pool.intern(value.namespace), .labels = labels };
    }

    fn internResolution(self: *Graph, value: model.Resolution) Allocator.Error!model.Resolution {
        return switch (value) {
            .fact => |f| .{ .fact = .{ .method = try self.pool.intern(f.method) } },
            .unresolved => |u| .{ .unresolved = .{
                .missing = u.missing,
                .explanation = try self.pool.intern(u.explanation),
            } },
            .approximate => |a| .{ .approximate = .{
                .basis = try self.pool.intern(a.basis),
                .confidence = a.confidence,
            } },
        };
    }
};

fn wholeUnitRange(bytes: []const u8) model.SourceRange {
    var rows: u32 = 0;
    var last_newline: usize = 0;
    for (bytes, 0..) |byte, index| {
        if (byte == '\n') {
            rows += 1;
            last_newline = index + 1;
        }
    }
    return .{
        .start_byte = 0,
        .end_byte = @intCast(bytes.len),
        .start_row = 0,
        .start_column = 0,
        .end_row = rows,
        .end_column = @intCast(bytes.len - last_newline),
    };
}

/// What a consumer observes: one complete graph state.
///
/// Queries default to current claims only. A claim recorded before its source
/// unit's contents last changed is stale: it is still here, still attributed,
/// and still reachable by asking for it, but a query that did not ask for stale
/// claims is never answered with one.
pub const Snapshot = struct {
    gpa: Allocator,
    revision: u64,
    entities: []const model.Entity,
    assertions: []const model.Assertion,
    diagnostics: []const model.Diagnostic,
    identity_events: []const model.IdentityEvent,
    units: []const SourceUnitView,

    pub fn deinit(self: *Snapshot) void {
        self.gpa.free(self.entities);
        self.gpa.free(self.assertions);
        self.gpa.free(self.diagnostics);
        self.gpa.free(self.identity_events);
        self.gpa.free(self.units);
        self.* = undefined;
    }

    // -- freshness ----------------------------------------------------------

    pub fn unit(self: Snapshot, id: SourceUnitId) ?SourceUnitView {
        for (self.units) |view| {
            if (view.id == id) return view;
        }
        return null;
    }

    pub fn unitByPath(self: Snapshot, path: []const u8) ?SourceUnitView {
        for (self.units) |view| {
            if (std.mem.eql(u8, view.path, path)) return view;
        }
        return null;
    }

    pub fn unitAnalysis(self: Snapshot, id: SourceUnitId) ?UnitAnalysis {
        const view = self.unit(id) orelse return null;
        return view.analysis();
    }

    pub fn countUnits(self: Snapshot, analysis: UnitAnalysis) usize {
        var count: usize = 0;
        for (self.units) |view| {
            if (view.analysis() == analysis) count += 1;
        }
        return count;
    }

    /// A claim observed in a source unit is current when it was recorded at or
    /// after the revision that established the unit's contents. A claim with no
    /// source unit behind it cannot go stale this way.
    fn freshnessAt(
        self: Snapshot,
        evidence: ?model.SourceEvidence,
        revision: u64,
    ) model.Freshness {
        const observed = evidence orelse return .current;
        const view = self.unit(observed.unit) orelse return .current;
        return if (revision >= view.content_revision) .current else .stale;
    }

    pub fn entityFreshness(self: Snapshot, entity: model.Entity) model.Freshness {
        return self.freshnessAt(entity.evidence, entity.observed_revision);
    }

    pub fn assertionFreshness(self: Snapshot, assertion: model.Assertion) model.Freshness {
        return self.freshnessAt(assertion.evidence, assertion.revision);
    }

    // -- entities -----------------------------------------------------------

    pub const EntityFilter = struct {
        kind: ?model.EntityKind = null,
        scope: ?[]const u8 = null,
        name: ?[]const u8 = null,
        role: ?[]const u8 = null,
        language: ?model.Language = null,
        /// `null` matches regardless of freshness. The default is deliberately
        /// not that: a caller who did not ask for stale entities must not be
        /// handed one.
        freshness: ?model.Freshness = .current,
    };

    pub const EntityIterator = struct {
        snapshot: *const Snapshot,
        index: usize,
        filter: EntityFilter,

        pub fn next(self: *EntityIterator) ?model.Entity {
            while (self.index < self.snapshot.entities.len) {
                const entity = self.snapshot.entities[self.index];
                self.index += 1;
                if (self.filter.kind) |kind| {
                    if (entity.kind != kind) continue;
                }
                if (self.filter.scope) |scope| {
                    if (!std.mem.eql(u8, entity.identity.scope, scope)) continue;
                }
                if (self.filter.name) |name| {
                    const entity_name = entity.identity.name orelse continue;
                    if (!std.mem.eql(u8, entity_name, name)) continue;
                }
                if (self.filter.role) |role| {
                    if (!std.mem.eql(u8, entity.identity.role, role)) continue;
                }
                if (self.filter.language) |language| {
                    const entity_language = entity.identity.language orelse continue;
                    if (entity_language != language) continue;
                }
                if (self.filter.freshness) |freshness| {
                    if (self.snapshot.entityFreshness(entity) != freshness) continue;
                }
                return entity;
            }
            return null;
        }
    };

    pub fn entitiesMatching(self: *const Snapshot, filter: EntityFilter) EntityIterator {
        return .{ .snapshot = self, .index = 0, .filter = filter };
    }

    pub fn countEntities(self: *const Snapshot, filter: EntityFilter) usize {
        var iterator = self.entitiesMatching(filter);
        var count: usize = 0;
        while (iterator.next()) |_| count += 1;
        return count;
    }

    pub fn findEntity(self: *const Snapshot, filter: EntityFilter) ?model.Entity {
        var iterator = self.entitiesMatching(filter);
        return iterator.next();
    }

    /// Entities are looked up by their id; this looks one up by the id it
    /// carries, not by anything derived from its evidence.
    pub fn entityById(self: Snapshot, id: EntityId) ?model.Entity {
        for (self.entities) |item| {
            if (item.id == id) return item;
        }
        return null;
    }

    /// Looks a definition up by identity evidence a consumer can name. It is a
    /// query convenience, not an identity: the answer is an entity that carries
    /// its own id. Stale definitions are excluded, like every other query.
    pub fn findDefinition(self: *const Snapshot, scope: []const u8, name: []const u8) ?model.Entity {
        return self.findEntity(.{ .kind = .definition, .scope = scope, .name = name });
    }

    // -- relationships ------------------------------------------------------

    pub const RelationshipFilter = struct {
        source: ?EntityId = null,
        target: ?EntityId = null,
        kind: ?model.RelationshipKind = null,
        /// Matches every kind that answers an "all references" query, so one
        /// occurrence recorded as a call is counted once and only once.
        reference_query: bool = false,
        resolution: ?model.ResolutionCategory = null,
        designator: ?[]const u8 = null,
        /// `null` matches regardless of freshness. The default excludes claims
        /// recorded against contents the unit no longer has.
        freshness: ?model.Freshness = .current,
    };

    pub const RelationshipIterator = struct {
        snapshot: *const Snapshot,
        assertions: []const model.Assertion,
        index: usize,
        filter: RelationshipFilter,

        pub fn next(self: *RelationshipIterator) ?model.Assertion {
            while (self.index < self.assertions.len) {
                const assertion = self.assertions[self.index];
                self.index += 1;
                if (self.filter.freshness) |freshness| {
                    if (self.snapshot.assertionFreshness(assertion) != freshness) continue;
                }
                const rel = assertion.relationship() orelse continue;
                if (self.filter.reference_query) {
                    if (!rel.kind.satisfiesReferenceQuery()) continue;
                } else if (self.filter.kind) |kind| {
                    if (rel.kind != kind) continue;
                }
                if (self.filter.source) |source| {
                    if (rel.source != source) continue;
                }
                if (self.filter.target) |target| {
                    switch (rel.target) {
                        .entity => |id| if (id != target) continue,
                        .designator => continue,
                    }
                }
                if (self.filter.designator) |designator| {
                    switch (rel.target) {
                        .designator => |value| if (!std.mem.eql(u8, value, designator)) continue,
                        .entity => continue,
                    }
                }
                if (self.filter.resolution) |category| {
                    if (assertion.resolution.category() != category) continue;
                }
                return assertion;
            }
            return null;
        }
    };

    pub fn relationships(self: *const Snapshot, filter: RelationshipFilter) RelationshipIterator {
        return .{
            .snapshot = self,
            .assertions = self.assertions,
            .index = 0,
            .filter = filter,
        };
    }

    pub fn countRelationships(self: *const Snapshot, filter: RelationshipFilter) usize {
        var iterator = self.relationships(filter);
        var count: usize = 0;
        while (iterator.next()) |_| count += 1;
        return count;
    }

    pub fn firstRelationship(self: *const Snapshot, filter: RelationshipFilter) ?model.Assertion {
        var iterator = self.relationships(filter);
        return iterator.next();
    }

    pub const AssertionFilter = struct {
        resolution: ?model.ResolutionCategory = null,
        unit: ?SourceUnitId = null,
        /// Producer name, so a consumer can ask what one producer established
        /// rather than treating every assertion as equally sourced.
        producer: ?[]const u8 = null,
        freshness: ?model.Freshness = .current,
    };

    pub fn countAssertions(self: *const Snapshot, filter: AssertionFilter) usize {
        var count: usize = 0;
        for (self.assertions) |assertion| {
            if (filter.resolution) |category| {
                if (assertion.resolution.category() != category) continue;
            }
            if (filter.unit) |id| {
                const evidence = assertion.evidence orelse continue;
                if (evidence.unit != id) continue;
            }
            if (filter.producer) |name| {
                if (!std.mem.eql(u8, assertion.producer.name, name)) continue;
            }
            if (filter.freshness) |freshness| {
                if (self.assertionFreshness(assertion) != freshness) continue;
            }
            count += 1;
        }
        return count;
    }

    pub fn countUnresolvedAssertions(self: *const Snapshot) usize {
        return self.countAssertions(.{ .resolution = .unresolved });
    }

    pub fn countApproximateAssertions(self: *const Snapshot) usize {
        return self.countAssertions(.{ .resolution = .approximate });
    }

    pub fn identityEventsAt(self: Snapshot, revision: u64, gpa: Allocator) Allocator.Error![]model.IdentityEvent {
        var out: std.ArrayList(model.IdentityEvent) = .empty;
        errdefer out.deinit(gpa);
        for (self.identity_events) |event| {
            if (event.revision == revision) try out.append(gpa, event);
        }
        return out.toOwnedSlice(gpa);
    }

    pub fn identityEventFor(self: Snapshot, id: EntityId, revision: u64) ?model.IdentityEvent {
        for (self.identity_events) |event| {
            if (event.entity == id and event.revision == revision) return event;
        }
        return null;
    }

    pub fn countDiagnostics(self: Snapshot, kind: model.DiagnosticKind) usize {
        var count: usize = 0;
        for (self.diagnostics) |diagnostic| {
            if (diagnostic.kind == kind) count += 1;
        }
        return count;
    }

    pub fn findDiagnostic(self: Snapshot, kind: model.DiagnosticKind) ?model.Diagnostic {
        for (self.diagnostics) |diagnostic| {
            if (diagnostic.kind == kind) return diagnostic;
        }
        return null;
    }
};

const testing = std.testing;

fn testRange(start: u32, end: u32) model.SourceRange {
    return .{
        .start_byte = start,
        .end_byte = end,
        .start_row = 0,
        .start_column = start,
        .end_row = 0,
        .end_column = end,
    };
}

const frontend: model.Producer = .{ .name = "frontend.test", .version = "slice-001" };

fn addDefinition(
    graph: *Graph,
    unit: SourceUnitId,
    scope: []const u8,
    name: []const u8,
    range: model.SourceRange,
) !EntityId {
    const evidence: model.SourceEvidence = .{ .unit = unit, .range = range, .text = name };
    const id = try graph.addEntity(.{
        .kind = .definition,
        .identity = .{
            .scope = scope,
            .language = .java,
            .role = "method",
            .name = name,
            .signature = name,
            .container_path = &.{},
        },
        .evidence = evidence,
        .extension = .{ .namespace = "java", .labels = &.{} },
    });
    _ = try graph.addAssertion(
        .{ .entity_exists = id },
        frontend,
        evidence,
        .{ .fact = .{ .method = "declaration in source" } },
    );
    try graph.markAnalyzed(unit);
    return id;
}

test "a graph is built and queried without any language frontend" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    const greet = try addDefinition(&graph, unit, "a/A.java", "greet", testRange(0, 5));
    const greeting = try addDefinition(&graph, unit, "a/A.java", "greeting", testRange(6, 14));

    _ = try graph.addRelationship(
        .{ .kind = .calls, .source = greet, .target = .{ .entity = greeting } },
        frontend,
        .{ .unit = unit, .range = testRange(20, 30), .text = "greeting()" },
        .{ .fact = .{ .method = "same-container name match" } },
    );
    _ = try graph.addRelationship(
        .{ .kind = .calls, .source = greet, .target = .{ .designator = "println" } },
        frontend,
        .{ .unit = unit, .range = testRange(31, 40), .text = "println()" },
        .{ .unresolved = .{ .missing = .target_entity, .explanation = "not in fixture scope" } },
    );

    var snapshot = try graph.publish();
    defer snapshot.deinit();

    try testing.expectEqual(@as(usize, 1), snapshot.countEntities(.{ .kind = .repository }));
    try testing.expectEqual(@as(usize, 1), snapshot.countEntities(.{ .kind = .file }));
    try testing.expectEqual(@as(usize, 2), snapshot.countEntities(.{ .kind = .definition }));
    try testing.expectEqual(@as(usize, 1), snapshot.countUnresolvedAssertions());
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());

    // One occurrence recorded as a call answers the reference query once.
    try testing.expectEqual(@as(usize, 2), snapshot.countRelationships(.{
        .source = greet,
        .reference_query = true,
    }));
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .source = greet,
        .kind = .calls,
        .resolution = .fact,
    }));
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{
        .source = greet,
        .kind = .references,
    }));
}

test "a relationship to an entity the graph does not have is rejected" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    const greet = try addDefinition(&graph, unit, "a/A.java", "greet", testRange(0, 5));

    try testing.expectError(error.UnknownEntity, graph.addRelationship(
        .{ .kind = .calls, .source = greet, .target = .{ .entity = @enumFromInt(99) } },
        frontend,
        .{ .unit = unit, .range = testRange(0, 5), .text = "x()" },
        .{ .fact = .{ .method = "same-container name match" } },
    ));
    try testing.expectError(error.UnknownEntity, graph.addRelationship(
        .{ .kind = .calls, .source = @enumFromInt(99), .target = .{ .entity = greet } },
        frontend,
        .{ .unit = unit, .range = testRange(0, 5), .text = "x()" },
        .{ .fact = .{ .method = "same-container name match" } },
    ));
}

test "a relationship to a removed entity is rejected" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    const greet = try addDefinition(&graph, unit, "a/A.java", "greet", testRange(0, 5));
    const gone = try addDefinition(&graph, unit, "a/A.java", "gone", testRange(6, 10));

    try graph.removeEntity(gone);
    try testing.expectError(error.RemovedEntity, graph.addRelationship(
        .{ .kind = .calls, .source = greet, .target = .{ .entity = gone } },
        frontend,
        .{ .unit = unit, .range = testRange(0, 5), .text = "gone()" },
        .{ .fact = .{ .method = "same-container name match" } },
    ));
    try testing.expectError(error.RemovedEntity, graph.removeEntity(gone));
}

test "containment cannot point at an unresolved designator" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    const greet = try addDefinition(&graph, unit, "a/A.java", "greet", testRange(0, 5));

    try testing.expectError(error.UnresolvedContainment, graph.addRelationship(
        .{ .kind = .defines, .source = greet, .target = .{ .designator = "somewhere" } },
        frontend,
        .{ .unit = unit, .range = testRange(0, 5), .text = "somewhere" },
        .{ .unresolved = .{ .missing = .container_entity, .explanation = "unknown container" } },
    ));
}

test "an invalid resolution never reaches the graph" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    const greet = try addDefinition(&graph, unit, "a/A.java", "greet", testRange(0, 5));

    try testing.expectError(error.UnresolvedTargetPresentedAsFact, graph.addRelationship(
        .{ .kind = .calls, .source = greet, .target = .{ .designator = "println" } },
        frontend,
        .{ .unit = unit, .range = testRange(0, 5), .text = "println()" },
        .{ .fact = .{ .method = "guessed" } },
    ));
    try testing.expectError(error.MissingProducerName, graph.addRelationship(
        .{ .kind = .calls, .source = greet, .target = .{ .designator = "println" } },
        .{ .name = "", .version = "slice-001" },
        .{ .unit = unit, .range = testRange(0, 5), .text = "println()" },
        .{ .unresolved = .{ .missing = .target_entity, .explanation = "not in fixture scope" } },
    ));
}

test "a published snapshot does not observe later graph mutation" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    _ = try addDefinition(&graph, unit, "a/A.java", "greet", testRange(0, 5));

    var before = try graph.publish();
    defer before.deinit();

    _ = graph.beginRevision();
    _ = try addDefinition(&graph, unit, "a/A.java", "farewell", testRange(6, 15));

    var after = try graph.publish();
    defer after.deinit();

    try testing.expectEqual(@as(usize, 1), before.countEntities(.{ .kind = .definition }));
    try testing.expectEqual(@as(usize, 2), after.countEntities(.{ .kind = .definition }));
    try testing.expect(before.revision < after.revision);
}

test "publishing refuses a state whose assertions have lost an endpoint" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    const greet = try addDefinition(&graph, unit, "a/A.java", "greet", testRange(0, 5));
    const greeting = try addDefinition(&graph, unit, "a/A.java", "greeting", testRange(6, 14));
    _ = try graph.addRelationship(
        .{ .kind = .calls, .source = greet, .target = .{ .entity = greeting } },
        frontend,
        .{ .unit = unit, .range = testRange(20, 30), .text = "greeting()" },
        .{ .fact = .{ .method = "same-container name match" } },
    );

    try graph.removeEntity(greeting);
    try testing.expectError(error.DanglingAssertionEndpoint, graph.publish());
}

test "a source range is evidence, not identity" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    const greet = try addDefinition(&graph, unit, "a/A.java", "greet", testRange(0, 5));

    // Two definitions may legitimately report the same range; they stay
    // distinct entities, and neither id is derived from the range.
    const other = try addDefinition(&graph, unit, "a/A.java", "other", testRange(0, 5));
    try testing.expect(greet != other);

    // Moving the definition changes only the projection.
    _ = graph.beginRevision();
    try graph.refreshEntity(greet, .{
        .unit = unit,
        .range = testRange(400, 405),
        .text = "greet",
    }, .{ .namespace = "java", .labels = &.{} });

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    const moved = snapshot.entityById(greet).?;
    try testing.expectEqual(greet, moved.id);
    try testing.expectEqual(@as(u32, 400), moved.evidence.?.range.start_byte);
}

test "the source container's extent follows an edit" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");

    var before = try graph.publish();
    defer before.deinit();
    const file_before = before.findEntity(.{ .kind = .file }).?;
    try testing.expectEqual(@as(u32, 11), file_before.evidence.?.range.end_byte);
    try testing.expectEqual(@as(u32, 11), before.firstRelationship(.{
        .kind = .defines,
        .target = file_before.id,
    }).?.evidence.?.range.end_byte);

    _ = try graph.setSourceUnitBytes(unit, "class A {\n  void f() {}\n}\n");

    var after = try graph.publish();
    defer after.deinit();
    const file_after = after.findEntity(.{ .kind = .file }).?;

    // The source container is the same entity; only its projection moved.
    try testing.expectEqual(file_before.id, file_after.id);
    try testing.expectEqual(@as(u32, 26), file_after.evidence.?.range.end_byte);
    try testing.expectEqual(@as(u32, 3), file_after.evidence.?.range.end_row);

    // What source ingestion claims about the unit moved with it, rather than
    // continuing to describe the previous contents.
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{
        .kind = .defines,
        .target = file_after.id,
    }));
    try testing.expectEqual(@as(u32, 26), after.firstRelationship(.{
        .kind = .defines,
        .target = file_after.id,
    }).?.evidence.?.range.end_byte);
}

test "a unit is pending until it is analyzed and current afterwards" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");

    var pending = try graph.publish();
    defer pending.deinit();
    try testing.expectEqual(UnitAnalysis.pending, pending.unitAnalysis(unit).?);
    try testing.expectEqual(@as(usize, 1), pending.countUnits(.pending));

    _ = try addDefinition(&graph, unit, "a/A.java", "greet", testRange(0, 5));

    var current = try graph.publish();
    defer current.deinit();
    try testing.expectEqual(UnitAnalysis.current, current.unitAnalysis(unit).?);
    try testing.expectEqual(@as(usize, 1), current.countEntities(.{ .kind = .definition }));
}

test "a duplicate source unit path is rejected" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    _ = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    try testing.expectError(
        error.DuplicateSourceUnitPath,
        graph.addSourceUnit("a/A.java", .java, "class A {}\n"),
    );
}
