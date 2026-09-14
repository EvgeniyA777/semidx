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
    DefinitionIntroductionTargetMustBeDefinition,
    DuplicateSourceUnitPath,
    UnknownSourceUnit,
    RemovedSourceUnit,
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
    /// Content identity of those contents, so the next scan can be reconciled
    /// against this one without rereading what the graph already holds.
    content: model.ContentId,
    /// The `file` entity for this unit.
    entity: EntityId,
    /// The revision at which these contents were established.
    content_revision: u64,
    /// The revision at which a frontend last analyzed this unit successfully,
    /// or 0 if it never has.
    analysis_revision: u64,
    /// Set when the unit leaves the index. The record stays behind so its
    /// identity is never handed to a later unit.
    removed_revision: ?u64,

    pub fn isLive(self: SourceUnitRecord) bool {
        return self.removed_revision == null;
    }

    pub fn analysis(self: SourceUnitRecord) UnitAnalysis {
        if (self.analysis_revision == 0) return .pending;
        return if (self.analysis_revision >= self.content_revision) .current else .stale;
    }

    /// What a later scan compares against to decide whether it is seeing this
    /// same unit.
    pub fn identity(self: SourceUnitRecord) model.UnitIdentityEvidence {
        return .{ .path = self.path, .language = self.language, .content = self.content };
    }

    pub fn view(self: SourceUnitRecord) SourceUnitView {
        return .{
            .id = self.id,
            .path = self.path,
            .language = self.language,
            .entity = self.entity,
            .content_revision = self.content_revision,
            .analysis_revision = self.analysis_revision,
        };
    }
};

