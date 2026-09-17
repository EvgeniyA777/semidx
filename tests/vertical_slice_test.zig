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

    // Source ingestion says the repository contains the file. The frontend says
    // the file introduces the class, and the class introduces its methods.
    const java_file = snapshot.findEntity(.{ .kind = .file, .path = java_path }).?;
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .contains,
        .target = java_file.id,
    }));
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

    // `greeting` sits inside `(str ...)`. This frontend cannot rule out that
    // `str` is a macro binding `greeting` locally, so the name is not claimed
    // as the unit's `def`, even though that is almost certainly what it means.
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{
        .target = greeting.id,
        .kind = .references,
    }));
    const greeting_reference = snapshot.firstRelationship(.{
        .kind = .references,
        .source = greet.id,
        .designator = "greeting",
        .resolution = .unresolved,
    }).?;
    try expectExplanation(greeting_reference, "macro that binds the name locally");
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

    try testing.expectEqual(@as(usize, 1), snapshot.countEntities(.{ .kind = .repository }));
    try testing.expectEqual(@as(usize, 2), snapshot.countEntities(.{ .kind = .file }));
    try testing.expectEqual(@as(usize, 8), snapshot.countEntities(.{ .kind = .definition }));

    // The same shared-core question is answerable across both languages, and
    // each entity still reports which language produced it.
    var java_definitions: usize = 0;
    var clojure_definitions: usize = 0;
    for (snapshot.entities) |entity| {
        if (entity.kind != .definition) continue;
        switch (entity.identity.language.?) {
            .java => java_definitions += 1,
            .clojure => clojure_definitions += 1,
            .zig => {},
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
    try testing.expectEqual(before.countEntities(.{ .kind = .definition }), after.countEntities(.{ .kind = .definition }));
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
    // The reference inside `(str ...)` stays a designator for the new name;
    // nothing is silently retargeted to either entity.
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{
        .kind = .references,
        .source = greet_before.id,
        .designator = "salutation",
        .resolution = .unresolved,
    }));
    try testing.expectEqual(@as(usize, 0), after.countRelationships(.{ .target = salutation.id, .kind = .references }));
    try testing.expectEqual(@as(usize, 0), after.countRelationships(.{ .target = greeting_before.id, .kind = .references }));
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
    try testing.expectEqual(@as(usize, 2), after.countEntities(.{ .kind = .file }));
}

test "editing a java fixture into unparsable source stops its facts being current" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greet_before = before.findDefinition(java_path, "greet").?;
    const java_unit = before.unitByPath(java_path).?;
    try testing.expectEqual(semidx.core.graph.UnitAnalysis.current, java_unit.analysis());

    const outcome = try fixture.edit(fixture.java_unit, "java/edits/05_unparsable.java");
    try testing.expect(!outcome.applied);

    var after = try fixture.index.publish();
    defer after.deinit();

    // The unit reports what happened, and its earlier facts no longer answer
    // questions about what is in the file now.
    try testing.expectEqual(
        semidx.core.graph.UnitAnalysis.stale,
        after.unitAnalysis(fixture.java_unit).?,
    );
    try testing.expectEqual(@as(usize, 1), after.countDiagnostics(.analysis_failed));
    try testing.expect(after.findDefinition(java_path, "greet") == null);
    try testing.expectEqual(@as(usize, 0), after.countRelationships(.{ .source = greet_before.id }));

    // The Clojure unit is untouched: one file failing to parse is not a reason
    // to stop answering about another.
    try testing.expectEqual(
        semidx.core.graph.UnitAnalysis.current,
        after.unitAnalysis(fixture.clojure_unit).?,
    );
    try testing.expectEqual(@as(usize, 4), after.countEntities(.{
        .kind = .definition,
        .language = .clojure,
    }));
    try testing.expectEqual(@as(usize, 0), after.countEntities(.{
        .kind = .definition,
        .language = .java,
    }));

    // Nothing was deleted, so repairing the source restores the same entities.
    const repaired = try fixture.edit(fixture.java_unit, "java/edits/01_body_edit.java");
    try testing.expect(repaired.applied);
    try testing.expectEqual(@as(usize, 4), repaired.preserved);
    try testing.expectEqual(@as(usize, 0), repaired.created);
    try testing.expectEqual(@as(usize, 0), repaired.lost);

    var repaired_snapshot = try fixture.index.publish();
    defer repaired_snapshot.deinit();
    try testing.expectEqual(
        semidx.core.graph.UnitAnalysis.current,
        repaired_snapshot.unitAnalysis(fixture.java_unit).?,
    );
    try testing.expectEqual(
        greet_before.id,
        repaired_snapshot.findDefinition(java_path, "greet").?.id,
    );
    try testing.expectEqual(@as(usize, 0), repaired_snapshot.countDiagnostics(.analysis_failed));
}

test "editing a clojure fixture into unparsable source stops its facts being current" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greet_before = before.findDefinition(clojure_path, "greet").?;

    const outcome = try fixture.edit(fixture.clojure_unit, "clojure/edits/05_unparsable.clj");
    try testing.expect(!outcome.applied);

    var after = try fixture.index.publish();
    defer after.deinit();
    try testing.expectEqual(
        semidx.core.graph.UnitAnalysis.stale,
        after.unitAnalysis(fixture.clojure_unit).?,
    );
    try testing.expect(after.findDefinition(clojure_path, "greet") == null);

    // Still recorded, still attributed, just not current.
    try testing.expectEqual(greet_before.id, after.findEntity(.{
        .kind = .definition,
        .path = clojure_path,
        .name = "greet",
        .freshness = .stale,
    }).?.id);
}

test "the source container's extent tracks the file it stands for" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const file_before = before.findEntity(.{ .kind = .file, .path = java_path }).?;

    _ = try fixture.edit(fixture.java_unit, "java/edits/02_added_definition.java");

    var after = try fixture.index.publish();
    defer after.deinit();
    const file_after = after.findEntity(.{ .kind = .file, .path = java_path }).?;

    try testing.expectEqual(file_before.id, file_after.id);
    try testing.expect(
        file_after.evidence.?.range.end_byte > file_before.evidence.?.range.end_byte,
    );
    try testing.expectEqual(
        file_after.evidence.?.range.end_byte,
        after.firstRelationship(.{ .kind = .contains, .target = file_after.id }).?
            .evidence.?.range.end_byte,
    );
}

test "a scan of the fixture root discovers its units without a manual list" {
    const gpa = testing.allocator;

    var root = try std.Io.Dir.cwd().openDir(testing.io, build_options.fixtures_dir, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer root.close(testing.io);

    var found = try semidx.source.discovery.scanDir(
        gpa,
        testing.io,
        root,
        build_options.fixtures_dir,
        .{},
    );
    defer found.deinit();

    // Both fixture languages are present, every discovered unit is one a
    // frontend covers, and the base fixtures are among them.
    try testing.expect(found.units.len >= 4);
    try testing.expect(found.unitByPath(java_path) != null);
    try testing.expect(found.unitByPath(clojure_path) != null);

    var java_units: usize = 0;
    var clojure_units: usize = 0;
    for (found.units) |unit| {
        try testing.expectEqual(unit.language, semidx.languageForPath(unit.path).?);
        switch (unit.language) {
            .java => java_units += 1,
            .clojure => clojure_units += 1,
            .zig => {},
        }
    }
    try testing.expect(java_units > 0);
    try testing.expect(clojure_units > 0);

    var index = try semidx.Index.init(gpa, build_options.fixtures_dir);
    defer index.deinit();
    _ = try index.applyScan(found);

    var snapshot = try index.publish();
    defer snapshot.deinit();

    try testing.expectEqual(found.units.len, snapshot.countEntities(.{ .kind = .file }));
    try testing.expect(snapshot.findDefinition(java_path, "greet") != null);
    try testing.expect(snapshot.findDefinition(clojure_path, "greet") != null);

    // The deliberately unparsable fixtures were discovered and registered, and
    // report that nothing analyzed them rather than looking like empty files.
    const unparsable = snapshot.unitByPath("java/edits/05_unparsable.java").?;
    try testing.expectEqual(semidx.core.graph.UnitAnalysis.pending, unparsable.analysis());
    try testing.expect(snapshot.countDiagnostics(.analysis_failed) > 0);
}

test "renaming a java fixture keeps every identity inside it" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greeter = before.findDefinition(java_path, "Greeter").?;
    const greet = before.findDefinition(java_path, "greet").?;
    const announce = before.findDefinition(java_path, "announce").?;
    const file = before.unit(fixture.java_unit).?.entity;
    const calls_before = before.countRelationships(.{ .source = announce.id });

    try fixture.index.renameUnit(fixture.java_unit, "java/Renamed.java");

    var after = try fixture.index.publish();
    defer after.deinit();

    // Everything the file introduced kept its id, and so did the file.
    try testing.expectEqual(greeter.id, after.findDefinition("java/Renamed.java", "Greeter").?.id);
    try testing.expectEqual(greet.id, after.findDefinition("java/Renamed.java", "greet").?.id);
    try testing.expectEqual(file, after.unit(fixture.java_unit).?.entity);
    try testing.expectEqual(calls_before, after.countRelationships(.{ .source = announce.id }));

    // A rename is not an edit. Nothing went stale, and no identity broke: the
    // only event is the container's own preserved correspondence.
    try testing.expectEqual(
        semidx.core.graph.UnitAnalysis.current,
        after.unitAnalysis(fixture.java_unit).?,
    );
    const events = try after.identityEventsAt(after.revision, testing.allocator);
    defer testing.allocator.free(events);
    try testing.expectEqual(@as(usize, 1), events.len);
    try testing.expectEqual(model.IdentityEventKind.preserved, events[0].kind);
    try testing.expectEqual(file, events[0].entity);

    // The Clojure unit did not move.
    try testing.expect(after.findDefinition(clojure_path, "greet") != null);

    // And an edit after the rename still reconciles against the same entities.
    const outcome = try fixture.edit(fixture.java_unit, "java/edits/01_body_edit.java");
    try testing.expectEqual(@as(usize, 4), outcome.preserved);
    try testing.expectEqual(@as(usize, 0), outcome.lost);

    var edited = try fixture.index.publish();
    defer edited.deinit();
    try testing.expectEqual(greet.id, edited.findDefinition("java/Renamed.java", "greet").?.id);
}

// -- Stage 3: scan reconciliation -------------------------------------------

/// A source tree on disk that can be rescanned, so that what the indexer is
/// told about a change is only ever what a scan can see.
const Tree = struct {
    tmp: std.testing.TmpDir,
    index: semidx.Index,

    fn init(gpa: std.mem.Allocator) !Tree {
        return .{
            .tmp = testing.tmpDir(.{ .iterate = true }),
            .index = try semidx.Index.init(gpa, "tree"),
        };
    }

    fn deinit(self: *Tree) void {
        self.index.deinit();
        self.tmp.cleanup();
    }

    fn write(self: *Tree, path: []const u8, bytes: []const u8) !void {
        if (std.fs.path.dirname(path)) |parent| {
            try self.tmp.dir.createDirPath(testing.io, parent);
        }
        try self.tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = bytes });
    }

    fn remove(self: *Tree, path: []const u8) !void {
        try self.tmp.dir.deleteFile(testing.io, path);
    }

    fn move(self: *Tree, from: []const u8, to: []const u8) !void {
        if (std.fs.path.dirname(to)) |parent| {
            try self.tmp.dir.createDirPath(testing.io, parent);
        }
        try self.tmp.dir.rename(from, self.tmp.dir, to, testing.io);
    }

    fn rescan(self: *Tree) !semidx.Index.ScanOutcome {
        var found = try semidx.source.discovery.scanDir(
            self.index.graph.gpa,
            testing.io,
            self.tmp.dir,
            "tree",
            .{},
        );
        defer found.deinit();
        return self.index.applyScan(found);
    }

    fn invocations(self: *const Tree) usize {
        return self.index.analyzer.invocations;
    }
};

