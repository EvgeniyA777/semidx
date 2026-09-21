//! Shared semantic model.
//!
//! These types encode the distinctions the architecture constitution treats as
//! product identity: entities rather than chunks, assertions that always carry
//! what produced them and how far they were resolved, and identity evidence
//! that is evidence for correspondence rather than an entity id.
//!
//! This module must not learn about parsers, languages' concrete syntax,
//! filesystem walking, or output formatting.

const std = @import("std");

/// Graph identity for a semantic entity.
///
/// Allocated by the graph. It is never derived from a byte offset, a text
/// range, a chunk boundary, or a frontend's own identifier, so moving or
/// reformatting source cannot change it.
pub const EntityId = enum(u32) {
    _,

    pub fn index(self: EntityId) usize {
        return @intFromEnum(self);
    }
};

/// Identity of a recorded assertion, used to talk about one claim.
pub const AssertionId = enum(u32) { _ };

/// Identity of one independently addressable source unit.
pub const SourceUnitId = enum(u32) {
    _,

    pub fn index(self: SourceUnitId) usize {
        return @intFromEnum(self);
    }
};

/// Languages the vertical slice has frontends for. This is fixture coverage,
/// not a published language roster.
pub const Language = enum {
    java,
    clojure,
    zig,

    pub fn tag(self: Language) []const u8 {
        return @tagName(self);
    }
};

/// Where in a source unit a claim was observed.
///
/// A range is a projection: it locates evidence for a claim. It is never an
/// identity, never an endpoint, and never a node.
pub const SourceRange = struct {
    start_byte: u32,
    end_byte: u32,
    start_row: u32,
    start_column: u32,
    end_row: u32,
    end_column: u32,

    pub fn eql(a: SourceRange, b: SourceRange) bool {
        return std.meta.eql(a, b);
    }
};

/// The source observation backing a claim.
pub const SourceEvidence = struct {
    unit: SourceUnitId,
    range: SourceRange,
    /// The source text the claim was read from.
    text: []const u8,
};

/// What produced an assertion.
pub const Producer = struct {
    name: []const u8,
    version: []const u8,
};

/// How far a claim was resolved. Consumers rely on this distinction, so the
/// set is closed for the slice and widening it is a requirements change.
pub const ResolutionCategory = enum { fact, unresolved, approximate };

/// Which required part of a claim a producer could not establish.
pub const MissingPart = enum {
    target_entity,
    container_entity,
    identity_correspondence,
};

pub const Resolution = union(ResolutionCategory) {
    /// Fully established. `method` records how.
    fact: struct { method: []const u8 },
    /// Part of the claim is established and a required part is not.
    unresolved: struct { missing: MissingPart, explanation: []const u8 },
    /// Heuristic, similarity-based, or confidence-based. The slice's frontends
    /// do not produce these; the category exists so that an approximate claim
    /// has somewhere to go that is not `fact`.
    approximate: struct { basis: []const u8, confidence: f32 },

    pub fn category(self: Resolution) ResolutionCategory {
        return std.meta.activeTag(self);
    }

    pub fn isFact(self: Resolution) bool {
        return self.category() == .fact;
    }
};

pub const RelationshipKind = enum {
    /// Direct containment: one source or program container immediately contains
    /// another entity. This does not by itself introduce a program definition.
    contains,
    /// Definition introduction: a container directly introduces a program
    /// definition.
    defines,
    /// One entity names or otherwise designates another.
    references,
    /// A reference that invokes the referenced definition.
    calls,

    /// Whether an occurrence of this kind answers a "all references" query.
    /// `calls` specializes `references`; one occurrence is recorded once and
    /// counted once, never added twice to infer a total.
    pub fn satisfiesReferenceQuery(self: RelationshipKind) bool {
        return switch (self) {
            .references, .calls => true,
            .contains, .defines => false,
        };
    }
};

