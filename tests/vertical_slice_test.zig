//! Fixture and edit-history tests for the vertical slice.
//!
//! Every expectation below is read from a published `Snapshot`. Nothing here
//! asserts against a frontend batch, a parse tree, or the developer command's
//! output, because none of those is the semantic authority.

const std = @import("std");
const build_options = @import("build_options");

const semidx = @import("semidx");
const core = @import("semidx_core");

const model = semidx.model;
const testing = std.testing;

const java_path = "java/Greeter.java";
const clojure_path = "clojure/greeter.clj";

fn loadFixture(gpa: std.mem.Allocator, relative: []const u8) ![]u8 {
    const path = try std.fs.path.join(gpa, &.{ build_options.fixtures_dir, relative });
    defer gpa.free(path);
    return std.Io.Dir.cwd().readFileAlloc(testing.io, path, gpa, .limited(1 << 20));
}

const Fixture = struct {
    index: semidx.Index,
    java_unit: model.SourceUnitId,
    clojure_unit: model.SourceUnitId,

    fn init(gpa: std.mem.Allocator) !Fixture {
        var index = try semidx.Index.init(gpa, build_options.fixtures_dir);
        errdefer index.deinit();

        const java_source = try loadFixture(gpa, java_path);
        defer gpa.free(java_source);
        const clojure_source = try loadFixture(gpa, clojure_path);
        defer gpa.free(clojure_source);

        const java_unit = try index.addUnit(java_path, .java, java_source);
        const clojure_unit = try index.addUnit(clojure_path, .clojure, clojure_source);

        return .{ .index = index, .java_unit = java_unit, .clojure_unit = clojure_unit };
    }

    fn deinit(self: *Fixture) void {
        self.index.deinit();
        self.* = undefined;
    }

    fn edit(self: *Fixture, unit: model.SourceUnitId, relative: []const u8) !semidx.reconcile.Outcome {
        const gpa = self.index.graph.gpa;
        const source = try loadFixture(gpa, relative);
        defer gpa.free(source);
        return self.index.applyEdit(unit, source);
    }
};

// -- Stage 5: Java fixture coverage -----------------------------------------

test "the java fixture yields the expected entities and relationships" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var snapshot = try fixture.index.publish();
    defer snapshot.deinit();

    const greeter = snapshot.findDefinition(java_path, "Greeter").?;
    const greeting = snapshot.findDefinition(java_path, "greeting").?;
    const greet = snapshot.findDefinition(java_path, "greet").?;
    const announce = snapshot.findDefinition(java_path, "announce").?;

    try testing.expectEqualStrings("class", greeter.identity.role);
    try testing.expectEqualStrings("method", greet.identity.role);
    try testing.expectEqualStrings("Greeter", greet.identity.container_path[0]);
    try testing.expectEqualStrings("greet()", greet.identity.signature.?);
    try testing.expectEqualStrings("demo", greet.extension.get("java.package").?);
    try testing.expectEqualStrings("String", greet.extension.get("java.return_type").?);

    // One file source container, established by source ingestion, defines the
    // class; the class defines its methods.
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .defines,
        .target = greeter.id,
    }));
    try testing.expectEqual(@as(usize, 3), snapshot.countRelationships(.{
        .kind = .defines,
        .source = greeter.id,
    }));

    // A resolved call, an unresolved call, a resolved type reference, and an
    // unresolved type reference.
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .calls,
        .source = greet.id,
        .target = greeting.id,
        .resolution = .fact,
    }));
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .calls,
        .source = announce.id,
        .target = greet.id,
        .resolution = .fact,
    }));
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .calls,
        .source = announce.id,
        .designator = "report",
        .resolution = .unresolved,
    }));
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .references,
        .source = greeter.id,
        .target = greeter.id,
        .resolution = .fact,
    }));
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .references,
        .source = greet.id,
        .designator = "String",
        .resolution = .unresolved,
    }));

    // A field is a Java definition this frontend does not cover. It is
    // reported as unsupported rather than left looking absent.
    const diagnostic = snapshot.findDiagnostic(.unsupported_construct).?;
    try testing.expect(std.mem.indexOf(u8, diagnostic.message, "field_declaration") != null);
}