const greeter_java =
    \\class Greeter {
    \\    String greet() {
    \\        return greeting();
    \\    }
    \\
    \\    String greeting() {
    \\        return "hello";
    \\    }
    \\}
    \\
;

test "rescanning an unchanged tree asks no frontend anything" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write("Greeter.java", greeter_java);
    try tree.write("demo/greeter.clj", "(ns demo.greeter)\n(defn greet [] \"hi\")\n");

    const first = try tree.rescan();
    try testing.expectEqual(@as(usize, 2), first.added);
    try testing.expectEqual(@as(usize, 2), first.analyzed);
    const after_first = tree.invocations();
    try testing.expectEqual(@as(usize, 2), after_first);

    var before = try tree.index.publish();
    defer before.deinit();
    const greet = before.findDefinition("Greeter.java", "greet").?;
    const revision_before = before.revision;

    const second = try tree.rescan();
    try testing.expectEqual(@as(usize, 2), second.unchanged);
    try testing.expectEqual(@as(usize, 0), second.analyzed);
    try testing.expectEqual(@as(usize, 0), second.changed);

    // Measured, not assumed: no frontend was asked to read anything.
    try testing.expectEqual(after_first, tree.invocations());

    var after = try tree.index.publish();
    defer after.deinit();
    try testing.expectEqual(greet.id, after.findDefinition("Greeter.java", "greet").?.id);

    // No revision opened and no identity event was recorded, because nothing
    // about the graph changed.
    try testing.expectEqual(revision_before, after.revision);
    try testing.expectEqual(before.identity_events.len, after.identity_events.len);
}

test "editing one file in a tree reanalyzes exactly that file" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write("Greeter.java", greeter_java);
    for (0..12) |index| {
        const path = try std.fmt.allocPrint(testing.allocator, "bulk/Filler{d}.java", .{index});
        defer testing.allocator.free(path);
        const body = try std.fmt.allocPrint(
            testing.allocator,
            "class Filler{d} {{ void run() {{}} }}\n",
            .{index},
        );
        defer testing.allocator.free(body);
        try tree.write(path, body);
    }

    const first = try tree.rescan();
    try testing.expectEqual(@as(usize, 13), first.added);
    const baseline = tree.invocations();
    try testing.expectEqual(@as(usize, 13), baseline);

    var before = try tree.index.publish();
    defer before.deinit();
    const filler = before.findDefinition("bulk/Filler7.java", "run").?;

    try tree.write("Greeter.java", greeter_java ++ "// edited\n");
    const second = try tree.rescan();

    try testing.expectEqual(@as(usize, 1), second.changed);
    try testing.expectEqual(@as(usize, 12), second.unchanged);
    try testing.expectEqual(@as(usize, 1), second.analyzed);

    // One frontend invocation for thirteen units. This is the whole point of
    // the stage: the work tracks the change, not the repository.
    try testing.expectEqual(baseline + 1, tree.invocations());

    var after = try tree.index.publish();
    defer after.deinit();
    try testing.expectEqual(filler.id, after.findDefinition("bulk/Filler7.java", "run").?.id);
    try testing.expectEqual(
        filler.evidence.?.range.start_byte,
        after.findDefinition("bulk/Filler7.java", "run").?.evidence.?.range.start_byte,
    );
}

test "adding a file leaves every existing unit alone" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write("Greeter.java", greeter_java);
    _ = try tree.rescan();
    const baseline = tree.invocations();

    var before = try tree.index.publish();
    defer before.deinit();
    const greet = before.findDefinition("Greeter.java", "greet").?;

    try tree.write("Other.java", "class Other { void run() {} }\n");
    const outcome = try tree.rescan();

    try testing.expectEqual(@as(usize, 1), outcome.added);
    try testing.expectEqual(@as(usize, 1), outcome.unchanged);
    try testing.expectEqual(baseline + 1, tree.invocations());

    var after = try tree.index.publish();
    defer after.deinit();
    try testing.expectEqual(greet.id, after.findDefinition("Greeter.java", "greet").?.id);
    try testing.expect(after.findDefinition("Other.java", "run") != null);
}

test "moving a file preserves the unit and everything inside it" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write("old/Greeter.java", greeter_java);
    try tree.write("Keep.java", "class Keep { void run() {} }\n");
    _ = try tree.rescan();
    const baseline = tree.invocations();

    var before = try tree.index.publish();
    defer before.deinit();
    const unit = before.unitByPath("old/Greeter.java").?;
    const greet = before.findDefinition("old/Greeter.java", "greet").?;
    const greeting = before.findDefinition("old/Greeter.java", "greeting").?;
    const calls = before.countRelationships(.{ .source = greet.id });

    try tree.move("old/Greeter.java", "new/Greeter.java");
    const outcome = try tree.rescan();

    try testing.expectEqual(@as(usize, 1), outcome.renamed);
    try testing.expectEqual(@as(usize, 1), outcome.unchanged);
    try testing.expectEqual(@as(usize, 0), outcome.removed);
    try testing.expectEqual(@as(usize, 0), outcome.added);

    // Nothing inside the file moved, so nothing was re-read.
    try testing.expectEqual(@as(usize, 0), outcome.analyzed);
    try testing.expectEqual(baseline, tree.invocations());

    var after = try tree.index.publish();
    defer after.deinit();
    try testing.expectEqual(unit.id, after.unitByPath("new/Greeter.java").?.id);
    try testing.expectEqual(unit.entity, after.unitByPath("new/Greeter.java").?.entity);
    try testing.expectEqual(greet.id, after.findDefinition("new/Greeter.java", "greet").?.id);
    try testing.expectEqual(greeting.id, after.findDefinition("new/Greeter.java", "greeting").?.id);
    try testing.expectEqual(calls, after.countRelationships(.{ .source = greet.id }));
    try testing.expectEqual(
        semidx.core.graph.UnitAnalysis.current,
        after.unitAnalysis(unit.id).?,
    );

    // The move is recorded as an established correspondence, and it is a fact:
    // identical bytes is exact resolution of "the same unit", not a guess.
    const event = after.lastIdentityEvent(unit.entity).?;
    try testing.expectEqual(model.IdentityEventKind.preserved, event.kind);
}

test "moving a file while editing it is a break, and the break is visible" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write("old/Greeter.java", greeter_java);
    _ = try tree.rescan();

    var before = try tree.index.publish();
    defer before.deinit();
    const unit = before.unitByPath("old/Greeter.java").?;
    const greet = before.findDefinition("old/Greeter.java", "greet").?;

    try tree.remove("old/Greeter.java");
    try tree.write("new/Greeter.java", greeter_java ++ "// moved and edited\n");
    const outcome = try tree.rescan();

    // Nothing establishes that the new unit is the old one, so the graph does
    // not claim it. The old unit leaves and a new one arrives.
    try testing.expectEqual(@as(usize, 1), outcome.removed);
    try testing.expectEqual(@as(usize, 1), outcome.added);
    try testing.expectEqual(@as(usize, 0), outcome.renamed);
    try testing.expectEqual(@as(usize, 0), outcome.ambiguous_renames);

    var after = try tree.index.publish();
    defer after.deinit();
    try testing.expect(after.unitByPath("old/Greeter.java") == null);
    try testing.expect(after.entityById(greet.id) == null);
    try testing.expect(after.entityById(unit.entity) == null);

    // The departure is recorded, not merely absent.
    try testing.expectEqual(
        model.IdentityEventKind.removed,
        after.lastIdentityEvent(greet.id).?.kind,
    );

    const arrived = after.findDefinition("new/Greeter.java", "greet").?;
    try testing.expect(arrived.id != greet.id);
}

test "deleting a file removes what it introduced and leaves the rest" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write("Greeter.java", greeter_java);
    try tree.write("Keep.java", "class Keep { void run() {} }\n");
    _ = try tree.rescan();
    const baseline = tree.invocations();

    var before = try tree.index.publish();
    defer before.deinit();
    const greet = before.findDefinition("Greeter.java", "greet").?;
    const keep = before.findDefinition("Keep.java", "run").?;

    try tree.remove("Greeter.java");
    const outcome = try tree.rescan();

    try testing.expectEqual(@as(usize, 1), outcome.removed);
    try testing.expectEqual(@as(usize, 1), outcome.unchanged);

    // A deletion is not a reason to re-read anything that survived.
    try testing.expectEqual(@as(usize, 0), outcome.analyzed);
    try testing.expectEqual(baseline, tree.invocations());

    var after = try tree.index.publish();
    defer after.deinit();
    try testing.expect(after.entityById(greet.id) == null);
    try testing.expectEqual(
        model.IdentityEventKind.removed,
        after.lastIdentityEvent(greet.id).?.kind,
    );
    try testing.expectEqual(keep.id, after.findDefinition("Keep.java", "run").?.id);
    try testing.expectEqual(@as(usize, 1), after.countEntities(.{ .kind = .file }));
}

test "an unresolvable move is reported rather than guessed" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write("old/Twin.java", "class Twin { void run() {} }\n");
    _ = try tree.rescan();

    try tree.remove("old/Twin.java");
    try tree.write("one/Twin.java", "class Twin { void run() {} }\n");
    try tree.write("two/Twin.java", "class Twin { void run() {} }\n");
    const outcome = try tree.rescan();

    try testing.expectEqual(@as(usize, 0), outcome.renamed);
    try testing.expectEqual(@as(usize, 1), outcome.removed);
    try testing.expectEqual(@as(usize, 2), outcome.added);
    try testing.expectEqual(@as(usize, 1), outcome.ambiguous_renames);

    var after = try tree.index.publish();
    defer after.deinit();
    const diagnostic = after.findDiagnostic(.unsupported_construct).?;
    try testing.expect(std.mem.indexOf(u8, diagnostic.message, "no move could be established") != null);
}

test "a file edited into unparsable source stays stale across a rescan" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write("Greeter.java", greeter_java);
    try tree.write("Keep.java", "class Keep { void run() {} }\n");
    _ = try tree.rescan();

    var before = try tree.index.publish();
    defer before.deinit();
    const unit = before.unitByPath("Greeter.java").?;
    const greet = before.findDefinition("Greeter.java", "greet").?;

    try tree.write("Greeter.java", "class Greeter { String greet( \n");
    _ = try tree.rescan();

    var after = try tree.index.publish();
    defer after.deinit();
    try testing.expectEqual(
        semidx.core.graph.UnitAnalysis.stale,
        after.unitAnalysis(unit.id).?,
    );
    try testing.expect(after.findDefinition("Greeter.java", "greet") == null);
    try testing.expect(after.entityById(greet.id) != null);
    try testing.expect(after.findDefinition("Keep.java", "run") != null);

    // Repairing it brings the same entities back.
    try tree.write("Greeter.java", greeter_java);
    _ = try tree.rescan();

    var repaired = try tree.index.publish();
    defer repaired.deinit();
    try testing.expectEqual(
        semidx.core.graph.UnitAnalysis.current,
        repaired.unitAnalysis(unit.id).?,
    );
    try testing.expectEqual(greet.id, repaired.findDefinition("Greeter.java", "greet").?.id);
}

// -- Stage 4: the affected-region proof at scale ----------------------------