/// A name read from source that the producer could not resolve to an entity.
///
/// It is a name in parts, not a run of source text
/// ([ADR 010](../../docs/adr/010_designator_is_a_structured_name.md)). Only a
/// frontend can say which part of what the source wrote is the name and which
/// is a scope in front of it, so both parts are recorded where they are read
/// and neither is derived later by splitting a string.
///
/// What the source wrote around the name — a receiver expression, an argument
/// list — is not here. It is `SourceEvidence.text`, with the range that locates
/// it.
pub const Designator = struct {
    /// The identifier that names the thing. Empty when the producer could read
    /// no identifier at all, such as a computed callee: the claim is still
    /// recorded with its evidence, and nothing can find it by name, which is
    /// the honest answer rather than a synthesized one.
    name: []const u8,
    /// The name the source wrote in front of `name`, recorded only where the
    /// producer knows that prefix names a scope — an import alias, a namespace,
    /// a type — and never where it is a value expression. Absent is the normal
    /// case and is absent, never an empty string.
    qualifier: ?[]const u8 = null,

    pub fn eql(a: Designator, b: Designator) bool {
        if (!std.mem.eql(u8, a.name, b.name)) return false;
        const left = a.qualifier orelse return b.qualifier == null;
        const right = b.qualifier orelse return false;
        return std.mem.eql(u8, left, right);
    }
};

/// A relationship endpoint.
///
/// `designator` is a name the producer could not resolve to an entity. It stays
/// a name: an unresolved target never becomes a node.
pub const Target = union(enum) {
    entity: EntityId,
    designator: Designator,
};

pub const RelationshipClaim = struct {
    kind: RelationshipKind,
    source: EntityId,
    target: Target,
};

pub const IdentityCorrespondence = struct {
    current: EntityId,
    previous: EntityId,
};

/// Anything the graph records.
pub const Claim = union(enum) {
    entity_exists: EntityId,
    relationship: RelationshipClaim,
    identity_correspondence: IdentityCorrespondence,
};

pub const Assertion = struct {
    id: AssertionId,
    claim: Claim,
    producer: Producer,
    /// Absent only for the existence of a source container that is not
    /// observed at a range inside a source unit, such as the repository root.
    /// Every relationship and every identity correspondence must carry it.
    evidence: ?SourceEvidence,
    resolution: Resolution,
    /// The graph revision that recorded this assertion.
    revision: u64,

    pub fn relationship(self: Assertion) ?RelationshipClaim {
        return switch (self.claim) {
            .relationship => |rel| rel,
            else => null,
        };
    }
};

/// A source unit's content identity.
///
/// SHA-256 rather than a fast 64-bit hash on purpose. This value decides "this
/// unit did not change, do not reanalyze it" and "this is the same unit under a
/// new path". A collision there is not a slow answer; it is a wrong graph with a
/// heuristic wearing the face of a fact.
pub const ContentId = [32]u8;

pub fn contentId(bytes: []const u8) ContentId {
    var out: ContentId = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &out, .{});
    return out;
}

pub fn sameContent(a: ContentId, b: ContentId) bool {
    return std.mem.eql(u8, &a, &b);
}

/// Evidence that a unit seen in one scan of a source tree is the unit seen in
/// the next. Like `IdentityEvidence`, it is evidence for correspondence and not
/// the identity itself: the graph allocates unit identity, and consults this to
/// decide whether a unit in the new scan continues one it already knows.
pub const UnitIdentityEvidence = struct {
    /// Where the unit is found. Strong evidence, because a path that survives a
    /// scan almost always belongs to the same unit — and weak on its own,
    /// because a unit that moved has a different one.
    path: []const u8,
    language: Language,
    /// What the unit contains. The evidence that survives a move.
    content: ContentId,
};

/// Where an entity belongs.
///
/// A source unit appears here by the identity the graph allocated for it, never
/// by its path. A path is where a unit is found today; making it the scope would
/// bake a location into identity, which is the same mistake as deriving identity
/// from a byte range, and it is what makes renaming a file destroy the identity
/// of everything inside it.
pub const Scope = union(enum) {
    /// The indexed source tree itself.
    repository,
    /// One source unit.
    unit: SourceUnitId,

    pub fn eql(a: Scope, b: Scope) bool {
        return std.meta.eql(a, b);
    }
};