/// The part of a source unit a consumer observes. It carries no contents: a
/// snapshot answers questions about the graph, not about source text.
pub const SourceUnitView = struct {
    id: SourceUnitId,
    /// Where the unit is found now. A property, not its identity: a rename
    /// changes this and leaves the unit, its contents, and everything defined
    /// inside it alone.
    path: []const u8,
    language: model.Language,
    /// The source container entity for this unit. A consumer that found a unit
    /// by path reaches its entities from here, rather than by matching a path
    /// against identity evidence.
    entity: EntityId,
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
    /// Assertions not observed in any source unit. Today that is the existence
    /// of the repository root and nothing else.
    assertions: std.ArrayList(model.Assertion),
    /// Assertions observed in a source unit, bucketed by it.
    ///
    /// Bucketing is not an optimization detail: withdrawing one unit's analysis
    /// is the single most frequent thing ingestion does, and finding those
    /// assertions by sweeping every assertion in the repository is how "reanalyze
    /// the affected region" quietly becomes "touch the whole graph on every
    /// keystroke".
    unit_assertions: std.ArrayList(std.ArrayList(model.Assertion)),
    diagnostics: std.ArrayList(model.Diagnostic),
    unit_diagnostics: std.ArrayList(std.ArrayList(model.Diagnostic)),
    /// Definitions introduced in each unit, for the same reason.
    unit_definitions: std.ArrayList(std.ArrayList(EntityId)),
    identity_events: std.ArrayList(model.IdentityEvent),
    units: std.ArrayList(SourceUnitRecord),
    /// Current path to unit, so registering or moving a unit does not scan.
    unit_paths: std.StringHashMapUnmanaged(SourceUnitId),
    /// Stored records examined while applying a change scoped to one source
    /// unit.
    ///
    /// This is the number Stage 4's guard watches. Changing one unit must cost
    /// the same whatever else the repository holds; if it grows with the graph,
    /// a lookup that should be keyed has become a sweep.
    unit_work: usize,

    pub fn init(gpa: Allocator, repository_path: []const u8) GraphError!Graph {
        var self: Graph = .{
            .gpa = gpa,
            .pool = StringPool.init(gpa),
            .revision = 1,
            .next_assertion = 0,
            .repository = @enumFromInt(0),
            .entities = .empty,
            .assertions = .empty,
            .unit_assertions = .empty,
            .diagnostics = .empty,
            .unit_diagnostics = .empty,
            .unit_definitions = .empty,
            .identity_events = .empty,
            .units = .empty,
            .unit_paths = .empty,
            .unit_work = 0,
        };
        errdefer self.deinit();

        self.repository = try self.addEntity(.{
            .kind = .repository,
            .identity = .{
                .scope = .repository,
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
        for (self.unit_assertions.items) |*bucket| bucket.deinit(self.gpa);
        self.unit_assertions.deinit(self.gpa);
        for (self.unit_diagnostics.items) |*bucket| bucket.deinit(self.gpa);
        self.unit_diagnostics.deinit(self.gpa);
        for (self.unit_definitions.items) |*bucket| bucket.deinit(self.gpa);
        self.unit_definitions.deinit(self.gpa);
        self.unit_paths.deinit(self.gpa);
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

        // The source container's identity is the unit, and nothing else. Its
        // name is deliberately absent: a path is the one property a rename
        // changes, so naming the entity by it would make every rename an
        // identity break for the container itself.
        const file_entity = self.addEntity(.{
            .kind = .file,
            .identity = .{
                .scope = .{ .unit = id },
                .language = language,
                .role = "file",
                .name = null,
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

        try self.unit_assertions.append(self.gpa, .empty);
        try self.unit_diagnostics.append(self.gpa, .empty);
        try self.unit_definitions.append(self.gpa, .empty);
        try self.unit_paths.put(self.gpa, interned_path, id);

        self.units.append(self.gpa, .{
            .id = id,
            .path = interned_path,
            .language = language,
            .bytes = owned_bytes,
            .content = model.contentId(owned_bytes),
            .entity = file_entity,
            .content_revision = self.revision,
            .analysis_revision = 0,
            .removed_revision = null,
        }) catch |err| {
            self.gpa.free(owned_bytes);
            return err;
        };

        try self.recordUnitIngestion(self.units.items[id.index()]);
        try self.addIdentityEvent(
            .created,
            file_entity,
            null,
            "a source unit appeared that no known unit corresponded to",
        );
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
            record.content = model.contentId(owned);
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
            .{ .kind = .contains, .source = self.repository, .target = .{ .entity = record.entity } },
            ingestion,
            evidence,
            .{ .fact = .{ .method = "source unit belongs to the indexed source tree" } },
        );
    }

    /// Moves a unit to a new path.
    ///
    /// Nothing about the unit's identity, its contents, or the entities defined
    /// inside it changes, because none of them is derived from the path. What
    /// changes is one property and the evidence that carries it, so the unit
    /// does not go stale and no reanalysis is owed.
    pub fn setSourceUnitPath(
        self: *Graph,
        id: SourceUnitId,
        path: []const u8,
    ) GraphError!u64 {
        const index = id.index();
        if (index >= self.units.items.len) return error.UnknownSourceUnit;
        if (!self.units.items[index].isLive()) return error.RemovedSourceUnit;
        if (self.unitByPath(path)) |occupant| {
            if (occupant != id) return error.DuplicateSourceUnitPath;
        }

        const revision = self.beginRevision();
        const interned = try self.pool.intern(path);
        _ = self.unit_paths.remove(self.units.items[index].path);
        try self.unit_paths.put(self.gpa, interned, id);
        self.units.items[index].path = interned;

        const record = self.units.items[index];
        try self.refreshEntity(record.entity, .{
            .unit = record.id,
            .range = wholeUnitRange(record.bytes),
            .text = interned,
        }, model.ExtensionPayload.empty);

        self.dropIngestionAssertionsForUnit(id);
        try self.recordUnitIngestion(record);

        // A move is a correspondence claim, and it is an established one:
        // identical contents under a new path is exact resolution of "the same
        // unit", not a similarity score. It is recorded so a consumer can see
        // that the graph decided a file moved rather than inferring it.
        try self.addIdentityEvent(
            .preserved,
            record.entity,
            null,
            "the same contents appeared under a new path",
        );
        _ = try self.addAssertion(
            .{ .identity_correspondence = .{ .current = record.entity, .previous = record.entity } },
            reconciler,
            .{
                .unit = record.id,
                .range = wholeUnitRange(record.bytes),
                .text = interned,
            },
            .{ .fact = .{ .method = "identical content under a new path" } },
        );
        return revision;
    }

    /// Takes a unit out of the index.
    ///
    /// Its entities are removed and its assertions withdrawn, each with a
    /// recorded identity event: a definition that left with its file must be
    /// observable as having left, not simply missing. The unit record stays
    /// behind tombstoned, so its identity is never reused.
    pub fn removeSourceUnit(self: *Graph, id: SourceUnitId) GraphError!void {
        const index = id.index();
        if (index >= self.units.items.len) return error.UnknownSourceUnit;
        if (!self.units.items[index].isLive()) return error.RemovedSourceUnit;

        const revision = self.beginRevision();
        const file_entity = self.units.items[index].entity;
        _ = self.unit_paths.remove(self.units.items[index].path);
        self.units.items[index].removed_revision = revision;

        var definitions: std.ArrayList(EntityId) = .empty;
        defer definitions.deinit(self.gpa);
        try self.definitionsInUnit(id, &definitions, self.gpa);

        self.dropAssertionsForUnit(id);
        self.dropIngestionAssertionsForUnit(id);
        self.dropDiagnosticsForUnit(id);

        for (definitions.items) |entity_id| {
            try self.addIdentityEvent(
                .removed,
                entity_id,
                null,
                "the source unit that introduced it is no longer indexed",
            );
            try self.removeEntity(entity_id);
        }

        try self.addIdentityEvent(
            .removed,
            file_entity,
            null,
            "the source unit is no longer indexed",
        );
        try self.removeEntity(file_entity);
    }

    /// Records that a frontend has analyzed this unit's current contents.
    pub fn markAnalyzed(self: *Graph, id: SourceUnitId) GraphError!void {
        const record = self.unitMut(id) orelse return error.UnknownSourceUnit;
        record.analysis_revision = self.revision;
    }

    pub fn unitByPath(self: *Graph, path: []const u8) ?SourceUnitId {
        // Counted so that the Stage 4 guard notices if this ever goes back to
        // walking the unit table: one examined record here, not one per unit.
        self.unit_work += 1;
        return self.unit_paths.get(path);
    }

    /// Live units, in identity order, as correspondence evidence for a scan.
    pub fn knownUnits(
        self: *const Graph,
        out: *std.ArrayList(SourceUnitRecord),
        gpa: Allocator,
    ) Allocator.Error!void {
        for (self.units.items) |record| {
            if (record.isLive()) try out.append(gpa, record);
        }
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
        if (!record.isLive()) return null;
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

        if (spec.kind == .definition) {
            if (evidence) |observed| {
                if (self.definitionBucket(observed.unit)) |bucket| {
                    try bucket.append(self.gpa, id);
                }
            }
        }
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

        if (record.kind == .definition) {
            if (record.evidence) |observed| {
                if (self.definitionBucket(observed.unit)) |bucket| {
                    self.unit_work += bucket.items.len;
                    for (bucket.items, 0..) |entity_id, index| {
                        if (entity_id != id) continue;
                        _ = bucket.orderedRemove(index);
                        break;
                    }
                }
            }
        }
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

    /// Live definitions introduced in the given unit. This is the affected
    /// semantic region of an edit to that unit, and reading it must cost what
    /// the unit holds rather than what the repository holds.
    pub fn definitionsInUnit(
        self: *Graph,
        id: SourceUnitId,
        out: *std.ArrayList(EntityId),
        gpa: Allocator,
    ) Allocator.Error!void {
        const bucket = self.definitionBucket(id) orelse return;
        self.unit_work += bucket.items.len;
        for (bucket.items) |entity_id| {
            if (self.entities.items[entity_id.index()].isLive()) try out.append(gpa, entity_id);
        }
    }

    fn definitionBucket(self: *Graph, id: SourceUnitId) ?*std.ArrayList(EntityId) {
        const index = id.index();
        if (index >= self.unit_definitions.items.len) return null;
        return &self.unit_definitions.items[index];
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

        const bucket = if (evidence) |observed| self.assertionBucket(observed.unit) else null;
        try (bucket orelse &self.assertions).append(self.gpa, .{
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

    fn assertionBucket(self: *Graph, id: SourceUnitId) ?*std.ArrayList(model.Assertion) {
        const index = id.index();
        if (index >= self.unit_assertions.items.len) return null;
        return &self.unit_assertions.items[index];
    }

    fn diagnosticBucket(self: *Graph, id: SourceUnitId) ?*std.ArrayList(model.Diagnostic) {
        const index = id.index();
        if (index >= self.unit_diagnostics.items.len) return null;
        return &self.unit_diagnostics.items[index];
    }

    /// Drops every assertion observed in one source unit. Used before a unit's
    /// assertions are re-derived; assertions from other units are untouched, and
    /// not even looked at.
    pub fn dropAssertionsForUnit(self: *Graph, id: SourceUnitId) void {
        // What source ingestion established about the unit itself survives an
        // edit to the unit's contents. Only analysis derived from those
        // contents is re-run.
        self.filterBucket(id, true);
    }

    /// Drops what source ingestion previously claimed about one unit, so the
    /// claims can be re-established against its new contents.
    pub fn dropIngestionAssertionsForUnit(self: *Graph, id: SourceUnitId) void {
        self.filterBucket(id, false);
    }

    fn filterBucket(self: *Graph, id: SourceUnitId, keep_ingestion: bool) void {
        const bucket = self.assertionBucket(id) orelse return;
        self.unit_work += bucket.items.len;
        var write: usize = 0;
        for (bucket.items) |assertion| {
            const from_ingestion = std.mem.eql(u8, assertion.producer.name, ingestion.name);
            if (from_ingestion == keep_ingestion) {
                bucket.items[write] = assertion;
                write += 1;
            }
        }
        bucket.shrinkRetainingCapacity(write);
    }

    /// Drops what source ingestion said about the tree as a whole, so a rescan
    /// replaces the previous scan's account rather than accumulating beside it.
    pub fn dropScanDiagnostics(self: *Graph) void {
        var write: usize = 0;
        for (self.diagnostics.items) |diagnostic| {
            if (!std.mem.eql(u8, diagnostic.producer.name, ingestion.name)) {
                self.diagnostics.items[write] = diagnostic;
                write += 1;
            }
        }
        self.diagnostics.shrinkRetainingCapacity(write);
    }

    pub fn dropDiagnosticsForUnit(self: *Graph, id: SourceUnitId) void {
        const bucket = self.diagnosticBucket(id) orelse return;
        self.unit_work += bucket.items.len;
        bucket.clearRetainingCapacity();
    }

    pub fn addDiagnostic(
        self: *Graph,
        kind: model.DiagnosticKind,
        id: ?SourceUnitId,
        producer: model.Producer,
        message: []const u8,
    ) GraphError!void {
        const bucket = if (id) |unit_id| self.diagnosticBucket(unit_id) else null;
        try (bucket orelse &self.diagnostics).append(self.gpa, .{
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
        for (self.units.items) |record| {
            if (record.isLive()) try units.append(self.gpa, record.view());
        }

        // Publication is where the graph is walked in full, deliberately: a
        // consumer observes one complete state. Assertions come out grouped by
        // the unit they were observed in, which is a stable order, not the
        // order they happened to be recorded in across units.
        var assertions: std.ArrayList(model.Assertion) = .empty;
        errdefer assertions.deinit(self.gpa);
        try assertions.appendSlice(self.gpa, self.assertions.items);
        for (self.unit_assertions.items) |bucket| {
            try assertions.appendSlice(self.gpa, bucket.items);
        }

        var diagnostics: std.ArrayList(model.Diagnostic) = .empty;
        errdefer diagnostics.deinit(self.gpa);
        try diagnostics.appendSlice(self.gpa, self.diagnostics.items);
        for (self.unit_diagnostics.items) |bucket| {
            try diagnostics.appendSlice(self.gpa, bucket.items);
        }

        return .{
            .gpa = self.gpa,
            .revision = self.revision,
            .entities = try entities.toOwnedSlice(self.gpa),
            .assertions = try assertions.toOwnedSlice(self.gpa),
            .diagnostics = try diagnostics.toOwnedSlice(self.gpa),
            .identity_events = try self.gpa.dupe(model.IdentityEvent, self.identity_events.items),
            .units = try units.toOwnedSlice(self.gpa),
        };
    }

    /// Refuses to publish a state whose assertions point at entities that are
    /// not there, rather than letting a query quietly skip them.
    pub fn checkInvariants(self: *const Graph) GraphError!void {
        try self.checkAssertions(self.assertions.items);
        for (self.unit_assertions.items) |bucket| try self.checkAssertions(bucket.items);
    }

    fn checkAssertions(self: *const Graph, assertions: []const model.Assertion) GraphError!void {
        for (assertions) |assertion| {
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
                        if (rel.kind == .defines and target.kind != .definition) {
                            return error.DefinitionIntroductionTargetMustBeDefinition;
                        }
                    },
                    .designator => if (rel.kind == .contains or rel.kind == .defines) {
                        return error.UnresolvedContainment;
                    },
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
            .scope = value.scope,
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
        /// Matches by allocated scope.
        scope: ?model.Scope = null,
        /// Matches by where a unit is found right now. A convenience over
        /// `scope`, resolved through the unit registry rather than by comparing
        /// a path against identity evidence — which is exactly what identity
        /// evidence no longer holds.
        path: ?[]const u8 = null,
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
        /// A `path` filter resolved once. Resolving it per candidate entity
        /// would make every path query cost units times entities.
        path_scope: ?model.Scope,
        /// Set when a `path` filter names a unit the snapshot does not hold, so
        /// the iterator yields nothing rather than matching everything.
        empty: bool,

        pub fn next(self: *EntityIterator) ?model.Entity {
            if (self.empty) return null;
            while (self.index < self.snapshot.entities.len) {
                const entity = self.snapshot.entities[self.index];
                self.index += 1;
                if (self.filter.kind) |kind| {
                    if (entity.kind != kind) continue;
                }
                if (self.filter.scope) |scope| {
                    if (!entity.identity.scope.eql(scope)) continue;
                }
                if (self.path_scope) |scope| {
                    if (!entity.identity.scope.eql(scope)) continue;
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
        var path_scope: ?model.Scope = null;
        var empty = false;
        if (filter.path) |path| {
            if (self.unitByPath(path)) |view| {
                path_scope = .{ .unit = view.id };
            } else {
                empty = true;
            }
        }
        return .{
            .snapshot = self,
            .index = 0,
            .filter = filter,
            .path_scope = path_scope,
            .empty = empty,
        };
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

    /// Looks a definition up by the unit it is currently found in and its name.
    /// It is a query convenience, not an identity: the answer is an entity that
    /// carries its own id, and the path is resolved through the unit registry.
    /// Stale definitions are excluded, like every other query.
    pub fn findDefinition(self: *const Snapshot, path: []const u8, name: []const u8) ?model.Entity {
        return self.findEntity(.{ .kind = .definition, .path = path, .name = name });
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

    /// The most recent thing that happened to an entity's identity, whenever it
    /// happened. Asking by revision requires the caller to know which revision a
    /// multi-step operation recorded it in, which is exactly the kind of
    /// coupling a query should not need.
    pub fn lastIdentityEvent(self: Snapshot, id: EntityId) ?model.IdentityEvent {
        var found: ?model.IdentityEvent = null;
        for (self.identity_events) |event| {
            if (event.entity != id) continue;
            if (found == null or event.revision >= found.?.revision) found = event;
        }
        return found;
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
    name: []const u8,
    range: model.SourceRange,
) !EntityId {
    const evidence: model.SourceEvidence = .{ .unit = unit, .range = range, .text = name };
    const id = try graph.addEntity(.{
        .kind = .definition,
        .identity = .{
            .scope = .{ .unit = unit },
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
    const greet = try addDefinition(&graph, unit, "greet", testRange(0, 5));
    const greeting = try addDefinition(&graph, unit, "greeting", testRange(6, 14));

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
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .source = graph.repository,
        .kind = .contains,
    }));
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{
        .source = graph.repository,
        .kind = .defines,
    }));
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
    const greet = try addDefinition(&graph, unit, "greet", testRange(0, 5));

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
    const greet = try addDefinition(&graph, unit, "greet", testRange(0, 5));
    const gone = try addDefinition(&graph, unit, "gone", testRange(6, 10));

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
    const greet = try addDefinition(&graph, unit, "greet", testRange(0, 5));

    try testing.expectError(error.UnresolvedContainment, graph.addRelationship(
        .{ .kind = .contains, .source = greet, .target = .{ .designator = "somewhere" } },
        frontend,
        .{ .unit = unit, .range = testRange(0, 5), .text = "somewhere" },
        .{ .unresolved = .{ .missing = .container_entity, .explanation = "unknown container" } },
    ));
}

test "definition introduction cannot target a source container" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    const file = graph.unit(unit).?.entity;

    try testing.expectError(error.DefinitionIntroductionTargetMustBeDefinition, graph.addRelationship(
        .{ .kind = .defines, .source = graph.repository, .target = .{ .entity = file } },
        frontend,
        .{ .unit = unit, .range = testRange(0, 5), .text = "a/A.java" },
        .{ .fact = .{ .method = "invalid mixed containment claim" } },
    ));
}

test "an invalid resolution never reaches the graph" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    const greet = try addDefinition(&graph, unit, "greet", testRange(0, 5));

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
    _ = try addDefinition(&graph, unit, "greet", testRange(0, 5));

    var before = try graph.publish();
    defer before.deinit();

    _ = graph.beginRevision();
    _ = try addDefinition(&graph, unit, "farewell", testRange(6, 15));

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
    const greet = try addDefinition(&graph, unit, "greet", testRange(0, 5));
    const greeting = try addDefinition(&graph, unit, "greeting", testRange(6, 14));
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
    const greet = try addDefinition(&graph, unit, "greet", testRange(0, 5));

    // Two definitions may legitimately report the same range; they stay
    // distinct entities, and neither id is derived from the range.
    const other = try addDefinition(&graph, unit, "other", testRange(0, 5));
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
        .kind = .contains,
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
        .kind = .contains,
        .target = file_after.id,
    }));
    try testing.expectEqual(@as(u32, 26), after.firstRelationship(.{
        .kind = .contains,
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

    _ = try addDefinition(&graph, unit, "greet", testRange(0, 5));

    var current = try graph.publish();
    defer current.deinit();
    try testing.expectEqual(UnitAnalysis.current, current.unitAnalysis(unit).?);
    try testing.expectEqual(@as(usize, 1), current.countEntities(.{ .kind = .definition }));
}

test "renaming a unit changes one property and nothing else" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    const greet = try addDefinition(&graph, unit, "greet", testRange(0, 5));
    const greeting = try addDefinition(&graph, unit, "greeting", testRange(6, 14));
    _ = try graph.addRelationship(
        .{ .kind = .calls, .source = greet, .target = .{ .entity = greeting } },
        frontend,
        .{ .unit = unit, .range = testRange(20, 30), .text = "greeting()" },
        .{ .fact = .{ .method = "same-container name match" } },
    );

    var before = try graph.publish();
    defer before.deinit();
    const file_before = before.unit(unit).?.entity;
    const relationships_before = before.countRelationships(.{ .source = greet });

    _ = try graph.setSourceUnitPath(unit, "b/Renamed.java");

    var after = try graph.publish();
    defer after.deinit();

    // The unit, its source container, and every definition inside it kept
    // their identity. Only the path moved.
    try testing.expectEqualStrings("b/Renamed.java", after.unit(unit).?.path);
    try testing.expectEqual(file_before, after.unit(unit).?.entity);
    try testing.expectEqual(greet, after.findDefinition("b/Renamed.java", "greet").?.id);
    try testing.expectEqual(greeting, after.findDefinition("b/Renamed.java", "greeting").?.id);
    try testing.expectEqual(relationships_before, after.countRelationships(.{ .source = greet }));

    // A rename is not a content change, so nothing went stale and no
    // reanalysis is owed.
    try testing.expectEqual(UnitAnalysis.current, after.unitAnalysis(unit).?);

    // The old path answers nothing, and what ingestion claims about the unit
    // carries the new one.
    try testing.expect(after.findDefinition("a/A.java", "greet") == null);
    try testing.expectEqualStrings(
        "b/Renamed.java",
        after.firstRelationship(.{ .kind = .contains, .target = file_before }).?.evidence.?.text,
    );
    try testing.expect(after.entityById(file_before).?.identity.name == null);
}

test "two units at the same relative path are different units" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    // Same relative path, different roots, modelled here as the two distinct
    // units an indexer would register for them.
    const first = try graph.addSourceUnit("one/demo/A.java", .java, "class A {}\n");
    const second = try graph.addSourceUnit("two/demo/A.java", .java, "class A {}\n");
    try testing.expect(first != second);

    const in_first = try addDefinition(&graph, first, "greet", testRange(0, 5));
    const in_second = try addDefinition(&graph, second, "greet", testRange(0, 5));
    try testing.expect(in_first != in_second);

    // Identical in every respect a consumer can name, and still not the same
    // entity, because the scope they carry is the unit rather than the path.
    const a = graph.entity(in_first).?.identity;
    const b = graph.entity(in_second).?.identity;
    try testing.expectEqualStrings(a.name.?, b.name.?);
    try testing.expect(!a.corresponds(b));
    try testing.expect(!a.sameSlot(b));

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try testing.expectEqual(in_first, snapshot.findDefinition("one/demo/A.java", "greet").?.id);
    try testing.expectEqual(in_second, snapshot.findDefinition("two/demo/A.java", "greet").?.id);
}

test "removing a unit removes what it introduced, visibly" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const going = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    const staying = try graph.addSourceUnit("b/B.java", .java, "class B {}\n");
    const greet = try addDefinition(&graph, going, "greet", testRange(0, 5));
    const other = try addDefinition(&graph, staying, "other", testRange(0, 5));

    var before = try graph.publish();
    defer before.deinit();
    const file_going = before.unit(going).?.entity;

    try graph.removeSourceUnit(going);

    var after = try graph.publish();
    defer after.deinit();

    try testing.expect(after.unit(going) == null);
    try testing.expect(after.entityById(greet) == null);
    try testing.expect(after.entityById(file_going) == null);
    try testing.expectEqual(@as(usize, 1), after.countEntities(.{ .kind = .file }));
    try testing.expectEqual(@as(usize, 0), after.countRelationships(.{ .target = file_going }));

    // The definition did not simply stop being mentioned; its departure is a
    // recorded identity event.
    const event = after.identityEventFor(greet, after.revision).?;
    try testing.expectEqual(model.IdentityEventKind.removed, event.kind);
    try testing.expect(event.replacement == null);

    // The other unit is untouched.
    try testing.expectEqual(other, after.findDefinition("b/B.java", "other").?.id);
    try testing.expectEqual(UnitAnalysis.current, after.unitAnalysis(staying).?);
}

test "a removed unit's identity is never handed to a later unit" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const first = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    try graph.removeSourceUnit(first);

    // The same path becomes available again, and gets a different unit.
    const second = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    try testing.expect(first != second);
    try testing.expectError(error.RemovedSourceUnit, graph.removeSourceUnit(first));
    try testing.expectError(error.RemovedSourceUnit, graph.setSourceUnitPath(first, "c/C.java"));

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try testing.expectEqual(second, snapshot.unitByPath("a/A.java").?.id);
}

test "a rename onto an occupied path is rejected" {
    var graph = try Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const first = try graph.addSourceUnit("a/A.java", .java, "class A {}\n");
    _ = try graph.addSourceUnit("b/B.java", .java, "class B {}\n");

    try testing.expectError(
        error.DuplicateSourceUnitPath,
        graph.setSourceUnitPath(first, "b/B.java"),
    );
    // Renaming a unit to the path it already has is not a conflict with itself.
    _ = try graph.setSourceUnitPath(first, "a/A.java");
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