/// Fills a tree with `count` units per language that differ only by a number.
///
/// Generated rather than committed: a few dozen files that differ by an index
/// would add noise to the repository without adding evidence, and the property
/// under test is about size, which a generator states more clearly than a
/// directory listing does.
fn fill(tree: *Tree, count: usize) !void {
    const gpa = testing.allocator;
    for (0..count) |index| {
        const java_file = try std.fmt.allocPrint(gpa, "java/Filler{d}.java", .{index});
        defer gpa.free(java_file);
        const java_body = try std.fmt.allocPrint(
            gpa,
            "class Filler{d} {{\n    String run() {{\n        return helper();\n    }}\n\n" ++
                "    String helper() {{\n        return \"{d}\";\n    }}\n}}\n",
            .{ index, index },
        );
        defer gpa.free(java_body);
        try tree.write(java_file, java_body);

        const clj_file = try std.fmt.allocPrint(gpa, "clojure/filler{d}.clj", .{index});
        defer gpa.free(clj_file);
        const clj_body = try std.fmt.allocPrint(
            gpa,
            "(ns demo.filler{d})\n\n(def value \"{d}\")\n\n(defn run []\n  (str value))\n",
            .{ index, index },
        );
        defer gpa.free(clj_body);
        try tree.write(clj_file, clj_body);
    }
}

/// The unit every scale test edits. Identical in every tree, so the work of
/// changing it is comparable across tree sizes.
const subject_before = "class Subject {\n    String run() {\n        return \"before\";\n    }\n}\n";
const subject_after = "class Subject {\n    String run() {\n        return \"after\";\n    }\n}\n";

const ScaleRun = struct {
    /// Records the graph examined while applying the scan that first built the
    /// tree.
    build_work: usize,
    /// Records examined while applying a one-unit edit to it.
    edit_work: usize,
    /// Frontend invocations caused by that edit.
    edit_invocations: usize,
    units: usize,
    entities: usize,
    assertions: usize,
};

fn scaleRun(count: usize) !ScaleRun {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try fill(&tree, count);
    try tree.write("Subject.java", subject_before);

    const built = try tree.rescan();
    const build_work = tree.index.graph.unit_work;
    const invocations_before = tree.invocations();

    var snapshot = try tree.index.publish();
    defer snapshot.deinit();

    try tree.write("Subject.java", subject_after);
    const edited = try tree.rescan();
    try testing.expectEqual(@as(usize, 1), edited.changed);
    try testing.expectEqual(built.added - 1, edited.unchanged);

    return .{
        .build_work = build_work,
        .edit_work = tree.index.graph.unit_work - build_work,
        .edit_invocations = tree.invocations() - invocations_before,
        .units = snapshot.units.len,
        .entities = snapshot.entities.len,
        .assertions = snapshot.assertions.len,
    };
}

test "changing one unit costs the same whatever else the repository holds" {
    const small = try scaleRun(12);
    const large = try scaleRun(36);

    try testing.expectEqual(@as(usize, 25), small.units);
    try testing.expectEqual(@as(usize, 73), large.units);

    // One frontend invocation each, regardless of tree size.
    try testing.expectEqual(@as(usize, 1), small.edit_invocations);
    try testing.expectEqual(@as(usize, 1), large.edit_invocations);

    // And exactly the same number of stored records examined. This is the
    // guard: if any per-unit operation goes back to sweeping the graph — an
    // assertion list filtered end to end, a path resolved by scanning units,
    // a unit's definitions found by walking every entity — this number grows
    // with the tree and the test fails.
    try testing.expectEqual(small.edit_work, large.edit_work);
}

test "building a tree costs work proportional to the tree, not to its square" {
    const small = try scaleRun(12);
    const large = try scaleRun(36);

    // Three times the units for about three times the work. A per-unit
    // operation that sweeps the graph would make this nine times.
    try testing.expect(large.build_work < small.build_work * 4);
    try testing.expect(large.build_work > small.build_work * 2);

    // Stated the other way: the work of building a tree is bounded per unit.
    try testing.expect(small.build_work < small.units * 64);
    try testing.expect(large.build_work < large.units * 64);
}

test "adding units to a large tree reanalyzes only what was added" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try fill(&tree, 24);
    _ = try tree.rescan();

    const invocations_before = tree.invocations();
    const work_before = tree.index.graph.unit_work;

    var before = try tree.index.publish();
    defer before.deinit();
    const untouched = before.findDefinition("java/Filler7.java", "run").?;

    try tree.write("java/Added.java", "class Added { void run() {} }\n");
    try tree.write("clojure/added.clj", "(ns demo.added)\n(defn run [] \"x\")\n");
    const outcome = try tree.rescan();

    try testing.expectEqual(@as(usize, 2), outcome.added);
    try testing.expectEqual(@as(usize, 48), outcome.unchanged);
    try testing.expectEqual(@as(usize, 2), tree.invocations() - invocations_before);

    // Two units' worth of work for a repository of fifty.
    try testing.expect(tree.index.graph.unit_work - work_before < 64);

    var after = try tree.index.publish();
    defer after.deinit();
    try testing.expectEqual(untouched.id, after.findDefinition("java/Filler7.java", "run").?.id);
    // Two source containers, a Java class and its method, a Clojure namespace
    // and its function.
    try testing.expectEqual(before.entities.len + 6, after.entities.len);
}

test "the repository-scale fixtures resolve only what a language's scoping establishes" {
    const gpa = testing.allocator;
    const root = try std.fs.path.join(gpa, &.{ build_options.fixtures_dir, "..", "repository-scale" });
    defer gpa.free(root);

    var dir = try std.Io.Dir.cwd().openDir(testing.io, root, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer dir.close(testing.io);

    var found = try semidx.source.discovery.scanDir(gpa, testing.io, dir, root, .{});
    defer found.deinit();

    var index = try semidx.Index.init(gpa, root);
    defer index.deinit();
    const outcome = try index.applyScan(found);
    try testing.expectEqual(@as(usize, 6), outcome.added);
    // Units are analyzed in path order, so `Greeter` and `Helper` were read
    // before `Unrelated` finished changing what package `demo` declares, and
    // both are read once more. `Unrelated` and the Clojure units are not.
    try testing.expectEqual(@as(usize, 2), outcome.invalidated);
    try testing.expectEqual(@as(usize, 8), outcome.analyzed);

    var snapshot = try index.publish();
    defer snapshot.deinit();

    // Each unit's own definitions resolve.
    const greeter = snapshot.findDefinition("java/demo/Greeter.java", "greet").?;
    const salutation = snapshot.findDefinition("java/demo/Greeter.java", "salutation").?;
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .calls,
        .source = greeter.id,
        .target = salutation.id,
        .resolution = .fact,
    }));

    // `Helper` is declared by exactly one other unit of package `demo`, so Java
    // scoping establishes what the name means: a fact about that class, with the
    // dependency that keeps it current.
    const class = snapshot.findDefinition("java/demo/Greeter.java", "Greeter").?;
    const helper = snapshot.findDefinition("java/demo/Helper.java", "Helper").?;
    const reference = snapshot.firstRelationship(.{
        .kind = .references,
        .source = class.id,
        .target = helper.id,
    }).?;
    try testing.expectEqual(model.ResolutionCategory.fact, reference.resolution.category());
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .designator = "Helper" }));
    try testing.expectEqual(@as(usize, 1), index.graph.dependencies.count());
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());

    // Clojure namespace resolution was not decided, so a name that leaves its
    // unit there is still a designator, not matched across the tree.
    const clojure_greet = snapshot.findDefinition("clojure/demo/greeter.clj", "greet").?;
    const decorate = snapshot.firstRelationship(.{
        .kind = .calls,
        .source = clojure_greet.id,
        .designator = "decorate",
    }).?;
    try testing.expectEqual(model.ResolutionCategory.unresolved, decorate.resolution.category());
    try testing.expect(snapshot.findDefinition("clojure/demo/helper.clj", "decorate") != null);
}

// -- Plan 005: Java same-class invocation facts ------------------------------

fn callFrom(snapshot: *const semidx.Snapshot, source: model.EntityId, line: u32) !model.Assertion {
    var calls = snapshot.relationships(.{ .kind = .calls, .source = source });
    while (calls.next()) |call| {
        if (call.evidence.?.range.start_row + 1 == line) return call;
    }
    std.debug.print("no call from entity {d} on line {d}\n", .{ @intFromEnum(source), line });
    return error.TestExpectedCall;
}

test "a java invocation is a fact only when the class leaves one method to select" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit("demo/Calls.java", .java,
        \\package demo;
        \\
        \\class Plain {
        \\    void only() {}
        \\    void twice() {}
        \\    void twice(String name) {}
        \\    void run() {
        \\        only();
        \\        twice("x");
        \\        new Runnable() { public void run() { only(); } };
        \\        class Local { void go() { only(); } }
        \\        Runnable lambda = () -> only();
        \\    }
        \\}
        \\
        \\class Child extends Plain {
        \\    void own() {}
        \\    void run() { own(); }
        \\}
        \\
        \\class Worker implements Runnable {
        \\    void own() {}
        \\    public void run() { own(); }
        \\}
        \\
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();
    const only = snapshot.findDefinition("demo/Calls.java", "only").?;

    var plain_run: ?model.Entity = null;
    var runs = snapshot.entitiesMatching(.{ .kind = .definition, .name = "run" });
    while (runs.next()) |candidate| {
        if (std.mem.eql(u8, candidate.identity.container_path[0], "Plain")) plain_run = candidate;
    }
    const run = plain_run.?;

    // The one method of that name, from the class's own scope and from a
    // lambda, which keeps that scope.
    for ([_]u32{ 8, 12 }) |line| {
        const call = try callFrom(&snapshot, run.id, line);
        try testing.expectEqual(model.ResolutionCategory.fact, call.resolution.category());
        try testing.expectEqual(only.id, call.claim.relationship.target.entity);
    }

    // An overload is not selected by name.
    const overloaded = try callFrom(&snapshot, run.id, 9);
    try testing.expectEqualStrings("twice", overloaded.claim.relationship.target.designator);
    try expectExplanation(overloaded, "overloads are not resolved");

    // Inside an anonymous or local class the name may mean that class's method.
    for ([_]u32{ 10, 11 }) |line| {
        try expectExplanation(try callFrom(&snapshot, run.id, line), "class body declared in the method");
    }

    // A superclass or an interface may contribute a method of the same name.
    var classes = snapshot.entitiesMatching(.{ .kind = .definition, .name = "run" });
    var checked: usize = 0;
    while (classes.next()) |candidate| {
        const container = candidate.identity.container_path[0];
        if (std.mem.eql(u8, container, "Plain")) continue;
        var calls = snapshot.relationships(.{ .kind = .calls, .source = candidate.id });
        const call = calls.next().?;
        try expectExplanation(call, "supertypes");
        checked += 1;
    }
    try testing.expectEqual(@as(usize, 2), checked);

    try testing.expectEqual(@as(usize, 2), snapshot.countRelationships(.{ .kind = .calls, .resolution = .fact }));
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
}

fn clojureSymbol(
    snapshot: *const semidx.Snapshot,
    source: model.EntityId,
    kind: model.RelationshipKind,
    line: u32,
    name: []const u8,
) !model.Assertion {
    var found = snapshot.relationships(.{ .kind = kind, .source = source });
    while (found.next()) |assertion| {
        if (assertion.evidence.?.range.start_row + 1 != line) continue;
        if (!std.mem.eql(u8, assertion.evidence.?.text, name)) continue;
        return assertion;
    }
    std.debug.print("no {t} of `{s}` on line {d}\n", .{ kind, name, line });
    return error.TestExpectedRelationship;
}