/// Evidence that two observations describe the same semantic entity.
///
/// This is evidence, not an id: the graph allocates ids and consults this to
/// decide correspondence. A body edit leaves it unchanged; moving a definition
/// within its container leaves it unchanged, because no field is positional.
pub const IdentityEvidence = struct {
    /// The scope the entity belongs to, by allocated identity rather than by
    /// location. A rename moves a property of the unit and leaves this alone.
    scope: Scope,
    /// Absent for source containers that are not presented to analysis as one
    /// language, such as the repository root.
    language: ?Language,
    /// The frontend's role for the entity, such as "class" or "defn".
    role: []const u8,
    name: ?[]const u8,
    signature: ?[]const u8,
    /// Names of the containers the entity sits inside, outermost first.
    container_path: []const []const u8,

    pub fn corresponds(a: IdentityEvidence, b: IdentityEvidence) bool {
        if (a.language != b.language) return false;
        if (!a.scope.eql(b.scope)) return false;
        if (!std.mem.eql(u8, a.role, b.role)) return false;
        if (!optionalStringEql(a.name, b.name)) return false;
        if (!optionalStringEql(a.signature, b.signature)) return false;
        if (a.container_path.len != b.container_path.len) return false;
        for (a.container_path, b.container_path) |x, y| {
            if (!std.mem.eql(u8, x, y)) return false;
        }
        return true;
    }

    /// Weaker than `corresponds`: same scope, language, and role. Used to see
    /// that an entity was replaced rather than simply deleted, so that the
    /// replacement is reported as identity loss instead of silently.
    pub fn sameSlot(a: IdentityEvidence, b: IdentityEvidence) bool {
        if (a.language != b.language) return false;
        if (!a.scope.eql(b.scope)) return false;
        if (!std.mem.eql(u8, a.role, b.role)) return false;
        if (a.container_path.len != b.container_path.len) return false;
        for (a.container_path, b.container_path) |x, y| {
            if (!std.mem.eql(u8, x, y)) return false;
        }
        return true;
    }

    /// Same scope, language, role, and name under different containers: the
    /// shape a declaration takes when its container is renamed or it moves to
    /// another container. Like `sameSlot`, this is not correspondence. It only
    /// lets such a break be reported as identity loss with its replacement.
    pub fn sameNameElsewhere(a: IdentityEvidence, b: IdentityEvidence) bool {
        if (a.language != b.language) return false;
        if (!a.scope.eql(b.scope)) return false;
        if (!std.mem.eql(u8, a.role, b.role)) return false;
        const a_name = a.name orelse return false;
        const b_name = b.name orelse return false;
        if (!std.mem.eql(u8, a_name, b_name)) return false;
        if (a.container_path.len != b.container_path.len) return true;
        for (a.container_path, b.container_path) |x, y| {
            if (!std.mem.eql(u8, x, y)) return true;
        }
        return false;
    }
};

fn optionalStringEql(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return std.mem.eql(u8, a.?, b.?);
}

pub const ExtensionLabel = struct {
    key: []const u8,
    value: []const u8,
};

/// Language-specific meaning that the shared core does not own.
///
/// A frontend puts constructs here instead of inventing a shared-core kind for
/// them, so a second language family cannot flatten the core into the first
/// one's vocabulary.
pub const ExtensionPayload = struct {
    namespace: []const u8,
    labels: []const ExtensionLabel,

    pub const empty: ExtensionPayload = .{ .namespace = "", .labels = &.{} };

    pub fn get(self: ExtensionPayload, key: []const u8) ?[]const u8 {
        for (self.labels) |label| {
            if (std.mem.eql(u8, label.key, key)) return label.value;
        }
        return null;
    }
};

/// Whether a claim was established about the current contents of the source
/// unit it was observed in.
///
/// This is a different axis from `Resolution`, and collapsing the two would be
/// a lie in both directions. A fully resolved fact about source that has since
/// changed is still a fact about what its producer read, and it is still not
/// current. An unresolved assertion about the contents on disk right now is
/// current, and still unresolved.
pub const Freshness = enum { current, stale };