test "a call occurrence answers the reference query exactly once" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var snapshot = try fixture.index.publish();
    defer snapshot.deinit();

    const announce = snapshot.findDefinition(java_path, "announce").?;

    // `announce` calls `greet` and `report` and references nothing else. The
    // reference query returns both occurrences, once each; adding the per-kind
    // counts would double-count neither, because no separate `references`
    // assertion was recorded for the same occurrence.
    try testing.expectEqual(@as(usize, 2), snapshot.countRelationships(.{
        .source = announce.id,
        .reference_query = true,
    }));
    try testing.expectEqual(@as(usize, 2), snapshot.countRelationships(.{
        .source = announce.id,
        .kind = .calls,
    }));
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{
        .source = announce.id,
        .kind = .references,
    }));
}

// -- Stage 6: Clojure fixture coverage --------------------------------------

test "the clojure fixture yields the expected entities and relationships" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var snapshot = try fixture.index.publish();
    defer snapshot.deinit();

    const namespace = snapshot.findDefinition(clojure_path, "demo.greeter").?;
    const greeting = snapshot.findDefinition(clojure_path, "greeting").?;
    const greet = snapshot.findDefinition(clojure_path, "greet").?;
    const announce = snapshot.findDefinition(clojure_path, "announce").?;

    try testing.expectEqualStrings("namespace", namespace.identity.role);
    try testing.expectEqualStrings("def", greeting.identity.role);
    try testing.expectEqualStrings("defn", greet.identity.role);
    try testing.expectEqualStrings("demo.greeter", greet.identity.container_path[0]);

    // Clojure's own vocabulary stays in the extension payload. No new
    // shared-core kind appeared for a namespace, a var, or a form.
    try testing.expectEqualStrings("clojure", greet.extension.namespace);
    try testing.expectEqualStrings("defn", greet.extension.get("clojure.form").?);
    try testing.expectEqualStrings("true", greet.extension.get("clojure.var").?);
    for ([_]model.Entity{ namespace, greeting, greet, announce }) |entity| {
        try testing.expectEqual(model.EntityKind.definition, entity.kind);
    }

    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .defines,
        .target = namespace.id,
    }));
    try testing.expectEqual(@as(usize, 3), snapshot.countRelationships(.{
        .kind = .defines,
        .source = namespace.id,
    }));

    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .references,
        .source = greet.id,
        .target = greeting.id,
        .resolution = .fact,
    }));
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .calls,
        .source = greet.id,
        .designator = "str",
        .resolution = .unresolved,
    }));
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .calls,
        .source = announce.id,
        .target = greet.id,
        .resolution = .fact,
    }));
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .calls,
        .source = announce.id,
        .designator = "report",
        .resolution = .unresolved,
    }));
}

test "both languages contribute to one graph without flattening each other" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var snapshot = try fixture.index.publish();
    defer snapshot.deinit();

    try testing.expectEqual(@as(usize, 1), snapshot.countEntities(.repository));
    try testing.expectEqual(@as(usize, 2), snapshot.countEntities(.file));
    try testing.expectEqual(@as(usize, 8), snapshot.countEntities(.definition));

    // The same shared-core question is answerable across both languages, and
    // each entity still reports which language produced it.
    var java_definitions: usize = 0;
    var clojure_definitions: usize = 0;
    for (snapshot.entities) |entity| {
        if (entity.kind != .definition) continue;
        switch (entity.identity.language.?) {
            .java => java_definitions += 1,
            .clojure => clojure_definitions += 1,
        }
    }
    try testing.expectEqual(@as(usize, 4), java_definitions);
    try testing.expectEqual(@as(usize, 4), clojure_definitions);

    // Unresolved targets exist in both languages and none of them is a fact.
    try testing.expect(snapshot.countUnresolvedAssertions() > 0);
    for (snapshot.assertions) |assertion| {
        const relationship = assertion.relationship() orelse continue;
        switch (relationship.target) {
            .designator => try testing.expect(!assertion.resolution.isFact()),
            .entity => {},
        }
    }
}

// -- Stage 7: incremental reconciliation ------------------------------------