test "a clojure symbol is a fact only where nothing may bind it locally" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit("demo/scope.clj", .clojure,
        \\(ns demo.scope)
        \\(defn helper [] 1)
        \\(defn twice [] 2)
        \\(defn twice [] 3)
        \\(defmacro shadowed [] 4)
        \\(defn shadowed [] 5)
        \\(defn known [x]
        \\  (helper)
        \\  (twice)
        \\  (shadowed)
        \\  (do (helper) (if x (helper) [(helper)]))
        \\  (helper (helper))
        \\  ((helper) (helper)))
        \\(defn unknown [helper]
        \\  (helper))
        \\(defn scoped []
        \\  (let [helper (fn [] 2)] (helper))
        \\  (my-macro helper))
        \\(defn arities
        \\  ([] (helper))
        \\  ([x] x))
        \\
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();
    const helper = snapshot.findDefinition("demo/scope.clj", "helper").?;
    const known = snapshot.findDefinition("demo/scope.clj", "known").?;
    const unknown = snapshot.findDefinition("demo/scope.clj", "unknown").?;
    const scoped = snapshot.findDefinition("demo/scope.clj", "scoped").?;
    const arities = snapshot.findDefinition("demo/scope.clj", "arities").?;

    // Forms known to bind nothing keep the facts under them: the body itself,
    // `do`, `if`, a vector literal, arguments of the unit's own function, and
    // an application whose head is not a symbol.
    try testing.expectEqual(@as(usize, 8), snapshot.countRelationships(.{
        .source = known.id,
        .target = helper.id,
        .resolution = .fact,
    }));

    try expectExplanation(try clojureSymbol(&snapshot, known.id, .calls, 9, "twice"), "more than once");
    try expectExplanation(try clojureSymbol(&snapshot, known.id, .calls, 10, "shadowed"), "more than once");
    try expectExplanation(try clojureSymbol(&snapshot, unknown.id, .calls, 15, "helper"), "parameter");
    try expectExplanation(try clojureSymbol(&snapshot, scoped.id, .calls, 17, "helper"), "binds the name locally");
    try expectExplanation(try clojureSymbol(&snapshot, scoped.id, .references, 18, "helper"), "binds the name locally");
    try expectExplanation(try clojureSymbol(&snapshot, arities.id, .calls, 20, "helper"), "several arities");

    for ([_]model.EntityId{ unknown.id, scoped.id, arities.id }) |source| {
        try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .source = source, .resolution = .fact, .reference_query = true }));
    }
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
}

// -- Plan 003: Java same-package type resolution ------------------------------

fn referenceFrom(
    snapshot: *const semidx.Snapshot,
    source: model.EntityId,
    designator: []const u8,
) !model.Assertion {
    const found = snapshot.firstRelationship(.{
        .kind = .references,
        .source = source,
        .designator = designator,
    }) orelse {
        std.debug.print("no reference to `{s}` was recorded\n", .{designator});
        return error.TestExpectedReference;
    };
    try testing.expectEqual(model.ResolutionCategory.unresolved, found.resolution.category());
    return found;
}

fn expectExplanation(assertion: model.Assertion, fragment: []const u8) !void {
    const explanation = assertion.resolution.unresolved.explanation;
    if (std.mem.indexOf(u8, explanation, fragment) == null) {
        std.debug.print("explanation `{s}` does not mention `{s}`\n", .{ explanation, fragment });
        return error.TestUnexpectedExplanation;
    }
}

test "a java type name resolves to the one class its package declares in another unit" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    const helper = try index.addUnit("demo/Helper.java", .java, "package demo;\n\nclass Helper {}\n");
    const greeter = try index.addUnit(
        "demo/Greeter.java",
        .java,
        "package demo;\n\nclass Greeter {\n    Helper helper;\n    Helper make() { return null; }\n}\n",
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();
    const helper_class = snapshot.findDefinition("demo/Helper.java", "Helper").?;
    const greeter_class = snapshot.findDefinition("demo/Greeter.java", "Greeter").?;
    const make = snapshot.findDefinition("demo/Greeter.java", "make").?;

    // Both the field type and the return type are facts about the entity the
    // other unit introduced, not about a copy or a name.
    for ([_]model.EntityId{ greeter_class.id, make.id }) |source| {
        const reference = snapshot.firstRelationship(.{
            .kind = .references,
            .source = source,
            .target = helper_class.id,
        }).?;
        try testing.expectEqual(model.ResolutionCategory.fact, reference.resolution.category());
        try testing.expectEqualStrings(semidx.frontends.java.capabilities.producer.name, reference.producer.name);
        try testing.expectEqual(greeter, reference.evidence.?.unit);
    }
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .designator = "Helper" }));

    // The dependent says what it read, once, and nothing else declares anything.
    try testing.expectEqual(@as(usize, 1), index.graph.dependencies.count());
    const declared = index.graph.dependencies.declarations.items[0];
    try testing.expectEqual(greeter, declared.dependent);
    try testing.expectEqual(helper, declared.provider);

    // No approximate assertion, and no entity that is not a repository, a file,
    // or a definition: the package stayed Java vocabulary.
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
    try testing.expectEqual(
        snapshot.entities.len,
        snapshot.countEntities(.{ .kind = .repository }) +
            snapshot.countEntities(.{ .kind = .file }) +
            snapshot.countEntities(.{ .kind = .definition }),
    );
}

test "java type names outside the same-package rule stay unresolved and say why" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit("demo/Helper.java", .java, "package demo;\nclass Helper {}\n");
    _ = try index.addUnit("demo/T.java", .java, "package demo;\nclass T {}\n");
    _ = try index.addUnit("demo/Inner.java", .java, "package demo;\nclass Inner {}\n");
    _ = try index.addUnit("demo/Imported.java", .java, "package demo;\nclass Imported {}\n");
    _ = try index.addUnit("demo/Shape.java", .java, "package demo;\nclass Shape {}\n");
    _ = try index.addUnit("one/Twin.java", .java, "package demo;\nclass Twin {}\n");
    _ = try index.addUnit("two/Twin.java", .java, "package demo;\nclass Twin {}\n");
    _ = try index.addUnit("other/Elsewhere.java", .java, "package other;\nclass Elsewhere {}\n");
    _ = try index.addUnit("Loose.java", .java, "class Loose {}\n");

    const greeter = try index.addUnit("demo/Greeter.java", .java,
        \\package demo;
        \\
        \\import other.Imported;
        \\
        \\interface Shape {}
        \\
        \\class Greeter<T> {
        \\    Helper helper;
        \\    other.Elsewhere qualified;
        \\    Elsewhere elsewhere;
        \\    Missing missing;
        \\    Twin twin;
        \\    T typed;
        \\    Inner inner;
        \\    Imported imported;
        \\    Shape shape;
        \\    Loose loose;
        \\
        \\    class Inner {}
        \\
        \\    <Helper> Helper shadowed() { return null; }
        \\}
        \\
    );
    _ = try index.addUnit("DefaultUser.java", .java, "class DefaultUser { Loose loose; }\n");
    _ = try index.addUnit("demo/Child.java", .java, "package demo;\nclass Child extends Base { Helper helper; }\n");

    var snapshot = try index.publish();
    defer snapshot.deinit();
    const class = snapshot.findDefinition("demo/Greeter.java", "Greeter").?;
    const shadowed = snapshot.findDefinition("demo/Greeter.java", "shadowed").?;
    const default_user = snapshot.findDefinition("DefaultUser.java", "DefaultUser").?;
    const child = snapshot.findDefinition("demo/Child.java", "Child").?;

    // The one name the rule covers resolves.
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .references,
        .source = class.id,
        .target = snapshot.findDefinition("demo/Helper.java", "Helper").?.id,
        .resolution = .fact,
    }));

    try expectExplanation(try referenceFrom(&snapshot, class.id, "other.Elsewhere"), "qualified");
    // Declared, but in another package: not a candidate, and not matched.
    try expectExplanation(try referenceFrom(&snapshot, class.id, "Elsewhere"), "package `demo`");
    try expectExplanation(try referenceFrom(&snapshot, class.id, "Missing"), "package `demo`");
    try expectExplanation(try referenceFrom(&snapshot, class.id, "Loose"), "package `demo`");
    try expectExplanation(try referenceFrom(&snapshot, class.id, "Twin"), "ambiguous");
    try expectExplanation(try referenceFrom(&snapshot, class.id, "T"), "type parameter of the enclosing class");
    try expectExplanation(try referenceFrom(&snapshot, class.id, "Inner"), "member type");
    try expectExplanation(try referenceFrom(&snapshot, class.id, "Imported"), "import");
    try expectExplanation(try referenceFrom(&snapshot, class.id, "Shape"), "non-class type");
    try expectExplanation(try referenceFrom(&snapshot, shadowed.id, "Helper"), "type parameter of the enclosing method");
    try expectExplanation(try referenceFrom(&snapshot, default_user.id, "Loose"), "package declaration");
    try expectExplanation(try referenceFrom(&snapshot, child.id, "Helper"), "supertypes");

    // Exactly one dependency: the unit that resolved something, on the unit it
    // resolved it to. Ambiguous and shadowed names read nothing they rely on.
    try testing.expectEqual(@as(usize, 1), index.graph.dependencies.count());
    try testing.expectEqual(greeter, index.graph.dependencies.declarations.items[0].dependent);
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
}

test "a type declared in the unit still resolves locally when its package declares it elsewhere" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit("demo/Helper.java", .java, "package demo;\nclass Helper {}\n");
    _ = try index.addUnit("demo/Greeter.java", .java, "package demo;\nclass Greeter { Helper helper; }\nclass Helper {}\n");

    var snapshot = try index.publish();
    defer snapshot.deinit();
    const class = snapshot.findDefinition("demo/Greeter.java", "Greeter").?;
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .references,
        .source = class.id,
        .target = snapshot.findDefinition("demo/Greeter.java", "Helper").?.id,
        .resolution = .fact,
    }));
    try testing.expectEqual(@as(usize, 0), index.graph.dependencies.count());
}

const demo_greeter = "package demo;\n\nclass Greeter {\n    Helper helper;\n}\n";

/// A tree with a dependent in package `demo`, one more `demo` unit, a package
/// of its own with `others` units, a default-package unit, and a Clojure unit.
fn packageTree(tree: *Tree, others: usize) !void {
    try tree.write("demo/Greeter.java", demo_greeter);
    try tree.write("demo/Unrelated.java", "package demo;\n\nclass Unrelated {\n    void run() {}\n}\n");
    for (0..others) |index| {
        const path = try std.fmt.allocPrint(testing.allocator, "other/Other{d}.java", .{index});
        defer testing.allocator.free(path);
        const body = try std.fmt.allocPrint(testing.allocator, "package other;\n\nclass Other{d} {{ Helper helper; }}\n", .{index});
        defer testing.allocator.free(body);
        try tree.write(path, body);
    }
    try tree.write("Loose.java", "class Loose { Helper helper; }\n");
    try tree.write("clojure/demo/greeter.clj", "(ns demo.greeter)\n(defn greet [] (Helper.))\n");
}

/// The one reference `Greeter` makes, whatever it currently resolves to.
fn greeterReference(snapshot: *const semidx.Snapshot) !model.Assertion {
    const class = snapshot.findDefinition("demo/Greeter.java", "Greeter").?;
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .references,
        .source = class.id,
    }));
    return snapshot.firstRelationship(.{ .kind = .references, .source = class.id }).?;
}

fn expectGreeterResolvesTo(tree: *Tree, path: []const u8) !void {
    var snapshot = try tree.index.publish();
    defer snapshot.deinit();
    const target = snapshot.findDefinition(path, "Helper").?;
    const reference = try greeterReference(&snapshot);
    try testing.expectEqual(model.ResolutionCategory.fact, reference.resolution.category());
    try testing.expectEqual(target.id, reference.relationship().?.target.entity);
}