pub const EntityKind = enum { repository, file, definition };

pub const Entity = struct {
    id: EntityId,
    kind: EntityKind,
    identity: IdentityEvidence,
    /// Absent for entities with no source range of their own, such as the
    /// repository root.
    evidence: ?SourceEvidence,
    extension: ExtensionPayload,
    created_revision: u64,
    /// The revision at which this entity's source evidence was last
    /// established. A later analysis that establishes correspondence moves it;
    /// `created_revision` never moves, because the entity is the same entity.
    observed_revision: u64,
    removed_revision: ?u64,

    pub fn isLive(self: Entity) bool {
        return self.removed_revision == null;
    }
};

/// Why a consumer is not seeing assertions it might have expected. These stay
/// distinct so that "not analyzed" never reads as "nothing there".
pub const DiagnosticKind = enum {
    /// Analysis could not run: no parser, no grammar, unreadable source.
    analysis_unavailable,
    /// Analysis ran and failed.
    analysis_failed,
    /// The construct exists but is outside the frontend's declared coverage.
    unsupported_construct,
    /// Analysis ran, the coverage applies, and there is nothing there.
    confirmed_absence,
};

pub const Diagnostic = struct {
    kind: DiagnosticKind,
    unit: ?SourceUnitId,
    producer: Producer,
    message: []const u8,
    revision: u64,
};

pub const IdentityEventKind = enum {
    /// Correspondence established: the entity kept its id across the edit.
    preserved,
    /// No prior entity corresponded: a new id was allocated.
    created,
    /// A prior entity is gone and nothing took its place.
    removed,
    /// A prior entity was replaced by one whose correspondence could not be
    /// established. Recorded so the break is visible as a break.
    lost,
};

pub const IdentityEvent = struct {
    kind: IdentityEventKind,
    entity: EntityId,
    /// For `lost`, the entity that occupies the prior entity's slot.
    replacement: ?EntityId,
    reason: []const u8,
    revision: u64,
};

pub const ValidationError = error{
    MissingProducerName,
    MissingProducerVersion,
    MissingResolutionMethod,
    MissingResolutionExplanation,
    MissingApproximateBasis,
    ConfidenceOutOfRange,
    MissingEvidenceText,
    MissingRelationshipEvidence,
    UnresolvedTargetPresentedAsFact,
    ResolvedTargetMarkedUnresolved,
    MissingIdentityRole,
};

/// Reject an assertion that does not carry what produced it and how far it was
/// resolved, and reject the two ways a claim can misreport its own resolution.
///
/// This is the construction-time half of the exact/unresolved separation; the
/// graph re-checks it on insertion.
pub fn validateAssertion(
    claim: Claim,
    producer: Producer,
    evidence: ?SourceEvidence,
    resolution: Resolution,
) ValidationError!void {
    if (producer.name.len == 0) return error.MissingProducerName;
    if (producer.version.len == 0) return error.MissingProducerVersion;
    if (evidence) |observed| {
        if (observed.text.len == 0) return error.MissingEvidenceText;
    } else switch (claim) {
        .relationship, .identity_correspondence => return error.MissingRelationshipEvidence,
        .entity_exists => {},
    }

    switch (resolution) {
        .fact => |f| if (f.method.len == 0) return error.MissingResolutionMethod,
        .unresolved => |u| if (u.explanation.len == 0) return error.MissingResolutionExplanation,
        .approximate => |a| {
            if (a.basis.len == 0) return error.MissingApproximateBasis;
            if (!(a.confidence >= 0.0 and a.confidence <= 1.0)) return error.ConfidenceOutOfRange;
        },
    }

    switch (claim) {
        .relationship => |rel| switch (rel.target) {
            .designator => if (resolution.isFact()) return error.UnresolvedTargetPresentedAsFact,
            .entity => switch (resolution) {
                .unresolved => |u| if (u.missing == .target_entity) {
                    return error.ResolvedTargetMarkedUnresolved;
                },
                else => {},
            },
        },
        else => {},
    }
}