test "a java body edit preserves every entity id" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greeting_before = before.findDefinition(java_path, "greeting").?;
    const greet_before = before.findDefinition(java_path, "greet").?;

    const outcome = try fixture.edit(fixture.java_unit, "java/edits/01_body_edit.java");
    try testing.expect(outcome.applied);
    try testing.expectEqual(@as(usize, 4), outcome.preserved);
    try testing.expectEqual(@as(usize, 0), outcome.created);
    try testing.expectEqual(@as(usize, 0), outcome.removed);
    try testing.expectEqual(@as(usize, 0), outcome.lost);

    var after = try fixture.index.publish();
    defer after.deinit();
    try testing.expectEqual(greeting_before.id, after.findDefinition(java_path, "greeting").?.id);
    try testing.expectEqual(greet_before.id, after.findDefinition(java_path, "greet").?.id);

    // A body edit introduces and retires nothing.
    try testing.expect(before.revision < after.revision);
    try testing.expectEqual(before.countEntities(.definition), after.countEntities(.definition));
}

test "an added java definition leaves the others untouched" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greet_before = before.findDefinition(java_path, "greet").?;

    const outcome = try fixture.edit(fixture.java_unit, "java/edits/02_added_definition.java");
    try testing.expectEqual(@as(usize, 4), outcome.preserved);
    try testing.expectEqual(@as(usize, 1), outcome.created);
    try testing.expectEqual(@as(usize, 0), outcome.lost);

    var after = try fixture.index.publish();
    defer after.deinit();
    try testing.expectEqual(greet_before.id, after.findDefinition(java_path, "greet").?.id);
    const farewell = after.findDefinition(java_path, "farewell").?;
    try testing.expectEqual(
        model.IdentityEventKind.created,
        after.identityEventFor(farewell.id, outcome.revision).?.kind,
    );
}

test "a renamed java definition is reported as identity loss with its replacement" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greeting_before = before.findDefinition(java_path, "greeting").?;
    const greet_before = before.findDefinition(java_path, "greet").?;

    const outcome = try fixture.edit(fixture.java_unit, "java/edits/03_renamed_definition.java");
    try testing.expectEqual(@as(usize, 1), outcome.lost);
    try testing.expectEqual(@as(usize, 1), outcome.created);
    try testing.expectEqual(@as(usize, 3), outcome.preserved);
    try testing.expectEqual(@as(usize, 0), outcome.removed);

    var after = try fixture.index.publish();
    defer after.deinit();

    // The unrelated methods kept their ids.
    try testing.expectEqual(greet_before.id, after.findDefinition(java_path, "greet").?.id);

    const event = after.identityEventFor(greeting_before.id, outcome.revision).?;
    try testing.expectEqual(model.IdentityEventKind.lost, event.kind);
    const salutation = after.findDefinition(java_path, "salutation").?;
    try testing.expectEqual(salutation.id, event.replacement.?);
    try testing.expect(after.entityById(greeting_before.id) == null);

    // The call inside `greet` now resolves to the replacement, still as a fact.
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{
        .kind = .calls,
        .source = greet_before.id,
        .target = salutation.id,
        .resolution = .fact,
    }));
}

test "a java call moves from unresolved to resolved when its target appears" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const announce_before = before.findDefinition(java_path, "announce").?;
    try testing.expectEqual(@as(usize, 1), before.countRelationships(.{
        .source = announce_before.id,
        .kind = .calls,
        .designator = "report",
        .resolution = .unresolved,
    }));

    const outcome = try fixture.edit(fixture.java_unit, "java/edits/04_reference_resolved.java");
    try testing.expectEqual(@as(usize, 4), outcome.preserved);
    try testing.expectEqual(@as(usize, 1), outcome.created);

    var after = try fixture.index.publish();
    defer after.deinit();
    const report = after.findDefinition(java_path, "report").?;
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{
        .source = announce_before.id,
        .kind = .calls,
        .target = report.id,
        .resolution = .fact,
    }));
    try testing.expectEqual(@as(usize, 0), after.countRelationships(.{
        .source = announce_before.id,
        .kind = .calls,
        .designator = "report",
    }));
}

test "a clojure body edit preserves every entity id" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greeting_before = before.findDefinition(clojure_path, "greeting").?;
    const announce_before = before.findDefinition(clojure_path, "announce").?;

    const outcome = try fixture.edit(fixture.clojure_unit, "clojure/edits/01_body_edit.clj");
    try testing.expectEqual(@as(usize, 4), outcome.preserved);
    try testing.expectEqual(@as(usize, 0), outcome.created);
    try testing.expectEqual(@as(usize, 0), outcome.lost);

    var after = try fixture.index.publish();
    defer after.deinit();
    try testing.expectEqual(greeting_before.id, after.findDefinition(clojure_path, "greeting").?.id);
    try testing.expectEqual(announce_before.id, after.findDefinition(clojure_path, "announce").?.id);
}