fn expectGreeterUnresolved(tree: *Tree, fragment: []const u8) !void {
    var snapshot = try tree.index.publish();
    defer snapshot.deinit();
    const reference = try greeterReference(&snapshot);
    try testing.expectEqualStrings("Helper", reference.relationship().?.target.designator);
    try expectExplanation(reference, fragment);
}

test "adding a same-package provider resolves a dependent nobody edited" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try packageTree(&tree, 6);
    _ = try tree.rescan();
    try expectGreeterUnresolved(&tree, "package `demo`");

    var before = try tree.index.publish();
    defer before.deinit();
    const greeter_class = before.findDefinition("demo/Greeter.java", "Greeter").?;
    const baseline = tree.invocations();

    try tree.write("demo/Helper.java", "package demo;\n\nclass Helper {}\n");
    const outcome = try tree.rescan();

    try testing.expectEqual(@as(usize, 1), outcome.added);
    try testing.expectEqual(@as(usize, 0), outcome.changed);
    // The two other `demo` units, and nothing from `other`, the default package,
    // or Clojure — even though every one of them names `Helper` too.
    try testing.expectEqual(@as(usize, 2), outcome.invalidated);
    try testing.expectEqual(@as(usize, 3), outcome.analyzed);
    try testing.expectEqual(baseline + 3, tree.invocations());

    try expectGreeterResolvesTo(&tree, "demo/Helper.java");

    var after = try tree.index.publish();
    defer after.deinit();
    // Reanalysis preserved the dependent's identity; it was read, not rebuilt.
    try testing.expectEqual(greeter_class.id, after.findDefinition("demo/Greeter.java", "Greeter").?.id);
    const other = after.findDefinition("other/Other0.java", "Other0").?;
    try testing.expectEqual(model.ResolutionCategory.unresolved, (try referenceFrom(&after, other.id, "Helper")).resolution.category());
}

test "renaming, replacing, duplicating, moving, and removing a provider keep the dependent current" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try packageTree(&tree, 2);
    try tree.write("demo/Helper.java", "package demo;\n\nclass Helper {}\n");
    _ = try tree.rescan();
    try expectGreeterResolvesTo(&tree, "demo/Helper.java");

    var first = try tree.index.publish();
    defer first.deinit();
    const original = first.findDefinition("demo/Helper.java", "Helper").?;

    // Renamed: the old target is gone, and no current query still finds a fact
    // pointing at it.
    try tree.write("demo/Helper.java", "package demo;\n\nclass Assistant {}\n");
    var outcome = try tree.rescan();
    try testing.expectEqual(@as(usize, 1), outcome.changed);
    try expectGreeterUnresolved(&tree, "package `demo`");
    {
        var snapshot = try tree.index.publish();
        defer snapshot.deinit();
        try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .target = original.id }));
        try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .target = original.id, .freshness = null }));
    }
    try testing.expectEqual(@as(usize, 0), tree.index.graph.dependencies.count());

    // A new unique provider in another unit.
    try tree.write("demo/Help.java", "package demo;\n\nclass Helper {}\n");
    _ = try tree.rescan();
    try expectGreeterResolvesTo(&tree, "demo/Help.java");

    // A second one makes the name ambiguous, and removing it resolves it again.
    try tree.write("demo/HelpToo.java", "package demo;\n\nclass Helper {}\n");
    _ = try tree.rescan();
    try expectGreeterUnresolved(&tree, "ambiguous");
    try testing.expectEqual(@as(usize, 0), tree.index.graph.dependencies.count());
    try tree.remove("demo/HelpToo.java");
    outcome = try tree.rescan();
    try testing.expectEqual(@as(usize, 1), outcome.removed);
    try expectGreeterResolvesTo(&tree, "demo/Help.java");

    // Moving the provider to another package takes the binding with it.
    try tree.write("demo/Help.java", "package other;\n\nclass Helper {}\n");
    _ = try tree.rescan();
    try expectGreeterUnresolved(&tree, "package `demo`");

    // Back again, then deleted outright.
    try tree.write("demo/Help.java", "package demo;\n\nclass Helper {}\n");
    _ = try tree.rescan();
    try expectGreeterResolvesTo(&tree, "demo/Help.java");
    try tree.remove("demo/Help.java");
    _ = try tree.rescan();
    try expectGreeterUnresolved(&tree, "package `demo`");
}

test "a provider body edit reaches its dependent through the dependency alone" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try packageTree(&tree, 4);
    try tree.write("demo/Helper.java", "package demo;\n\nclass Helper {}\n");
    _ = try tree.rescan();

    var before = try tree.index.publish();
    defer before.deinit();
    const helper = before.findDefinition("demo/Helper.java", "Helper").?;
    const baseline = tree.invocations();

    try tree.write("demo/Helper.java", "package demo;\n\nclass Helper {\n    void added() {}\n}\n");
    const outcome = try tree.rescan();

    // The package's exports did not change, so only the unit that declared it
    // read `Helper` is read again: not `Unrelated`, not `other`.
    try testing.expectEqual(@as(usize, 1), outcome.changed);
    try testing.expectEqual(@as(usize, 1), outcome.invalidated);
    try testing.expectEqual(baseline + 2, tree.invocations());

    // The class kept its identity, and the fact still names it.
    try expectGreeterResolvesTo(&tree, "demo/Helper.java");
    var after = try tree.index.publish();
    defer after.deinit();
    try testing.expectEqual(helper.id, after.findDefinition("demo/Helper.java", "Helper").?.id);
}

test "a package export change costs its own package, not the repository" {
    const small = try packageChangeInvocations(4);
    const large = try packageChangeInvocations(24);
    // One added provider plus the two other `demo` units, at either size.
    try testing.expectEqual(@as(usize, 3), small);
    try testing.expectEqual(small, large);
}

fn packageChangeInvocations(others: usize) !usize {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try packageTree(&tree, others);
    _ = try tree.rescan();
    const baseline = tree.invocations();
    try tree.write("demo/Helper.java", "package demo;\n\nclass Helper {}\n");
    _ = try tree.rescan();
    return tree.invocations() - baseline;
}

test "a stale dependent survives its provider's removal without blocking publication" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try packageTree(&tree, 1);
    try tree.write("demo/Helper.java", "package demo;\n\nclass Helper {}\n");
    _ = try tree.rescan();

    var before = try tree.index.publish();
    defer before.deinit();
    const helper = before.findDefinition("demo/Helper.java", "Helper").?;
    const greeter = before.unitByPath("demo/Greeter.java").?;

    try tree.write("demo/Greeter.java", "package demo;\n\nclass Greeter {\n    Helper helper;\n");
    _ = try tree.rescan();
    try tree.remove("demo/Helper.java");
    const outcome = try tree.rescan();
    try testing.expectEqual(@as(usize, 1), outcome.removed);

    var after = try tree.index.publish();
    defer after.deinit();
    try testing.expectEqual(semidx.core.graph.UnitAnalysis.stale, after.unitAnalysis(greeter.id).?);
    try testing.expect(after.entityById(helper.id) == null);
    // The claim is recorded as what an earlier reading established, and does
    // not answer a current query.
    try testing.expectEqual(@as(usize, 0), after.countRelationships(.{ .target = helper.id }));
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{ .target = helper.id, .freshness = .stale }));

    // Repairing the dependent reads it against what exists now.
    try tree.write("demo/Greeter.java", demo_greeter);
    _ = try tree.rescan();
    try expectGreeterUnresolved(&tree, "package `demo`");
}

test "direct edits and removals keep cross-unit facts current without a scan" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    const greeter = try index.addUnit("demo/Greeter.java", .java, demo_greeter);
    const helper = try index.addUnit("demo/Helper.java", .java, "package demo;\nclass Helper {}\n");
    {
        var snapshot = try index.publish();
        defer snapshot.deinit();
        const class = snapshot.findDefinition("demo/Greeter.java", "Greeter").?;
        try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
            .source = class.id,
            .target = snapshot.findDefinition("demo/Helper.java", "Helper").?.id,
            .resolution = .fact,
        }));
    }

    _ = try index.applyEdit(helper, "package demo;\nclass Assistant {}\n");
    {
        var snapshot = try index.publish();
        defer snapshot.deinit();
        const class = snapshot.findDefinition("demo/Greeter.java", "Greeter").?;
        try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
            .source = class.id,
            .designator = "Helper",
            .resolution = .unresolved,
        }));
    }

    _ = try index.applyEdit(helper, "package demo;\nclass Helper {}\n");
    try index.removeUnit(helper);
    var snapshot = try index.publish();
    defer snapshot.deinit();
    try testing.expectEqual(semidx.core.graph.UnitAnalysis.current, snapshot.unitAnalysis(greeter).?);
    const class = snapshot.findDefinition("demo/Greeter.java", "Greeter").?;
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .source = class.id,
        .designator = "Helper",
        .resolution = .unresolved,
    }));
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
    try testing.expectEqual(@as(usize, 8), before.countEntities(.{ .kind = .definition }));
    try testing.expectEqual(@as(usize, 9), after.countEntities(.{ .kind = .definition }));
}

// -- Plan 004: Zig fixture coverage -----------------------------------------

const zig_path = "zig/greeter.zig";

const ZigFixture = struct {
    index: semidx.Index,
    unit: model.SourceUnitId,

    fn init(gpa: std.mem.Allocator) !ZigFixture {
        var index = try semidx.Index.init(gpa, build_options.fixtures_dir);
        errdefer index.deinit();
        const source = try loadFixture(gpa, zig_path);
        defer gpa.free(source);
        const unit = try index.addUnit(zig_path, .zig, source);
        return .{ .index = index, .unit = unit };
    }

    fn deinit(self: *ZigFixture) void {
        self.index.deinit();
        self.* = undefined;
    }

    fn edit(self: *ZigFixture, relative: []const u8) !semidx.reconcile.Outcome {
        const gpa = self.index.graph.gpa;
        const source = try loadFixture(gpa, relative);
        defer gpa.free(source);
        return self.index.applyEdit(self.unit, source);
    }
};

fn hasDiagnosticContaining(snapshot: *const semidx.Snapshot, kind: model.DiagnosticKind, fragment: []const u8) bool {
    for (snapshot.diagnostics) |diagnostic| {
        if (diagnostic.kind != kind) continue;
        if (std.mem.indexOf(u8, diagnostic.message, fragment) != null) return true;
    }
    return false;
}

/// The one current definition named `name` inside `container` in the Zig
/// fixture.
fn zigMember(snapshot: *const semidx.Snapshot, container: []const u8, name: []const u8) ?model.Entity {
    var found = snapshot.entitiesMatching(.{ .kind = .definition, .path = zig_path, .name = name });
    while (found.next()) |entity| {
        const path = entity.identity.container_path;
        if (path.len == 1 and std.mem.eql(u8, path[0], container)) return entity;
    }
    return null;
}