/// There is no scope check here. `Scope` is a union with no empty case, so a
/// missing scope is unrepresentable rather than rejected — which is the better
/// of the two, and is why the previous `MissingIdentityScope` error is gone.
pub fn validateIdentityEvidence(identity: IdentityEvidence) ValidationError!void {
    if (identity.role.len == 0) return error.MissingIdentityRole;
}

const testing = std.testing;

const test_unit: SourceUnitId = @enumFromInt(0);
const test_range: SourceRange = .{
    .start_byte = 10,
    .end_byte = 20,
    .start_row = 1,
    .start_column = 0,
    .end_row = 1,
    .end_column = 10,
};
const test_evidence: SourceEvidence = .{ .unit = test_unit, .range = test_range, .text = "greet()" };
const test_producer: Producer = .{ .name = "frontend.java", .version = "slice-001" };

fn relationshipTo(target: Target) Claim {
    return .{ .relationship = .{
        .kind = .calls,
        .source = @enumFromInt(0),
        .target = target,
    } };
}

test "an assertion without a producer is rejected" {
    try testing.expectError(error.MissingProducerName, validateAssertion(
        relationshipTo(.{ .entity = @enumFromInt(1) }),
        .{ .name = "", .version = "slice-001" },
        test_evidence,
        .{ .fact = .{ .method = "same-container name match" } },
    ));
    try testing.expectError(error.MissingProducerVersion, validateAssertion(
        relationshipTo(.{ .entity = @enumFromInt(1) }),
        .{ .name = "frontend.java", .version = "" },
        test_evidence,
        .{ .fact = .{ .method = "same-container name match" } },
    ));
}

test "an assertion without source evidence text is rejected" {
    try testing.expectError(error.MissingEvidenceText, validateAssertion(
        relationshipTo(.{ .entity = @enumFromInt(1) }),
        test_producer,
        .{ .unit = test_unit, .range = test_range, .text = "" },
        .{ .fact = .{ .method = "same-container name match" } },
    ));
}

test "a resolution without its explanation is rejected" {
    try testing.expectError(error.MissingResolutionMethod, validateAssertion(
        relationshipTo(.{ .entity = @enumFromInt(1) }),
        test_producer,
        test_evidence,
        .{ .fact = .{ .method = "" } },
    ));
    try testing.expectError(error.MissingResolutionExplanation, validateAssertion(
        relationshipTo(.{ .designator = .{ .name = "println" } }),
        test_producer,
        test_evidence,
        .{ .unresolved = .{ .missing = .target_entity, .explanation = "" } },
    ));
    try testing.expectError(error.MissingApproximateBasis, validateAssertion(
        relationshipTo(.{ .designator = .{ .name = "println" } }),
        test_producer,
        test_evidence,
        .{ .approximate = .{ .basis = "", .confidence = 0.5 } },
    ));
    try testing.expectError(error.ConfidenceOutOfRange, validateAssertion(
        relationshipTo(.{ .designator = .{ .name = "println" } }),
        test_producer,
        test_evidence,
        .{ .approximate = .{ .basis = "name similarity", .confidence = 1.5 } },
    ));
}

test "an unresolved target cannot be presented as a fact" {
    try testing.expectError(error.UnresolvedTargetPresentedAsFact, validateAssertion(
        relationshipTo(.{ .designator = .{ .name = "println", .qualifier = "System.out" } }),
        test_producer,
        test_evidence,
        .{ .fact = .{ .method = "same-container name match" } },
    ));
}

test "a resolved target cannot claim its target is missing" {
    try testing.expectError(error.ResolvedTargetMarkedUnresolved, validateAssertion(
        relationshipTo(.{ .entity = @enumFromInt(1) }),
        test_producer,
        test_evidence,
        .{ .unresolved = .{ .missing = .target_entity, .explanation = "not in fixture scope" } },
    ));
}