test "an added clojure definition leaves the others untouched" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greet_before = before.findDefinition(clojure_path, "greet").?;

    const outcome = try fixture.edit(fixture.clojure_unit, "clojure/edits/02_added_definition.clj");
    try testing.expectEqual(@as(usize, 4), outcome.preserved);
    try testing.expectEqual(@as(usize, 1), outcome.created);

    var after = try fixture.index.publish();
    defer after.deinit();
    try testing.expectEqual(greet_before.id, after.findDefinition(clojure_path, "greet").?.id);
    try testing.expect(after.findDefinition(clojure_path, "farewell") != null);
}

test "a renamed clojure definition is reported as identity loss with its replacement" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greeting_before = before.findDefinition(clojure_path, "greeting").?;
    const greet_before = before.findDefinition(clojure_path, "greet").?;

    const outcome = try fixture.edit(fixture.clojure_unit, "clojure/edits/03_renamed_definition.clj");
    try testing.expectEqual(@as(usize, 1), outcome.lost);
    try testing.expectEqual(@as(usize, 1), outcome.created);
    try testing.expectEqual(@as(usize, 3), outcome.preserved);

    var after = try fixture.index.publish();
    defer after.deinit();
    const event = after.identityEventFor(greeting_before.id, outcome.revision).?;
    try testing.expectEqual(model.IdentityEventKind.lost, event.kind);

    const salutation = after.findDefinition(clojure_path, "salutation").?;
    try testing.expectEqual(salutation.id, event.replacement.?);
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{
        .kind = .references,
        .source = greet_before.id,
        .target = salutation.id,
        .resolution = .fact,
    }));
}

test "a clojure call moves from unresolved to resolved when its target appears" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const announce_before = before.findDefinition(clojure_path, "announce").?;

    const outcome = try fixture.edit(fixture.clojure_unit, "clojure/edits/04_reference_resolved.clj");
    try testing.expectEqual(@as(usize, 4), outcome.preserved);
    try testing.expectEqual(@as(usize, 1), outcome.created);

    var after = try fixture.index.publish();
    defer after.deinit();
    const report = after.findDefinition(clojure_path, "report").?;
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{
        .kind = .calls,
        .source = announce_before.id,
        .target = report.id,
        .resolution = .fact,
    }));
    try testing.expectEqual(@as(usize, 0), after.countRelationships(.{
        .kind = .calls,
        .source = announce_before.id,
        .designator = "report",
    }));
}

test "editing one language's unit does not disturb the other's semantic region" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const clojure_greet_before = before.findDefinition(clojure_path, "greet").?;
    const clojure_relationships = before.countRelationships(.{ .source = clojure_greet_before.id });

    _ = try fixture.edit(fixture.java_unit, "java/edits/03_renamed_definition.java");

    var after = try fixture.index.publish();
    defer after.deinit();
    const clojure_greet_after = after.findDefinition(clojure_path, "greet").?;
    try testing.expectEqual(clojure_greet_before.id, clojure_greet_after.id);
    try testing.expectEqual(
        clojure_greet_before.evidence.?.range.start_byte,
        clojure_greet_after.evidence.?.range.start_byte,
    );
    try testing.expectEqual(
        clojure_relationships,
        after.countRelationships(.{ .source = clojure_greet_before.id }),
    );
    try testing.expectEqual(@as(usize, 2), after.countEntities(.file));
}

test "a snapshot taken before an edit keeps observing the state it was published from" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();

    _ = try fixture.edit(fixture.java_unit, "java/edits/02_added_definition.java");

    var after = try fixture.index.publish();
    defer after.deinit();

    try testing.expect(before.findDefinition(java_path, "farewell") == null);
    try testing.expect(after.findDefinition(java_path, "farewell") != null);
    try testing.expectEqual(@as(usize, 8), before.countEntities(.definition));
    try testing.expectEqual(@as(usize, 9), after.countEntities(.definition));
}