test "the zig fixture yields its top-level functions and containers as definitions" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var snapshot = try fixture.index.publish();
    defer snapshot.deinit();

    try testing.expectEqual(
        semidx.core.graph.UnitAnalysis.current,
        snapshot.unitAnalysis(fixture.unit).?,
    );

    const greeter = snapshot.findDefinition(zig_path, "Greeter").?;
    const mood = snapshot.findDefinition(zig_path, "Mood").?;
    const greeting = snapshot.findDefinition(zig_path, "greeting").?;
    const greet = snapshot.findDefinition(zig_path, "greet").?;
    const announce = snapshot.findDefinition(zig_path, "announce").?;

    try testing.expectEqualStrings("container", greeter.identity.role);
    try testing.expectEqualStrings("struct", greeter.extension.get("zig.container").?);
    try testing.expectEqualStrings("enum", mood.extension.get("zig.container").?);
    for ([_]model.Entity{ greeting, greet, announce }) |function| {
        try testing.expectEqualStrings("function", function.identity.role);
        try testing.expectEqualStrings("function", function.extension.get("zig.construct").?);
    }
    for ([_]model.Entity{ greeter, mood, greeting, greet, announce }) |definition| {
        try testing.expectEqual(model.EntityKind.definition, definition.kind);
        try testing.expectEqual(model.Language.zig, definition.identity.language.?);
        try testing.expectEqualStrings("zig", definition.extension.namespace);
        try testing.expectEqual(@as(usize, 0), definition.identity.container_path.len);
    }
    // The direct member function of `Greeter` is a sixth definition.
    try testing.expectEqual(@as(usize, 6), snapshot.countEntities(.{ .kind = .definition }));

    // Ingestion says the repository contains the file; the frontend says the
    // file introduces each covered declaration, as a fact of its own.
    const file = snapshot.findEntity(.{ .kind = .file, .path = zig_path }).?;
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{ .kind = .contains, .target = file.id }));
    try testing.expectEqual(@as(usize, 5), snapshot.countRelationships(.{
        .kind = .defines,
        .source = file.id,
        .resolution = .fact,
    }));
    try testing.expect(snapshot.countAssertions(.{ .producer = "frontend.zig", .resolution = .fact }) >= 10);

    // The `name` field, the import, the constant, and the test are not
    // definitions, and they are reported instead of looking absent.
    for ([_][]const u8{ "name", "std", "limit" }) |name| {
        try testing.expect(snapshot.findDefinition(zig_path, name) == null);
    }
    try testing.expect(hasDiagnosticContaining(&snapshot, .unsupported_construct, "2 top-level `variable_declaration`"));
    try testing.expect(hasDiagnosticContaining(&snapshot, .unsupported_construct, "`test_declaration`"));
    try testing.expect(hasDiagnosticContaining(&snapshot, .unsupported_construct, "`container_field` declared inside a top-level container"));
    try testing.expect(!hasDiagnosticContaining(&snapshot, .unsupported_construct, "`function_declaration` declared inside a top-level container"));

    // The `greet` member of `Greeter` is a definition of its own, introduced by
    // the container rather than by the file, and distinct from top-level `greet`.
    try testing.expectEqual(@as(usize, 2), snapshot.countEntities(.{ .kind = .definition, .name = "greet" }));
    const member = zigMember(&snapshot, "Greeter", "greet").?;
    try testing.expect(member.id != greet.id);
    try testing.expectEqualStrings("function", member.identity.role);
    try testing.expectEqualStrings("function", member.extension.get("zig.construct").?);
    try testing.expectEqualStrings("container_member", member.extension.get("zig.placement").?);
    try testing.expect(greet.extension.get("zig.placement") == null);
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .defines,
        .source = greeter.id,
        .target = member.id,
        .resolution = .fact,
    }));
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .kind = .defines, .source = file.id, .target = member.id }));
    // Its body is analyzed like any covered function's, and holds no call.
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .kind = .calls, .source = member.id }));
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
    try testing.expectEqual(@as(usize, 0), snapshot.countDiagnostics(.confirmed_absence));
}

test "a zig body edit preserves every definition id" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greeting_before = before.findDefinition(zig_path, "greeting").?;
    const announce_before = before.findDefinition(zig_path, "announce").?;

    const outcome = try fixture.edit("zig/edits/01_body_edit.zig");
    try testing.expect(outcome.applied);
    try testing.expectEqual(@as(usize, 6), outcome.preserved);
    try testing.expectEqual(@as(usize, 0), outcome.created);
    try testing.expectEqual(@as(usize, 0), outcome.removed);
    try testing.expectEqual(@as(usize, 0), outcome.lost);

    var after = try fixture.index.publish();
    defer after.deinit();
    try testing.expectEqual(greeting_before.id, after.findDefinition(zig_path, "greeting").?.id);
    try testing.expectEqual(announce_before.id, after.findDefinition(zig_path, "announce").?.id);
    try testing.expect(before.revision < after.revision);
}

test "an added zig definition leaves the others untouched" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greet_before = before.findDefinition(zig_path, "greet").?;

    const outcome = try fixture.edit("zig/edits/02_added_definition.zig");
    try testing.expectEqual(@as(usize, 6), outcome.preserved);
    try testing.expectEqual(@as(usize, 1), outcome.created);
    try testing.expectEqual(@as(usize, 0), outcome.lost);

    var after = try fixture.index.publish();
    defer after.deinit();
    try testing.expectEqual(greet_before.id, after.findDefinition(zig_path, "greet").?.id);
    const farewell = after.findDefinition(zig_path, "farewell").?;
    try testing.expectEqual(
        model.IdentityEventKind.created,
        after.identityEventFor(farewell.id, outcome.revision).?.kind,
    );
}

test "a renamed zig definition is reported as identity loss with its replacement" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greeting_before = before.findDefinition(zig_path, "greeting").?;
    const greet_before = before.findDefinition(zig_path, "greet").?;

    const outcome = try fixture.edit("zig/edits/03_renamed_definition.zig");
    try testing.expectEqual(@as(usize, 1), outcome.lost);
    try testing.expectEqual(@as(usize, 1), outcome.created);
    try testing.expectEqual(@as(usize, 5), outcome.preserved);
    try testing.expectEqual(@as(usize, 0), outcome.removed);

    var after = try fixture.index.publish();
    defer after.deinit();
    try testing.expectEqual(greet_before.id, after.findDefinition(zig_path, "greet").?.id);

    const event = after.identityEventFor(greeting_before.id, outcome.revision).?;
    try testing.expectEqual(model.IdentityEventKind.lost, event.kind);
    const salutation = after.findDefinition(zig_path, "salutation").?;
    try testing.expectEqual(salutation.id, event.replacement.?);
    try testing.expect(after.entityById(greeting_before.id) == null);
}

test "editing the zig fixture into unparsable source stops its facts being current" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greet_before = before.findDefinition(zig_path, "greet").?;

    const outcome = try fixture.edit("zig/edits/05_unparsable.zig");
    try testing.expect(!outcome.applied);

    var after = try fixture.index.publish();
    defer after.deinit();
    try testing.expectEqual(
        semidx.core.graph.UnitAnalysis.stale,
        after.unitAnalysis(fixture.unit).?,
    );
    try testing.expectEqual(@as(usize, 1), after.countDiagnostics(.analysis_failed));
    try testing.expect(after.findDefinition(zig_path, "greet") == null);
    try testing.expectEqual(greet_before.id, after.findEntity(.{
        .kind = .definition,
        .path = zig_path,
        .name = "greet",
        .freshness = .stale,
    }).?.id);

    // Nothing was deleted, so repairing the source restores the same entities.
    const repaired = try fixture.edit("zig/edits/01_body_edit.zig");
    try testing.expect(repaired.applied);
    try testing.expectEqual(@as(usize, 6), repaired.preserved);
    try testing.expectEqual(@as(usize, 0), repaired.created);

    var repaired_snapshot = try fixture.index.publish();
    defer repaired_snapshot.deinit();
    try testing.expectEqual(greet_before.id, repaired_snapshot.findDefinition(zig_path, "greet").?.id);
    try testing.expectEqual(@as(usize, 0), repaired_snapshot.countDiagnostics(.analysis_failed));
}

test "a zig member body edit preserves the member's identity" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const member_before = zigMember(&before, "Greeter", "greet").?;

    const outcome = try fixture.edit("zig/edits/07_member_body_edit.zig");
    try testing.expect(outcome.applied);
    try testing.expectEqual(@as(usize, 6), outcome.preserved);
    try testing.expectEqual(@as(usize, 0), outcome.created);
    try testing.expectEqual(@as(usize, 0), outcome.lost);
    try testing.expectEqual(@as(usize, 0), outcome.removed);

    var after = try fixture.index.publish();
    defer after.deinit();
    const member_after = zigMember(&after, "Greeter", "greet").?;
    try testing.expectEqual(member_before.id, member_after.id);
    try testing.expectEqual(model.IdentityEventKind.preserved, after.identityEventFor(member_before.id, outcome.revision).?.kind);
}

test "a renamed zig member is reported as identity loss with its replacement" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const member_before = zigMember(&before, "Greeter", "greet").?;
    const greet_before = before.findDefinition(zig_path, "greet").?;

    const outcome = try fixture.edit("zig/edits/08_member_renamed.zig");
    try testing.expectEqual(@as(usize, 5), outcome.preserved);
    try testing.expectEqual(@as(usize, 1), outcome.lost);
    try testing.expectEqual(@as(usize, 1), outcome.created);
    try testing.expectEqual(@as(usize, 0), outcome.removed);

    var after = try fixture.index.publish();
    defer after.deinit();
    const welcome = zigMember(&after, "Greeter", "welcome").?;
    const event = after.identityEventFor(member_before.id, outcome.revision).?;
    try testing.expectEqual(model.IdentityEventKind.lost, event.kind);
    try testing.expectEqual(welcome.id, event.replacement.?);
    // The top-level function of the member's old name is not its replacement.
    try testing.expectEqual(greet_before.id, after.findDefinition(zig_path, "greet").?.id);
    try testing.expect(zigMember(&after, "Greeter", "greet") == null);
}

test "renaming a zig container makes its member's identity loss observable" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const container_before = before.findDefinition(zig_path, "Greeter").?;
    const member_before = zigMember(&before, "Greeter", "greet").?;

    const outcome = try fixture.edit("zig/edits/09_container_renamed.zig");
    try testing.expectEqual(@as(usize, 4), outcome.preserved);
    try testing.expectEqual(@as(usize, 2), outcome.lost);
    try testing.expectEqual(@as(usize, 2), outcome.created);
    try testing.expectEqual(@as(usize, 0), outcome.removed);

    var after = try fixture.index.publish();
    defer after.deinit();
    const welcomer = after.findDefinition(zig_path, "Welcomer").?;
    const member_after = zigMember(&after, "Welcomer", "greet").?;
    try testing.expectEqual(welcomer.id, after.identityEventFor(container_before.id, outcome.revision).?.replacement.?);
    const event = after.identityEventFor(member_before.id, outcome.revision).?;
    try testing.expectEqual(model.IdentityEventKind.lost, event.kind);
    try testing.expectEqual(member_after.id, event.replacement.?);
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{ .kind = .defines, .source = welcomer.id, .target = member_after.id }));
}

test "same-unit zig calls are current facts and every other callee stays unresolved" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var snapshot = try fixture.index.publish();
    defer snapshot.deinit();

    const greeting = snapshot.findDefinition(zig_path, "greeting").?;
    const greet = snapshot.findDefinition(zig_path, "greet").?;
    const announce = snapshot.findDefinition(zig_path, "announce").?;

    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .calls,
        .source = greet.id,
        .target = greeting.id,
        .resolution = .fact,
    }));
    // `greet()` inside the print arguments is the top-level function.
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .calls,
        .source = announce.id,
        .target = greet.id,
        .resolution = .fact,
    }));

    // `greeter.greet()` names the container member, not the top-level `greet`,
    // and nothing here resolves members, so it is not retargeted to either.
    for ([_][]const u8{ "std.debug.print", "greeter.greet", "report" }) |designator| {
        try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
            .kind = .calls,
            .source = announce.id,
            .designator = designator,
            .resolution = .unresolved,
        }));
    }
    try testing.expectEqual(@as(usize, 4), snapshot.countRelationships(.{ .source = announce.id, .kind = .calls }));
    try testing.expectEqual(@as(usize, 4), snapshot.countRelationships(.{ .source = announce.id, .reference_query = true }));
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .source = announce.id, .kind = .references }));

    // The call facts carry a range and the Zig producer, and the call inside
    // the test block produced nothing.
    var facts = snapshot.relationships(.{ .kind = .calls, .resolution = .fact });
    var fact_count: usize = 0;
    while (facts.next()) |fact| : (fact_count += 1) {
        try testing.expectEqualStrings("frontend.zig", fact.producer.name);
        const evidence = fact.evidence.?;
        try testing.expectEqual(fixture.unit, evidence.unit);
        try testing.expect(evidence.range.end_byte > evidence.range.start_byte);
    }
    try testing.expectEqual(@as(usize, 2), fact_count);
    try testing.expectEqual(@as(usize, 5), snapshot.countRelationships(.{ .kind = .calls }));
}

