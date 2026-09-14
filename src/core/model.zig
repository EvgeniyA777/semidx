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
    /// Direct containment: a container introduces a definition.
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
            .defines => false,
        };
    }
};

/// A relationship endpoint.
///
/// `designator` is a name read from source that the producer could not resolve
/// to an entity. It stays a string: an unresolved target never becomes a node.
pub const Target = union(enum) {
    entity: EntityId,
    designator: []const u8,
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

/// Evidence that two observations describe the same semantic entity.
///
/// This is evidence, not an id: the graph allocates ids and consults this to
/// decide correspondence. A body edit leaves it unchanged; moving a definition
/// within its container leaves it unchanged, because no field is positional.
pub const IdentityEvidence = struct {
    /// The source scope the entity belongs to, such as a source unit path.
    scope: []const u8,
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
        if (!std.mem.eql(u8, a.scope, b.scope)) return false;
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
        if (!std.mem.eql(u8, a.scope, b.scope)) return false;
        if (!std.mem.eql(u8, a.role, b.role)) return false;
        if (a.container_path.len != b.container_path.len) return false;
        for (a.container_path, b.container_path) |x, y| {
            if (!std.mem.eql(u8, x, y)) return false;
        }
        return true;
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
    MissingIdentityScope,
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

pub fn validateIdentityEvidence(identity: IdentityEvidence) ValidationError!void {
    if (identity.scope.len == 0) return error.MissingIdentityScope;
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
        relationshipTo(.{ .designator = "println" }),
        test_producer,
        test_evidence,
        .{ .unresolved = .{ .missing = .target_entity, .explanation = "" } },
    ));
    try testing.expectError(error.MissingApproximateBasis, validateAssertion(
        relationshipTo(.{ .designator = "println" }),
        test_producer,
        test_evidence,
        .{ .approximate = .{ .basis = "", .confidence = 0.5 } },
    ));
    try testing.expectError(error.ConfidenceOutOfRange, validateAssertion(
        relationshipTo(.{ .designator = "println" }),
        test_producer,
        test_evidence,
        .{ .approximate = .{ .basis = "name similarity", .confidence = 1.5 } },
    ));
}

test "an unresolved target cannot be presented as a fact" {
    try testing.expectError(error.UnresolvedTargetPresentedAsFact, validateAssertion(
        relationshipTo(.{ .designator = "System.out.println" }),
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
        relationshipTo(.{ .designator = "println" }),
        test_producer,
        test_evidence,
        resolution,
    );
    try testing.expectEqual(ResolutionCategory.approximate, resolution.category());
    try testing.expect(!resolution.isFact());
}

test "calls answer a reference query and defines does not" {
    try testing.expect(RelationshipKind.calls.satisfiesReferenceQuery());
    try testing.expect(RelationshipKind.references.satisfiesReferenceQuery());
    try testing.expect(!RelationshipKind.defines.satisfiesReferenceQuery());
}

test "identity evidence ignores source position" {
    const containers = [_][]const u8{"Greeter"};
    const a: IdentityEvidence = .{
        .scope = "java/Greeter.java",
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
        .scope = "java/Greeter.java",
        .language = .java,
        .role = "method",
        .name = "greet",
        .signature = "greet()",
        .container_path = &.{},
    };
    var b = a;
    b.scope = "java/Other.java";
    try testing.expect(!a.corresponds(b));
    try testing.expect(!a.sameSlot(b));
}

test "identity evidence must name a scope and a role" {
    try testing.expectError(error.MissingIdentityScope, validateIdentityEvidence(.{
        .scope = "",
        .language = .clojure,
        .role = "defn",
        .name = "greet",
        .signature = null,
        .container_path = &.{},
    }));
    try testing.expectError(error.MissingIdentityRole, validateIdentityEvidence(.{
        .scope = "clojure/greeter.clj",
        .language = .clojure,
        .role = "",
        .name = "greet",
        .signature = null,
        .container_path = &.{},
    }));
}

test "a relationship without source evidence is rejected" {
    try testing.expectError(error.MissingRelationshipEvidence, validateAssertion(
        relationshipTo(.{ .designator = "println" }),
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