test "an approximate assertion is neither a fact nor unresolved" {
    const resolution: Resolution = .{ .approximate = .{ .basis = "name similarity", .confidence = 0.4 } };
    try validateAssertion(
        relationshipTo(.{ .designator = .{ .name = "println" } }),
        test_producer,
        test_evidence,
        resolution,
    );
    try testing.expectEqual(ResolutionCategory.approximate, resolution.category());
    try testing.expect(!resolution.isFact());
}

test "calls answer a reference query and containment does not" {
    try testing.expect(RelationshipKind.calls.satisfiesReferenceQuery());
    try testing.expect(RelationshipKind.references.satisfiesReferenceQuery());
    try testing.expect(!RelationshipKind.contains.satisfiesReferenceQuery());
    try testing.expect(!RelationshipKind.defines.satisfiesReferenceQuery());
}

test "identity evidence ignores source position" {
    const containers = [_][]const u8{"Greeter"};
    const a: IdentityEvidence = .{
        .scope = .{ .unit = test_unit },
        .language = .java,
        .role = "method",
        .name = "greet",
        .signature = "greet()",
        .container_path = &containers,
    };
    var b = a;
    try testing.expect(a.corresponds(b));

    // Identity evidence carries no range, so a move cannot change it. The
    // ranges below differ; correspondence is unaffected.
    const moved_evidence: SourceEvidence = .{
        .unit = test_unit,
        .range = .{
            .start_byte = 500,
            .end_byte = 540,
            .start_row = 40,
            .start_column = 4,
            .end_row = 42,
            .end_column = 5,
        },
        .text = "greet()",
    };
    try testing.expect(!moved_evidence.range.eql(test_range));
    try testing.expect(a.corresponds(b));

    b.name = "salutation";
    try testing.expect(!a.corresponds(b));
    // A rename still occupies the same slot, which is how the break is seen as
    // a break rather than as an unrelated delete and create.
    try testing.expect(a.sameSlot(b));
}

test "identity evidence is not an entity id" {
    // Two entities may carry equal evidence in different scopes and stay
    // distinct; nothing derives an id from these fields.
    const a: IdentityEvidence = .{
        .scope = .{ .unit = test_unit },
        .language = .java,
        .role = "method",
        .name = "greet",
        .signature = "greet()",
        .container_path = &.{},
    };
    var b = a;
    b.scope = .{ .unit = @enumFromInt(1) };
    try testing.expect(!a.corresponds(b));
    try testing.expect(!a.sameSlot(b));
}

test "a scope is an allocated identity, not a location" {
    // Two units may sit at the same relative path under different roots. They
    // are different units, so entities in them do not correspond, and no
    // rewriting of paths can make them.
    const first: Scope = .{ .unit = @enumFromInt(0) };
    const second: Scope = .{ .unit = @enumFromInt(1) };
    try testing.expect(!first.eql(second));
    try testing.expect(first.eql(.{ .unit = @enumFromInt(0) }));
    try testing.expect(!first.eql(.repository));
    const root: Scope = .repository;
    try testing.expect(root.eql(.repository));
}

test "identity evidence must name a role" {
    try testing.expectError(error.MissingIdentityRole, validateIdentityEvidence(.{
        .scope = .{ .unit = test_unit },
        .language = .clojure,
        .role = "",
        .name = "greet",
        .signature = null,
        .container_path = &.{},
    }));
    try validateIdentityEvidence(.{
        .scope = .repository,
        .language = null,
        .role = "repository",
        .name = null,
        .signature = null,
        .container_path = &.{},
    });
}

test "a relationship without source evidence is rejected" {
    try testing.expectError(error.MissingRelationshipEvidence, validateAssertion(
        relationshipTo(.{ .designator = .{ .name = "println" } }),
        test_producer,
        null,
        .{ .unresolved = .{ .missing = .target_entity, .explanation = "not in fixture scope" } },
    ));
    // A source container that is not observed at a range inside a source unit
    // is the one claim allowed to omit evidence.
    try validateAssertion(
        .{ .entity_exists = @enumFromInt(0) },
        .{ .name = "source-ingestion", .version = "slice-001" },
        null,
        .{ .fact = .{ .method = "indexed source tree root" } },
    );
}