test "a zig callee body edit keeps its callers' facts current" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greeting_before = before.findDefinition(zig_path, "greeting").?;
    const greet_before = before.findDefinition(zig_path, "greet").?;

    _ = try fixture.edit("zig/edits/01_body_edit.zig");

    var after = try fixture.index.publish();
    defer after.deinit();
    try testing.expectEqual(greeting_before.id, after.findDefinition(zig_path, "greeting").?.id);
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{
        .kind = .calls,
        .source = greet_before.id,
        .target = greeting_before.id,
        .resolution = .fact,
        .freshness = .current,
    }));
    try testing.expectEqual(@as(usize, 0), after.countAssertions(.{ .freshness = .stale }));
}

test "renaming a zig callee alone leaves its call unresolved rather than retargeted" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greeting_before = before.findDefinition(zig_path, "greeting").?;
    const greet_before = before.findDefinition(zig_path, "greet").?;

    const outcome = try fixture.edit("zig/edits/06_callee_renamed.zig");
    try testing.expectEqual(@as(usize, 1), outcome.lost);
    try testing.expectEqual(@as(usize, 1), outcome.created);

    var after = try fixture.index.publish();
    defer after.deinit();
    const salutation = after.findDefinition(zig_path, "salutation").?;
    try testing.expectEqual(salutation.id, after.identityEventFor(greeting_before.id, outcome.revision).?.replacement.?);

    // `greet` still says `greeting()`, which no longer names anything.
    try testing.expectEqual(@as(usize, 0), after.countRelationships(.{ .kind = .calls, .source = greet_before.id, .target = salutation.id }));
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{
        .kind = .calls,
        .source = greet_before.id,
        .designator = "greeting",
        .resolution = .unresolved,
    }));
}

test "renaming a zig callee together with its call follows the replacement" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const greet_before = before.findDefinition(zig_path, "greet").?;

    _ = try fixture.edit("zig/edits/03_renamed_definition.zig");

    var after = try fixture.index.publish();
    defer after.deinit();
    const salutation = after.findDefinition(zig_path, "salutation").?;
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{
        .kind = .calls,
        .source = greet_before.id,
        .target = salutation.id,
        .resolution = .fact,
    }));
}

test "a zig call moves from unresolved to resolved when its target appears" {
    var fixture = try ZigFixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const announce_before = before.findDefinition(zig_path, "announce").?;

    const outcome = try fixture.edit("zig/edits/04_reference_resolved.zig");
    try testing.expectEqual(@as(usize, 6), outcome.preserved);
    try testing.expectEqual(@as(usize, 1), outcome.created);

    var after = try fixture.index.publish();
    defer after.deinit();
    const report = after.findDefinition(zig_path, "report").?;
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

test "adding a zig unit leaves java and clojure analysis unchanged" {
    var fixture = try Fixture.init(testing.allocator);
    defer fixture.deinit();

    var before = try fixture.index.publish();
    defer before.deinit();
    const java_assertions = before.countAssertions(.{ .producer = "frontend.java" });
    const clojure_assertions = before.countAssertions(.{ .producer = "frontend.clojure" });

    const source = try loadFixture(testing.allocator, zig_path);
    defer testing.allocator.free(source);
    _ = try fixture.index.addUnit(zig_path, .zig, source);

    var after = try fixture.index.publish();
    defer after.deinit();
    try testing.expectEqual(java_assertions, after.countAssertions(.{ .producer = "frontend.java" }));
    try testing.expectEqual(clojure_assertions, after.countAssertions(.{ .producer = "frontend.clojure" }));
    try testing.expectEqual(@as(usize, 8 + 6), after.countEntities(.{ .kind = .definition }));
    // A Java or Clojure call named `greet` did not become a Zig fact, or the
    // other way round: every call fact stays inside its own language's unit.
    var facts = after.relationships(.{ .kind = .calls, .resolution = .fact });
    while (facts.next()) |fact| {
        const target = after.entityById(fact.claim.relationship.target.entity).?;
        const evidence = fact.evidence.?;
        try testing.expectEqual(evidence.unit, target.evidence.?.unit);
    }
}

// -- Plan 006: Zig local imports ----------------------------------------------

const imports_dir = "zig/imports/";

/// Copies the local-import fixture units into a scannable tree, at the same
/// root-relative paths they have under the fixtures directory.
fn writeImportFixtures(tree: *Tree) !void {
    const gpa = testing.allocator;
    for ([_][]const u8{ "wire.zig", "session.zig", "support/util.zig" }) |name| {
        const path = try std.mem.concat(gpa, u8, &.{ imports_dir, name });
        defer gpa.free(path);
        const source = try loadFixture(gpa, path);
        defer gpa.free(source);
        try tree.write(path, source);
    }
}

/// Whether `dependent` currently declares a dependency on `provider`.
fn dependsOn(index: *semidx.Index, dependent: []const u8, provider: []const u8) bool {
    const from = index.graph.unitByPath(dependent) orelse return false;
    const to = index.graph.unitByPath(provider) orelse return false;
    for (index.graph.dependencies.declarations.items) |declaration| {
        if (declaration.dependent == from and declaration.provider == to) return true;
    }
    return false;
}

fn declaredDependencies(index: *semidx.Index, dependent: []const u8) usize {
    const from = index.graph.unitByPath(dependent) orelse return 0;
    var count: usize = 0;
    for (index.graph.dependencies.declarations.items) |declaration| {
        if (declaration.dependent == from) count += 1;
    }
    return count;
}

test "the local-import fixtures depend on exactly the units their established aliases name" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try writeImportFixtures(&tree);
    const outcome = try tree.rescan();
    try testing.expectEqual(@as(usize, 3), outcome.added);

    const session = imports_dir ++ "session.zig";
    const util = imports_dir ++ "support/util.zig";
    const wire = imports_dir ++ "wire.zig";
    try testing.expect(dependsOn(&tree.index, session, wire));
    try testing.expect(dependsOn(&tree.index, session, util));
    try testing.expect(dependsOn(&tree.index, util, session));
    try testing.expectEqual(@as(usize, 2), declaredDependencies(&tree.index, session));
    try testing.expectEqual(@as(usize, 1), declaredDependencies(&tree.index, util));
    try testing.expectEqual(@as(usize, 0), declaredDependencies(&tree.index, wire));

    var snapshot = try tree.index.publish();
    defer snapshot.deinit();
    for ([_][]const u8{
        "`const outside = @import(\"../../../outside.zig\")` establishes no local import alias: the path escapes the indexed root",
        "`const upper = @import(\"Wire.zig\")` establishes no local import alias: no indexed Zig source unit has the path `zig/imports/Wire.zig`",
        "`const absent = @import(\"absent.zig\")` establishes no local import alias: no indexed Zig source unit has the path `zig/imports/absent.zig`",
        "`const twin = @import(\"wire.zig\")` establishes no local import alias: the unit's top level declares this name more than once",
        "`const twin = @import(\"support/util.zig\")` establishes no local import alias: the unit's top level declares this name more than once",
    }) |message| {
        try testing.expect(hasDiagnosticContaining(&snapshot, .unsupported_construct, message));
    }
    try testing.expect(!hasDiagnosticContaining(&snapshot, .unsupported_construct, "`const std = @import"));
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
    // No import is a graph relationship: only containment, definition, and
    // calls come out of these units.
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .kind = .references }));
}

const importer_zig =
    \\const provider = @import("../b/provider.zig");
    \\pub fn run() void {
    \\    provider.go();
    \\}
    \\
;
const provider_zig = "pub fn go() void {}\n";

test "a zig importer scanned before its provider depends on it after the same scan" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    // Units are analyzed in path order, so the importer is read while its
    // provider is registered but not yet analyzed, and read again once it is.
    try tree.write("a/importer.zig", importer_zig);
    try tree.write("b/provider.zig", provider_zig);
    try tree.write("c/unrelated.zig", "pub fn idle() void {}\n");
    const first = try tree.rescan();
    try testing.expectEqual(@as(usize, 3), first.added);
    try testing.expectEqual(@as(usize, 1), first.invalidated);
    try testing.expect(dependsOn(&tree.index, "a/importer.zig", "b/provider.zig"));

    // A provider edit reaches the importer and nothing else.
    try tree.write("b/provider.zig", "pub fn go() void {\n    return;\n}\n");
    const edited = try tree.rescan();
    try testing.expectEqual(@as(usize, 1), edited.changed);
    try testing.expectEqual(@as(usize, 1), edited.invalidated);
    try testing.expectEqual(@as(usize, 2), edited.analyzed);
}

test "a zig provider scanned before its importer costs no second read" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write("a/provider.zig", provider_zig);
    try tree.write("b/importer.zig",
        \\const provider = @import("../a/provider.zig");
        \\pub fn run() void {}
        \\
    );
    const first = try tree.rescan();
    try testing.expectEqual(@as(usize, 0), first.invalidated);
    try testing.expect(dependsOn(&tree.index, "b/importer.zig", "a/provider.zig"));
}

test "moving or removing a zig provider reanalyzes its importer" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write("a/importer.zig", importer_zig);
    try tree.write("b/provider.zig", provider_zig);
    _ = try tree.rescan();

    // The provider's contents are unchanged, so it is not reanalyzed; the
    // importer found it by the path it no longer has.
    try tree.move("b/provider.zig", "b/moved.zig");
    const moved = try tree.rescan();
    try testing.expectEqual(@as(usize, 1), moved.renamed);
    try testing.expectEqual(@as(usize, 1), moved.invalidated);
    try testing.expectEqual(@as(usize, 1), moved.analyzed);
    try testing.expectEqual(@as(usize, 0), declaredDependencies(&tree.index, "a/importer.zig"));
    {
        var snapshot = try tree.index.publish();
        defer snapshot.deinit();
        try testing.expect(hasDiagnosticContaining(&snapshot, .unsupported_construct, "no indexed Zig source unit has the path `b/provider.zig`"));
    }

    // Moved back, a later edit of the importer finds it again; removal then
    // withdraws the dependency by reanalyzing the importer.
    try tree.move("b/moved.zig", "b/provider.zig");
    try tree.write("a/importer.zig", importer_zig ++ "\n");
    _ = try tree.rescan();
    try testing.expect(dependsOn(&tree.index, "a/importer.zig", "b/provider.zig"));
    try tree.remove("b/provider.zig");
    const removed = try tree.rescan();
    try testing.expectEqual(@as(usize, 1), removed.removed);
    try testing.expectEqual(@as(usize, 1), removed.invalidated);
    try testing.expectEqual(@as(usize, 0), declaredDependencies(&tree.index, "a/importer.zig"));
}

test "a zig provider added after its importer is not noticed until the importer is reanalyzed" {
    // The named residual risk of Plan 006: a missing import path is read as
    // no unit, which declares nothing, so adding the unit later reaches no one.
    // The importer's calls stay unresolved; nothing false is claimed.
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write("a/importer.zig", importer_zig);
    _ = try tree.rescan();
    try testing.expectEqual(@as(usize, 0), declaredDependencies(&tree.index, "a/importer.zig"));

    try tree.write("b/provider.zig", provider_zig);
    const added = try tree.rescan();
    try testing.expectEqual(@as(usize, 1), added.added);
    try testing.expectEqual(@as(usize, 0), added.invalidated);
    try testing.expectEqual(@as(usize, 0), declaredDependencies(&tree.index, "a/importer.zig"));

    try tree.write("a/importer.zig", importer_zig ++ "\n");
    _ = try tree.rescan();
    try testing.expect(dependsOn(&tree.index, "a/importer.zig", "b/provider.zig"));
}

const session_path = imports_dir ++ "session.zig";
const wire_path = imports_dir ++ "wire.zig";
const util_path = imports_dir ++ "support/util.zig";

/// The one current definition named `name` in the unit at `path`, directly in
/// `container` when one is given and at the top level otherwise.
fn definitionIn(snapshot: *const semidx.Snapshot, path: []const u8, container: ?[]const u8, name: []const u8) ?model.Entity {
    var found = snapshot.entitiesMatching(.{ .kind = .definition, .path = path, .name = name });
    while (found.next()) |entity| {
        const containers = entity.identity.container_path;
        if (container) |expected| {
            if (containers.len == 1 and std.mem.eql(u8, containers[0], expected)) return entity;
        } else if (containers.len == 0) {
            return entity;
        }
    }
    return null;
}

fn callFacts(snapshot: *const semidx.Snapshot, from: model.Entity, to: model.Entity) usize {
    return snapshot.countRelationships(.{ .kind = .calls, .source = from.id, .target = to.id, .resolution = .fact });
}

fn expectUnresolvedCall(snapshot: *const semidx.Snapshot, from: model.Entity, designator: []const u8, fragment: []const u8) !void {
    var calls = snapshot.relationships(.{ .kind = .calls, .source = from.id, .designator = designator });
    const call = calls.next() orelse {
        std.debug.print("no current call `{s}` from `{s}`\n", .{ designator, from.identity.name.? });
        return error.TestExpectedCall;
    };
    try testing.expect(!call.resolution.isFact());
    const explanation = call.resolution.unresolved.explanation;
    if (std.mem.indexOf(u8, explanation, fragment) == null) {
        std.debug.print("call `{s}`: expected \"{s}\" in \"{s}\"\n", .{ designator, fragment, explanation });
        return error.TestUnexpectedExplanation;
    }
}

test "exact local-import calls are cross-unit facts and every other qualified call stays unresolved" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try writeImportFixtures(&tree);
    _ = try tree.rescan();

    var snapshot = try tree.index.publish();
    defer snapshot.deinit();
    const run = definitionIn(&snapshot, session_path, null, "run").?;
    const shadowed = definitionIn(&snapshot, session_path, null, "shadowed").?;
    const helper = definitionIn(&snapshot, session_path, null, "helper").?;
    const send = definitionIn(&snapshot, session_path, "Session", "send").?;
    const flush = definitionIn(&snapshot, session_path, "Session", "flush").?;
    const write_string = definitionIn(&snapshot, wire_path, null, "writeString").?;
    const clean = definitionIn(&snapshot, util_path, null, "clean").?;

    try testing.expectEqual(@as(usize, 1), callFacts(&snapshot, run, write_string));
    try testing.expectEqual(@as(usize, 1), callFacts(&snapshot, run, clean));
    try testing.expectEqual(@as(usize, 1), callFacts(&snapshot, clean, run));
    try testing.expectEqual(@as(usize, 1), callFacts(&snapshot, send, write_string));
    try testing.expectEqual(@as(usize, 1), callFacts(&snapshot, flush, helper));
    try testing.expectEqual(@as(usize, 5), snapshot.countRelationships(.{ .kind = .calls, .resolution = .fact }));

    // A cross-unit fact carries the Zig producer, a current freshness, the
    // caller's own evidence, and a dependency on the unit it reached into.
    var facts = snapshot.relationships(.{ .kind = .calls, .target = write_string.id });
    var fact_count: usize = 0;
    while (facts.next()) |fact| : (fact_count += 1) {
        try testing.expect(fact.resolution.isFact());
        try testing.expectEqualStrings("frontend.zig", fact.producer.name);
        try testing.expectEqual(model.Freshness.current, snapshot.assertionFreshness(fact));
        const evidence = fact.evidence.?;
        try testing.expectEqual(snapshot.unitByPath(session_path).?.id, evidence.unit);
        try testing.expectEqualStrings("wire.writeString", evidence.text);
    }
    // Each resolved occurrence answers an all-references query once.
    try testing.expectEqual(@as(usize, 2), fact_count);
    try testing.expectEqual(@as(usize, 2), snapshot.countRelationships(.{ .target = write_string.id, .reference_query = true }));
    try testing.expect(dependsOn(&tree.index, session_path, wire_path));

    try expectUnresolvedCall(&snapshot, send, "self.flush", "qualifier is a parameter or local binding");
    try expectUnresolvedCall(&snapshot, flush, "reset", "enclosing container declares a member");
    try expectUnresolvedCall(&snapshot, run, "wire.hidden", "no current top-level `pub fn`");
    try expectUnresolvedCall(&snapshot, run, "wire.twice", "no current top-level `pub fn`");
    try expectUnresolvedCall(&snapshot, run, "wire.flushAll", "no current top-level `pub fn`");
    try expectUnresolvedCall(&snapshot, run, "wire.Frame.encode", "not a bare name or a name qualified by a local import alias");
    try expectUnresolvedCall(&snapshot, run, "std.debug.print", "not a bare name or a name qualified by a local import alias");
    try expectUnresolvedCall(&snapshot, run, "outside.run", "the path escapes the indexed root");
    try expectUnresolvedCall(&snapshot, run, "upper.run", "no indexed Zig source unit has the path `zig/imports/Wire.zig`");
    try expectUnresolvedCall(&snapshot, run, "absent.run", "no indexed Zig source unit has the path `zig/imports/absent.zig`");
    try expectUnresolvedCall(&snapshot, run, "twin.run", "declares this name more than once");
    try expectUnresolvedCall(&snapshot, run, "copy.writeString", "not a top-level `@import` alias");
    try expectUnresolvedCall(&snapshot, shadowed, "wire.writeString", "qualifier is a parameter or local binding");

    // Calls in the nested container's member are not recorded, and the
    // nested container is reported instead.
    try testing.expect(definitionIn(&snapshot, session_path, "Nested", "deep") == null);
    try testing.expect(hasDiagnosticContaining(&snapshot, .unsupported_construct, "`variable_declaration` declared inside a top-level container"));
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
}

test "provider edits update local-import calls without editing the importer" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try writeImportFixtures(&tree);
    const greeter = try loadFixture(testing.allocator, zig_path);
    defer testing.allocator.free(greeter);
    try tree.write(zig_path, greeter);
    _ = try tree.rescan();

    var before = try tree.index.publish();
    defer before.deinit();
    const run = definitionIn(&before, session_path, null, "run").?;
    const send = definitionIn(&before, session_path, "Session", "send").?;
    const write_string = definitionIn(&before, wire_path, null, "writeString").?;

    // A body edit keeps the target's identity and the facts reaching it. The
    // importer and, through the coarse dependency on it, `util.zig` are read
    // again; the unrelated unit is not.
    try writeFixtureInto(&tree, "wire_01_body_edit.zig");
    const body_edit = try tree.rescan();
    try testing.expectEqual(@as(usize, 1), body_edit.changed);
    try testing.expectEqual(@as(usize, 2), body_edit.invalidated);
    try testing.expectEqual(@as(usize, 3), body_edit.analyzed);
    {
        var after = try tree.index.publish();
        defer after.deinit();
        try testing.expectEqual(write_string.id, definitionIn(&after, wire_path, null, "writeString").?.id);
        try testing.expectEqual(@as(usize, 1), callFacts(&after, run, write_string));
        try testing.expectEqual(@as(usize, 1), callFacts(&after, send, write_string));
    }

    // An export the importer already calls appears: the call becomes a fact.
    try writeFixtureInto(&tree, "wire_02_added_export.zig");
    _ = try tree.rescan();
    {
        var after = try tree.index.publish();
        defer after.deinit();
        const flush_all = definitionIn(&after, wire_path, null, "flushAll").?;
        try testing.expectEqual(@as(usize, 1), callFacts(&after, run, flush_all));
    }

    // Renamed: identity is lost, and no current fact names the lost entity.
    try writeFixtureInto(&tree, "wire_03_renamed_export.zig");
    _ = try tree.rescan();
    {
        var after = try tree.index.publish();
        defer after.deinit();
        try testing.expect(after.entityById(write_string.id) == null);
        try testing.expectEqual(@as(usize, 0), after.countRelationships(.{ .target = write_string.id }));
        try expectUnresolvedCall(&after, run, "wire.writeString", "no current top-level `pub fn`");
        try expectUnresolvedCall(&after, send, "wire.writeString", "no current top-level `pub fn`");
    }

    // No longer `pub`: not exported, so not a target.
    try writeFixtureInto(&tree, "wire_04_export_made_private.zig");
    _ = try tree.rescan();
    {
        var after = try tree.index.publish();
        defer after.deinit();
        const private = definitionIn(&after, wire_path, null, "writeString").?;
        try testing.expect(private.extension.get("zig.export") == null);
        try testing.expectEqual(@as(usize, 0), after.countRelationships(.{ .kind = .calls, .target = private.id }));
        try expectUnresolvedCall(&after, run, "wire.writeString", "no current top-level `pub fn`");
    }

    // Back to the original, then broken: a provider whose analysis is not
    // current offers no target, and its stale definitions are not called.
    try writeFixtureInto(&tree, "../wire.zig");
    _ = try tree.rescan();
    const restored = blk: {
        var after = try tree.index.publish();
        defer after.deinit();
        const restored = definitionIn(&after, wire_path, null, "writeString").?;
        try testing.expectEqual(@as(usize, 1), callFacts(&after, run, restored));
        break :blk restored;
    };
    try tree.write(wire_path, "pub fn writeString( usize {\n");
    const broken = try tree.rescan();
    try testing.expectEqual(@as(usize, 1), broken.changed);
    try testing.expectEqual(@as(usize, 2), broken.invalidated);
    {
        var after = try tree.index.publish();
        defer after.deinit();
        try testing.expectEqual(semidx.core.graph.UnitAnalysis.stale, after.unitByPath(wire_path).?.analysis());
        try expectUnresolvedCall(&after, run, "wire.writeString", "analysis is not current");
        try testing.expectEqual(@as(usize, 0), after.countRelationships(.{ .kind = .calls, .target = restored.id }));
        // The call into the other provider is untouched.
        try testing.expectEqual(@as(usize, 1), callFacts(&after, run, definitionIn(&after, util_path, null, "clean").?));
    }

    // Removed: the alias no longer names a unit.
    try tree.remove(wire_path);
    const removed = try tree.rescan();
    try testing.expectEqual(@as(usize, 1), removed.removed);
    {
        var after = try tree.index.publish();
        defer after.deinit();
        try expectUnresolvedCall(&after, run, "wire.writeString", "no indexed Zig source unit has the path `zig/imports/wire.zig`");
        try testing.expectEqual(@as(usize, 1), callFacts(&after, run, definitionIn(&after, util_path, null, "clean").?));
    }
}

/// Writes `imports/edits/<name>` over the provider `wire.zig` in the tree.
fn writeFixtureInto(tree: *Tree, name: []const u8) !void {
    const gpa = testing.allocator;
    const fixture = try std.mem.concat(gpa, u8, &.{ imports_dir, "edits/", name });
    defer gpa.free(fixture);
    const source = try loadFixture(gpa, fixture);
    defer gpa.free(source);
    try tree.write(wire_path, source);
}
