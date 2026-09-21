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

    // The file landed in another directory, so it is re-read: where a unit
    // sits decides which other units it may resolve names to. Exactly one unit
    // is re-read — the one that moved, and not the one that did not.
    try testing.expectEqual(@as(usize, 1), outcome.analyzed);
    try testing.expectEqual(baseline + 1, tree.invocations());

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
    try testing.expectEqualStrings("twice", overloaded.claim.relationship.target.designator.name);
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
    // One package, one source root, two files each declaring a non-public class
    // of the same name: the ambiguity Java itself allows.
    _ = try index.addUnit("demo/TwinFirst.java", .java, "package demo;\nclass Twin {}\n");
    _ = try index.addUnit("demo/TwinSecond.java", .java, "package demo;\nclass Twin {}\n");
    _ = try index.addUnit("other/Elsewhere.java", .java, "package other;\nclass Elsewhere {}\n");
    _ = try index.addUnit("Loose.java", .java, "class Loose {}\n");

    const greeter = try index.addUnit("demo/Greeter.java", .java,
        \\package demo;
        \\
        \\import other.Imported;
        \\
        \\interface Shape {}
        \\
        \\enum Kind {}
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
        \\    Kind kind;
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
    // The move ADR 011 makes, pinned: `Shape` used to decline as a non-class
    // type this frontend does not cover, and is now a declaration the unit
    // holds, so the name resolves to it as a local fact. `Kind` is the half
    // that did not move — an enum still claims its name and still declines.
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .references,
        .source = class.id,
        .target = snapshot.findDefinition("demo/Greeter.java", "Shape").?.id,
        .resolution = .fact,
    }));
    try expectExplanation(try referenceFrom(&snapshot, class.id, "Kind"), "non-class type");
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
    try testing.expectEqualStrings("Helper", reference.relationship().?.target.designator.name);
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

// -- Plan 010: Java visibility boundaries ------------------------------------

/// Every way a reference can fail to resolve must stay distinguishable, so a
/// boundary-declined reference is checked for all of it: it is unresolved, it
/// keeps the name as written, it names its producer, it is current rather than
/// stale, and it is not reported as an absence or an unsupported construct.
fn expectHonestlyUnresolved(
    snapshot: *const semidx.Snapshot,
    source: model.EntityId,
    designator: []const u8,
) !model.Assertion {
    const found = try referenceFrom(snapshot, source, designator);
    try testing.expectEqualStrings(
        semidx.frontends.java.capabilities.producer.name,
        found.producer.name,
    );
    try testing.expectEqual(model.Freshness.current, snapshot.assertionFreshness(found));
    try testing.expectEqual(model.MissingPart.target_entity, found.resolution.unresolved.missing);
    for (snapshot.diagnostics) |diagnostic| {
        try testing.expect(diagnostic.kind != .confirmed_absence);
    }
    return found;
}

test "two source roots sharing a package do not become one visible package" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit(
        "moduleA/src/main/java/demo/Helper.java",
        .java,
        "package demo;\nclass Helper {}\n",
    );
    _ = try index.addUnit(
        "moduleB/src/main/java/demo/Consumer.java",
        .java,
        "package demo;\nclass Consumer { Helper helper; }\n",
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();
    const consumer = snapshot.findDefinition(
        "moduleB/src/main/java/demo/Consumer.java",
        "Consumer",
    ).?;

    // The name is carried as written, and nothing was resolved to the class the
    // other module happens to declare. The reason says the class exists and is
    // out of reach, which is not the same answer as a name nothing declares.
    try expectExplanation(
        try expectHonestlyUnresolved(&snapshot, consumer.id, "Helper"),
        "none of them in a Java source root this unit can see",
    );
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{
        .kind = .references,
        .source = consumer.id,
        .target = snapshot.findDefinition(
            "moduleA/src/main/java/demo/Helper.java",
            "Helper",
        ).?.id,
    }));
    // Nothing was read, so nothing is declared as a dependency.
    try testing.expectEqual(@as(usize, 0), index.graph.dependencies.count());
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
}

test "a test source root reads its module's main source root, and not the other way round" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    const main_unit = try index.addUnit(
        "module/src/main/java/demo/Helper.java",
        .java,
        "package demo;\nclass Helper { Fixture fixture; }\n",
    );
    const test_unit = try index.addUnit(
        "module/src/test/java/demo/Fixture.java",
        .java,
        "package demo;\nclass Fixture { Helper helper; }\n",
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();
    const helper = snapshot.findDefinition("module/src/main/java/demo/Helper.java", "Helper").?;
    const fixture = snapshot.findDefinition("module/src/test/java/demo/Fixture.java", "Fixture").?;

    // The permitted direction is a fact about the entity in the main root.
    const resolved = snapshot.firstRelationship(.{
        .kind = .references,
        .source = fixture.id,
        .target = helper.id,
    }).?;
    try testing.expectEqual(model.ResolutionCategory.fact, resolved.resolution.category());

    // The reverse is the same two units and the same package, and it is refused.
    _ = try expectHonestlyUnresolved(&snapshot, helper.id, "Fixture");

    // One dependency, in the direction that read something.
    try testing.expectEqual(@as(usize, 1), index.graph.dependencies.count());
    const declared = index.graph.dependencies.declarations.items[0];
    try testing.expectEqual(test_unit, declared.dependent);
    try testing.expectEqual(main_unit, declared.provider);
}

test "a path that does not spell its declared package resolves nothing and offers nothing" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    // Both units claim package `demo`; neither sits where that package says.
    _ = try index.addUnit("one/Helper.java", .java, "package demo;\nclass Helper {}\n");
    _ = try index.addUnit("two/Consumer.java", .java, "package demo;\nclass Consumer { Helper helper; }\n");
    // A unit that does sit where its package says still cannot see them.
    _ = try index.addUnit("demo/Laid.java", .java, "package demo;\nclass Laid { Helper helper; }\n");

    var snapshot = try index.publish();
    defer snapshot.deinit();

    // A unit with no source root has no scope, so it gets no table at all and
    // cannot even see that the name is declared elsewhere.
    try expectExplanation(
        try expectHonestlyUnresolved(
            &snapshot,
            snapshot.findDefinition("two/Consumer.java", "Consumer").?.id,
            "Helper",
        ),
        "no current top-level class of this name is declared in package `demo`",
    );
    // A unit that does have a source root is told the truth: the name is
    // declared in its package, out of reach.
    try expectExplanation(
        try expectHonestlyUnresolved(
            &snapshot,
            snapshot.findDefinition("demo/Laid.java", "Laid").?.id,
            "Helper",
        ),
        "none of them in a Java source root this unit can see",
    );
    try testing.expectEqual(@as(usize, 0), index.graph.dependencies.count());
}

test "ambiguity inside one shared scope stays unresolved and still says it is ambiguous" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit(
        "module/src/main/java/demo/First.java",
        .java,
        "package demo;\nclass Twin {}\n",
    );
    _ = try index.addUnit(
        "module/src/main/java/demo/Second.java",
        .java,
        "package demo;\nclass Twin {}\n",
    );
    _ = try index.addUnit(
        "module/src/main/java/demo/Consumer.java",
        .java,
        "package demo;\nclass Consumer { Twin twin; }\n",
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();
    const consumer = snapshot.findDefinition(
        "module/src/main/java/demo/Consumer.java",
        "Consumer",
    ).?;
    try expectExplanation(
        try expectHonestlyUnresolved(&snapshot, consumer.id, "Twin"),
        "ambiguous",
    );
}

test "a single-type import resolves to the one class the imported package declares" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    const provider = try index.addUnit(
        "src/main/java/lib/Helper.java",
        .java,
        "package lib;\npublic class Helper {}\n",
    );
    const consumer = try index.addUnit(
        "src/main/java/app/Consumer.java",
        .java,
        "package app;\n\nimport lib.Helper;\n\nclass Consumer { Helper helper; }\n",
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();
    const class = snapshot.findDefinition("src/main/java/app/Consumer.java", "Consumer").?;
    const target = snapshot.findDefinition("src/main/java/lib/Helper.java", "Helper").?;

    const reference = snapshot.firstRelationship(.{
        .kind = .references,
        .source = class.id,
        .target = target.id,
    }).?;
    try testing.expectEqual(model.ResolutionCategory.fact, reference.resolution.category());
    try testing.expectEqualStrings(
        semidx.frontends.java.capabilities.producer.name,
        reference.producer.name,
    );
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .designator = "Helper" }));

    // What it read is declared, so a later change to the provider reaches it.
    try testing.expectEqual(@as(usize, 1), index.graph.dependencies.count());
    const declared = index.graph.dependencies.declarations.items[0];
    try testing.expectEqual(consumer, declared.dependent);
    try testing.expectEqual(provider, declared.provider);
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
}

test "on-demand, static, and unindexed imports stay unresolved" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit("src/main/java/lib/Helper.java", .java, "package lib;\nclass Helper {}\n");
    _ = try index.addUnit("src/main/java/lib/Constants.java", .java, "package lib;\nclass Constants {}\n");

    // An on-demand import names a scope, not a type.
    _ = try index.addUnit(
        "src/main/java/app/Wild.java",
        .java,
        "package app;\n\nimport lib.*;\n\nclass Wild { Helper helper; }\n",
    );
    // A static import names a member.
    _ = try index.addUnit(
        "src/main/java/app/Static.java",
        .java,
        "package app;\n\nimport static lib.Constants.Helper;\n\nclass Static { Helper helper; }\n",
    );
    // An import of a type no indexed unit declares.
    _ = try index.addUnit(
        "src/main/java/app/Absent.java",
        .java,
        "package app;\n\nimport java.util.List;\n\nclass Absent { List list; }\n",
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    try expectExplanation(
        try expectHonestlyUnresolved(
            &snapshot,
            snapshot.findDefinition("src/main/java/app/Wild.java", "Wild").?.id,
            "Helper",
        ),
        "no current top-level class of this name is declared in package `app`",
    );
    try expectExplanation(
        try expectHonestlyUnresolved(
            &snapshot,
            snapshot.findDefinition("src/main/java/app/Static.java", "Static").?.id,
            "Helper",
        ),
        "a static import names this type",
    );
    try expectExplanation(
        try expectHonestlyUnresolved(
            &snapshot,
            snapshot.findDefinition("src/main/java/app/Absent.java", "Absent").?.id,
            "List",
        ),
        "no indexed source unit declares it in the package the import names",
    );
}

test "a single-type import does not cross a visibility boundary" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit(
        "moduleA/src/main/java/lib/Helper.java",
        .java,
        "package lib;\nclass Helper {}\n",
    );
    _ = try index.addUnit(
        "moduleB/src/main/java/app/Consumer.java",
        .java,
        "package app;\n\nimport lib.Helper;\n\nclass Consumer { Helper helper; }\n",
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();
    try expectExplanation(
        try expectHonestlyUnresolved(
            &snapshot,
            snapshot.findDefinition("moduleB/src/main/java/app/Consumer.java", "Consumer").?.id,
            "Helper",
        ),
        "none in a Java source root this unit can see",
    );
    try testing.expectEqual(@as(usize, 0), index.graph.dependencies.count());
}

test "a class appearing in an imported package reaches the unit that imported it" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write(
        "src/main/java/app/Consumer.java",
        "package app;\n\nimport lib.Helper;\n\nclass Consumer { Helper helper; }\n",
    );
    _ = try tree.rescan();

    {
        var before = try tree.index.publish();
        defer before.deinit();
        const class = before.findDefinition("src/main/java/app/Consumer.java", "Consumer").?;
        // Nothing declares it yet, so the import resolves to nothing.
        _ = try referenceFrom(&before, class.id, "Helper");
    }

    // The imported class appears. The importer declared no dependency, because
    // it had nothing to depend on, so only the import hint can reach it.
    try tree.write("src/main/java/lib/Helper.java", "package lib;\nclass Helper {}\n");
    _ = try tree.rescan();

    var after = try tree.index.publish();
    defer after.deinit();
    const class = after.findDefinition("src/main/java/app/Consumer.java", "Consumer").?;
    try testing.expectEqual(@as(usize, 1), after.countRelationships(.{
        .kind = .references,
        .source = class.id,
        .target = after.findDefinition("src/main/java/lib/Helper.java", "Helper").?.id,
        .resolution = .fact,
    }));
}

// -- Plan 012: Java static calls ---------------------------------------------

// The matrix below is written against
// [ADR 009](../docs/adr/009_java_static_calls.md), which Plan 012 Stage 5
// implements. Stage 2 wrote it as a specification behind a switch, Stage 4
// answered its receiver half, and Stage 5 removed the switch: every case now
// asserts the answer the frontend must give, and nothing here is pending.

const StaticTarget = struct {
    path: []const u8,
    class: []const u8,
    method: []const u8,
};

/// One invocation the matrix speaks about, named by where it is written rather
/// than by a line number, so inserting a case does not renumber the others.
const StaticCall = struct {
    /// The unit, class, and method the invocation is written in.
    path: []const u8,
    class: []const u8,
    method: []const u8,
    /// The invocation exactly as written. It is the evidence text either way,
    /// and since [ADR 010](../docs/adr/010_designator_is_a_structured_name.md)
    /// it is no longer the designator: a designator is the name the invocation
    /// names, with the class in front of it where this frontend established
    /// one.
    call: []const u8,
    /// What the frontend must have recorded as the designator. Absent where the
    /// case speaks about resolution rather than about the name it recorded.
    designator: ?model.Designator = null,
    expect: union(enum) {
        /// ADR 009 requires this call to name this method.
        fact: StaticTarget,
        /// ADR 009 requires this call to stay unresolved, saying this.
        unresolved: []const u8,
    },
};

fn staticCallFrom(
    snapshot: *const semidx.Snapshot,
    caller: model.Entity,
    text: []const u8,
) !model.Assertion {
    var calls = snapshot.relationships(.{ .kind = .calls, .source = caller.id });
    while (calls.next()) |call| {
        if (std.mem.eql(u8, call.evidence.?.text, text)) return call;
    }
    std.debug.print("no call `{s}` from `{s}`\n", .{ text, caller.identity.name.? });
    return error.TestExpectedCall;
}

fn expectStaticCall(snapshot: *const semidx.Snapshot, case: StaticCall) !void {
    const caller = definitionIn(snapshot, case.path, case.class, case.method) orelse {
        std.debug.print("no method `{s}.{s}` in `{s}`\n", .{ case.class, case.method, case.path });
        return error.TestExpectedDefinition;
    };
    const call = try staticCallFrom(snapshot, caller, case.call);
    switch (case.expect) {
        .fact => |target| {
            const wanted = definitionIn(snapshot, target.path, target.class, target.method) orelse {
                std.debug.print("no target `{s}.{s}`\n", .{ target.class, target.method });
                return error.TestExpectedDefinition;
            };
            try testing.expectEqual(model.ResolutionCategory.fact, call.resolution.category());
            try testing.expectEqual(wanted.id, call.claim.relationship.target.entity);
        },
        .unresolved => |fragment| {
            // Whatever the reason, the answer is never a fact and never loses
            // the text that was read.
            try testing.expect(!call.resolution.isFact());
            if (case.designator) |expected| {
                try testing.expect(expected.eql(call.claim.relationship.target.designator));
            }
            try expectExplanation(call, fragment);
        },
    }
}

/// The classes every static-call fixture resolves against, and the reason a
/// wrongly read receiver is detectable: `Util.make` is static and `Other.make`
/// is not, so a frontend that reads a variable as a class names the wrong
/// method rather than the same one by another route.
fn addStaticCallProviders(index: *semidx.Index) !void {
    _ = try index.addUnit(
        "module/src/main/java/lib/Util.java",
        .java,
        \\package lib;
        \\
        \\class Util {
        \\    public static String make() { return null; }
        \\    public static String twice() { return null; }
        \\    public static String twice(String name) { return null; }
        \\    static String packaged() { return null; }
        \\    protected static String guarded() { return null; }
        \\    private static String hidden() { return null; }
        \\    public String instance() { return null; }
        \\}
        \\
        ,
    );
    _ = try index.addUnit(
        "module/src/main/java/lib/Other.java",
        .java,
        \\package lib;
        \\
        \\class Other {
        \\    public String make() { return null; }
        \\}
        \\
        ,
    );
    _ = try index.addUnit(
        "module/src/main/java/lib/Shaped.java",
        .java,
        \\package lib;
        \\
        \\class Shaped extends Absent {
        \\    public static String make() { return null; }
        \\}
        \\
        ,
    );
}

test "the static-call matrix pins what each covered and declined case must answer" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();
    try addStaticCallProviders(&index);

    // A caller in the same package and source root as the provider.
    _ = try index.addUnit(
        "module/src/main/java/lib/Caller.java",
        .java,
        \\package lib;
        \\
        \\class Caller {
        \\    void covered() { Util.make(); }
        \\    void overloaded() { Util.twice(); }
        \\    void notStatic() { Util.instance(); }
        \\    void privateElsewhere() { Util.hidden(); }
        \\    void protectedElsewhere() { Util.guarded(); }
        \\    void packagedElsewhere() { Util.packaged(); }
        \\    void missingMethod() { Util.absent(); }
        \\    void targetHasSupertypes() { Shaped.make(); }
        \\    void noSuchClass() { Absent.make(); }
        \\    void nested() { Runnable task = new Runnable() { public void run() { Util.make(); } }; }
        \\}
        \\
        ,
    );
    // Two top-level classes in one unit: the enclosing class reaches its own
    // private members, and no other class's.
    _ = try index.addUnit(
        "module/src/main/java/lib/Local.java",
        .java,
        \\package lib;
        \\
        \\class Local {
        \\    private static String own() { return null; }
        \\    void covered() { Local.own(); }
        \\    void sameUnit() { Companion.make(); }
        \\    void privateInAnotherClass() { Companion.secret(); }
        \\}
        \\
        \\class Companion {
        \\    public static String make() { return null; }
        \\    private static String secret() { return null; }
        \\}
        \\
        ,
    );
    // The standard-layout test root reads its module's main root.
    _ = try index.addUnit(
        "module/src/test/java/lib/CallerTest.java",
        .java,
        \\package lib;
        \\
        \\class CallerTest {
        \\    void covered() { Util.make(); }
        \\}
        \\
        ,
    );
    // Another package in the same root, reaching the class by single-type import.
    _ = try index.addUnit(
        "module/src/main/java/app/Importer.java",
        .java,
        \\package app;
        \\
        \\import lib.Util;
        \\
        \\class Importer {
        \\    void covered() { Util.make(); }
        \\}
        \\
        ,
    );
    // The same package name in another source root is another scope.
    _ = try index.addUnit(
        "other/src/main/java/lib/Outsider.java",
        .java,
        \\package lib;
        \\
        \\class Outsider {
        \\    void declined() { Util.make(); }
        \\}
        \\
        ,
    );
    // An enclosing class with supertypes may inherit a field of the receiver's
    // name, and the working copy cannot see that it does not.
    _ = try index.addUnit(
        "module/src/main/java/lib/Derived.java",
        .java,
        \\package lib;
        \\
        \\class Derived extends Absent {
        \\    void declined() { Util.make(); }
        \\}
        \\
        ,
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    const util: StaticTarget = .{
        .path = "module/src/main/java/lib/Util.java",
        .class = "Util",
        .method = "make",
    };
    const cases = [_]StaticCall{
        // Covered: one declared static method, reached inside the boundary.
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "covered",
            .call = "Util.make()",
            .expect = .{ .fact = util },
        },
        .{
            .path = "module/src/test/java/lib/CallerTest.java",
            .class = "CallerTest",
            .method = "covered",
            .call = "Util.make()",
            .expect = .{ .fact = util },
        },
        .{
            .path = "module/src/main/java/app/Importer.java",
            .class = "Importer",
            .method = "covered",
            .call = "Util.make()",
            .expect = .{ .fact = util },
        },
        .{
            .path = "module/src/main/java/lib/Local.java",
            .class = "Local",
            .method = "covered",
            .call = "Local.own()",
            .expect = .{ .fact = .{
                .path = "module/src/main/java/lib/Local.java",
                .class = "Local",
                .method = "own",
            } },
        },
        .{
            .path = "module/src/main/java/lib/Local.java",
            .class = "Local",
            .method = "sameUnit",
            .call = "Companion.make()",
            .expect = .{ .fact = .{
                .path = "module/src/main/java/lib/Local.java",
                .class = "Companion",
                .method = "make",
            } },
        },
        // Declined, each for its own reason.
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "overloaded",
            .call = "Util.twice()",
            // The receiver was established as a class and only the method
            // choice failed, so the class is the qualifier.
            .designator = .{ .name = "twice", .qualifier = "Util" },
            .expect = .{ .unresolved = "overloads are not resolved" },
        },
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "notStatic",
            .call = "Util.instance()",
            .designator = .{ .name = "instance", .qualifier = "Util" },
            .expect = .{ .unresolved = "is not static" },
        },
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "privateElsewhere",
            .call = "Util.hidden()",
            .expect = .{ .unresolved = "access" },
        },
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "protectedElsewhere",
            .call = "Util.guarded()",
            .expect = .{ .unresolved = "access" },
        },
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "packagedElsewhere",
            .call = "Util.packaged()",
            .expect = .{ .unresolved = "access" },
        },
        .{
            .path = "module/src/main/java/lib/Local.java",
            .class = "Local",
            .method = "privateInAnotherClass",
            .call = "Companion.secret()",
            .expect = .{ .unresolved = "access" },
        },
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "missingMethod",
            .call = "Util.absent()",
            .expect = .{ .unresolved = "no method of this name" },
        },
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "targetHasSupertypes",
            .call = "Shaped.make()",
            .expect = .{ .unresolved = "supertypes" },
        },
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "noSuchClass",
            .call = "Absent.make()",
            .expect = .{ .unresolved = "no current top-level class" },
        },
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "nested",
            .call = "Util.make()",
            .expect = .{ .unresolved = "class body declared in the method" },
        },
        .{
            .path = "other/src/main/java/lib/Outsider.java",
            .class = "Outsider",
            .method = "declined",
            .call = "Util.make()",
            .expect = .{ .unresolved = "source root this unit can see" },
        },
        .{
            .path = "module/src/main/java/lib/Derived.java",
            .class = "Derived",
            .method = "declined",
            .call = "Util.make()",
            .expect = .{ .unresolved = "supertypes" },
        },
    };
    for (cases) |case| try expectStaticCall(&snapshot, case);

    // Whatever else moves, no Java answer is ever a confidence.
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
}

test "a receiver name any binding introducer declares is not read as a class" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();
    try addStaticCallProviders(&index);

    // Each method isolates one binding introducer, and every receiver is a
    // value of a type whose `make` is not the static one: a frontend that read
    // the name as a class would name the wrong method, not the same one.
    //
    // `bySpread` is the one snippet that is parsed rather than compilable —
    // varargs bind an array, and no valid call through one reaches this rule —
    // but what it pins is the binding, which is the same rule.
    _ = try index.addUnit(
        "module/src/main/java/lib/Shadowed.java",
        .java,
        \\package lib;
        \\
        \\import java.util.List;
        \\import java.util.function.BiConsumer;
        \\import java.util.function.Consumer;
        \\
        \\class Shadowed {
        \\    void byParameter(Other Util) { Util.make(); }
        \\    void bySpread(Other... Util) { Util.make(); }
        \\    void byLocal() { Other Util = null; Util.make(); }
        \\    void beforeLocal() { Util.make(); Other Util = null; }
        \\    void byForEach(List<Other> items) { for (Other Util : items) { Util.make(); } }
        \\    void byCatch() { try { } catch (Failure Util) { Util.make(); } }
        \\    void byResource() { try (Handle Util = null) { Util.make(); } catch (Exception error) { } }
        \\    void byLambda() { Consumer<Other> sink = Util -> Util.make(); }
        \\    void byInferredLambda() { BiConsumer<Other, Other> sink = (Util, rest) -> Util.make(); }
        \\    void byTypedLambda() { Consumer<Other> sink = (Other Util) -> Util.make(); }
        \\    void byPattern(Object value) { if (value instanceof Other Util) { Util.make(); } }
        \\    void byRecordPattern(Object value) { if (value instanceof Pair(Other Util, Other rest)) { Util.make(); } }
        \\}
        \\
        \\class Failure extends RuntimeException {
        \\    public String make() { return null; }
        \\}
        \\
        \\class Handle implements AutoCloseable {
        \\    public void close() {}
        \\    public String make() { return null; }
        \\}
        \\
        \\record Pair(Other first, Other second) {}
        \\
        ,
    );
    // A field of the class binds the name for every method that declares
    // nothing of its own.
    _ = try index.addUnit(
        "module/src/main/java/lib/Fielded.java",
        .java,
        \\package lib;
        \\
        \\class Fielded {
        \\    Other Util;
        \\
        \\    void byField() { Util.make(); }
        \\}
        \\
        ,
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    const shadowed = "module/src/main/java/lib/Shadowed.java";
    const bound = "declared here as a binding";
    const cases = [_]StaticCall{
        .{ .path = shadowed, .class = "Shadowed", .method = "byParameter", .call = "Util.make()", .expect = .{ .unresolved = bound } },
        .{ .path = shadowed, .class = "Shadowed", .method = "bySpread", .call = "Util.make()", .expect = .{ .unresolved = bound } },
        .{ .path = shadowed, .class = "Shadowed", .method = "byLocal", .call = "Util.make()", .expect = .{ .unresolved = bound } },
        .{ .path = shadowed, .class = "Shadowed", .method = "byForEach", .call = "Util.make()", .expect = .{ .unresolved = bound } },
        .{ .path = shadowed, .class = "Shadowed", .method = "byCatch", .call = "Util.make()", .expect = .{ .unresolved = bound } },
        .{ .path = shadowed, .class = "Shadowed", .method = "byResource", .call = "Util.make()", .expect = .{ .unresolved = bound } },
        .{ .path = shadowed, .class = "Shadowed", .method = "byLambda", .call = "Util.make()", .expect = .{ .unresolved = bound } },
        .{ .path = shadowed, .class = "Shadowed", .method = "byInferredLambda", .call = "Util.make()", .expect = .{ .unresolved = bound } },
        .{ .path = shadowed, .class = "Shadowed", .method = "byTypedLambda", .call = "Util.make()", .expect = .{ .unresolved = bound } },
        .{ .path = shadowed, .class = "Shadowed", .method = "byPattern", .call = "Util.make()", .expect = .{ .unresolved = bound } },
        .{ .path = shadowed, .class = "Shadowed", .method = "byRecordPattern", .call = "Util.make()", .expect = .{ .unresolved = bound } },
        .{
            .path = "module/src/main/java/lib/Fielded.java",
            .class = "Fielded",
            .method = "byField",
            .call = "Util.make()",
            .expect = .{ .unresolved = bound },
        },
        // The scope of a local declaration is the rest of the block, so the
        // name before it is still the class. This is the one case in the
        // matrix that distinguishes a lexical rule from poisoning the method.
        .{
            .path = shadowed,
            .class = "Shadowed",
            .method = "beforeLocal",
            .call = "Util.make()",
            .expect = .{ .fact = .{
                .path = "module/src/main/java/lib/Util.java",
                .class = "Util",
                .method = "make",
            } },
        },
    };
    for (cases) |case| try expectStaticCall(&snapshot, case);
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
}

test "provider method and class-shape edits decide what a static call may claim" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    const provider = try index.addUnit(
        "module/src/main/java/lib/Util.java",
        .java,
        "package lib;\n\nclass Util {\n    public static String make() { return null; }\n}\n",
    );
    _ = try index.addUnit(
        "module/src/main/java/lib/Caller.java",
        .java,
        "package lib;\n\nclass Caller {\n    void run() { Util.make(); }\n}\n",
    );

    const caller_path = "module/src/main/java/lib/Caller.java";
    const target: StaticTarget = .{
        .path = "module/src/main/java/lib/Util.java",
        .class = "Util",
        .method = "make",
    };

    // Each edit replaces the provider and decides the same call again. The
    // shape of the provider is the whole input: the caller is never touched.
    const Step = struct {
        what: []const u8,
        source: []const u8,
        expect: @FieldType(StaticCall, "expect"),
    };
    const steps = [_]Step{
        .{
            .what = "the method is there to begin with",
            .source = "package lib;\n\nclass Util {\n    public static String make() { return null; }\n}\n",
            .expect = .{ .fact = target },
        },
        .{
            .what = "the method is removed",
            .source = "package lib;\n\nclass Util {\n}\n",
            .expect = .{ .unresolved = "no method of this name" },
        },
        .{
            .what = "the method comes back",
            .source = "package lib;\n\nclass Util {\n    public static String make() { return null; }\n}\n",
            .expect = .{ .fact = target },
        },
        .{
            .what = "the method is overloaded",
            .source = "package lib;\n\nclass Util {\n    public static String make() { return null; }\n" ++
                "    public static String make(String name) { return null; }\n}\n",
            .expect = .{ .unresolved = "overloads are not resolved" },
        },
        .{
            .what = "the method stops being static",
            .source = "package lib;\n\nclass Util {\n    public String make() { return null; }\n}\n",
            .expect = .{ .unresolved = "is not static" },
        },
        .{
            .what = "the method leaves the covered access",
            .source = "package lib;\n\nclass Util {\n    static String make() { return null; }\n}\n",
            .expect = .{ .unresolved = "access" },
        },
        .{
            .what = "the class declares a supertype",
            .source = "package lib;\n\nclass Util extends Absent {\n    public static String make() { return null; }\n}\n",
            .expect = .{ .unresolved = "supertypes" },
        },
        .{
            .what = "the supertype is removed again",
            .source = "package lib;\n\nclass Util {\n    public static String make() { return null; }\n}\n",
            .expect = .{ .fact = target },
        },
    };

    for (steps) |step| {
        _ = try index.applyEdit(provider, step.source);
        var snapshot = try index.publish();
        defer snapshot.deinit();
        expectStaticCall(&snapshot, .{
            .path = caller_path,
            .class = "Caller",
            .method = "run",
            .call = "Util.make()",
            .expect = step.expect,
        }) catch |failure| {
            std.debug.print("after {s}\n", .{step.what});
            return failure;
        };
    }

    // The receiver class leaves the caller's scope entirely.
    try index.renameUnit(provider, "other/src/main/java/lib/Util.java");
    var moved = try index.publish();
    defer moved.deinit();
    try expectStaticCall(&moved, .{
        .path = caller_path,
        .class = "Caller",
        .method = "run",
        .call = "Util.make()",
        .expect = .{ .unresolved = "source root this unit can see" },
    });
    try testing.expectEqual(@as(usize, 0), moved.countApproximateAssertions());
}

test "a receiver that is a value stays unresolved, whatever the static rule admits" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();
    try addStaticCallProviders(&index);

    // Every receiver here is a value, and none of them is what ADR 009 admits.
    // The static rule is allowed to make class names resolve; it is not allowed
    // to make these resolve on the way past.
    _ = try index.addUnit(
        "module/src/main/java/lib/Values.java",
        .java,
        \\package lib;
        \\
        \\class Values extends Absent {
        \\    Other field;
        \\
        \\    Other self() { return null; }
        \\    void byLocal() { Other value = null; value.make(); }
        \\    void byField() { field.make(); }
        \\    void byParameter(Other value) { value.make(); }
        \\    void byCreation() { new Other().make(); }
        \\    void byChain() { self().make(); }
        \\    void byLiteral() { "text".length(); }
        \\    void byClassLiteral() { Other.class.getName(); }
        \\    void byThis() { this.self(); }
        \\    void bySuper() { super.toString(); }
        \\}
        \\
        ,
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    const values = "module/src/main/java/lib/Values.java";
    const cases = [_]StaticCall{
        // A receiver read as a value names no scope, so the name stands alone.
        .{ .path = values, .class = "Values", .method = "byLocal", .call = "value.make()", .designator = .{ .name = "make" }, .expect = .{ .unresolved = "receiver" } },
        .{ .path = values, .class = "Values", .method = "byField", .call = "field.make()", .expect = .{ .unresolved = "receiver" } },
        .{ .path = values, .class = "Values", .method = "byParameter", .call = "value.make()", .expect = .{ .unresolved = "receiver" } },
        .{ .path = values, .class = "Values", .method = "byCreation", .call = "new Other().make()", .designator = .{ .name = "make" }, .expect = .{ .unresolved = "receiver" } },
        .{ .path = values, .class = "Values", .method = "byChain", .call = "self().make()", .expect = .{ .unresolved = "receiver" } },
        .{ .path = values, .class = "Values", .method = "byLiteral", .call = "\"text\".length()", .expect = .{ .unresolved = "receiver" } },
        .{ .path = values, .class = "Values", .method = "byClassLiteral", .call = "Other.class.getName()", .expect = .{ .unresolved = "receiver" } },
        .{ .path = values, .class = "Values", .method = "byThis", .call = "this.self()", .expect = .{ .unresolved = "receiver" } },
        .{ .path = values, .class = "Values", .method = "bySuper", .call = "super.toString()", .expect = .{ .unresolved = "receiver" } },
    };
    for (cases) |case| try expectStaticCall(&snapshot, case);
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
}

/// A provider, a reader of one of its methods, another class in the same
/// package, and a unit importing from it. Only the reader is ever hinted, so
/// what a change costs is visible as a count.
const MemberTree = struct {
    index: semidx.Index,
    provider: model.SourceUnitId,
    reader: model.SourceUnitId,
    /// A unit in the same package that reads nothing of the provider.
    sibling: model.SourceUnitId,

    fn init() !MemberTree {
        var index = try semidx.Index.init(testing.allocator, "tree");
        errdefer index.deinit();

        const provider = try index.addUnit(
            "src/main/java/demo/Util.java",
            .java,
            "package demo;\n\nclass Util {\n    public static String make() { return null; }\n" ++
                "    public static String keep() { return null; }\n}\n",
        );
        const reader = try index.addUnit(
            "src/main/java/demo/Reader.java",
            .java,
            "package demo;\n\nclass Reader {\n    void run() { Util.make(); }\n}\n",
        );
        // A second declarer in the package, and a unit that imports from it.
        // Both are reanalyzed when the package's exports change, and neither
        // has any business being reanalyzed when one method's shape does. The
        // importer names the class without referring to it, so it is reachable
        // only through the import hint: a dependency of its own would make this
        // a test of the dependency channel instead.
        const sibling = try index.addUnit(
            "src/main/java/demo/Sibling.java",
            .java,
            "package demo;\n\nclass Sibling {\n    void run() {}\n}\n",
        );
        _ = try index.addUnit(
            "src/main/java/app/Importer.java",
            .java,
            "package app;\n\nimport demo.Util;\n\nclass Importer {\n    void run() {}\n}\n",
        );
        return .{ .index = index, .provider = provider, .reader = reader, .sibling = sibling };
    }

    fn deinit(self: *MemberTree) void {
        self.index.deinit();
        self.* = undefined;
    }

    fn hint(self: *MemberTree, unit: model.SourceUnitId, class: []const u8, method: []const u8) !void {
        try self.index.analyzer.java_members.noteReader(unit, class, method);
    }

    /// Replaces the provider and reports what keeping the graph current cost.
    fn editProvider(self: *MemberTree, source: []const u8) !usize {
        semidx.work.reset();
        _ = try self.index.applyEdit(self.provider, source);
        return semidx.work.upkeep_reanalyses;
    }
};

test "a reader is reanalyzed when the method it asked about changes" {
    var tree = try MemberTree.init();
    defer tree.deinit();

    // Nothing is seeded here. The reader hinted itself when it read
    // `Util.make()`, which is what Stage 5 added to the channel Stage 3 built.

    // A body edit changes nothing a caller can see — but this call resolves, so
    // the reader declares a dependency on the provider *unit*, and a dependency
    // is per unit rather than per method. It is re-read for a change it cannot
    // observe, which is the price of a cross-unit fact.
    try testing.expectEqual(@as(usize, 1), tree.index.graph.dependencies.count());
    try testing.expectEqual(@as(usize, 1), try tree.editProvider(
        "package demo;\n\nclass Util {\n    public static String make() { return \"x\"; }\n" ++
            "    public static String keep() { return null; }\n}\n",
    ));

    // Losing `public` is a different answer for that one name.
    try testing.expectEqual(@as(usize, 1), try tree.editProvider(
        "package demo;\n\nclass Util {\n    static String make() { return null; }\n" ++
            "    public static String keep() { return null; }\n}\n",
    ));

    // The answer it got reads nothing, so from here on there is no dependency
    // in the graph at all: every re-read below is the hint's doing.
    try testing.expectEqual(@as(usize, 0), tree.index.graph.dependencies.count());

    // Losing `static`, gaining an overload, and disappearing entirely.
    try testing.expectEqual(@as(usize, 1), try tree.editProvider(
        "package demo;\n\nclass Util {\n    String make() { return null; }\n" ++
            "    public static String keep() { return null; }\n}\n",
    ));
    try testing.expectEqual(@as(usize, 1), try tree.editProvider(
        "package demo;\n\nclass Util {\n    String make() { return null; }\n" ++
            "    String make(String name) { return null; }\n    public static String keep() { return null; }\n}\n",
    ));
    try testing.expectEqual(@as(usize, 1), try tree.editProvider(
        "package demo;\n\nclass Util {\n    public static String keep() { return null; }\n}\n",
    ));
    try testing.expectEqual(@as(usize, 0), tree.index.graph.dependencies.count());

    // And a method appearing where the reader found none: the case no
    // dependency can carry, because an unresolved call read nothing.
    try testing.expectEqual(@as(usize, 1), try tree.editProvider(
        "package demo;\n\nclass Util {\n    public static String make() { return null; }\n" ++
            "    public static String keep() { return null; }\n}\n",
    ));

    // Measured, not assumed: that last re-read had nothing to propagate along,
    // and it is what turned the call back into a fact — which declares the
    // dependency again.
    try testing.expectEqual(@as(u32, 0), semidx.work.propagation_rounds);
    try testing.expect(!semidx.work.propagation_exhausted);
    try testing.expectEqual(@as(usize, 1), tree.index.graph.dependencies.count());
}

test "editing one method does not reanalyze the package's declarers and importers" {
    var tree = try MemberTree.init();
    defer tree.deinit();
    try tree.hint(tree.reader, "Util", "make");

    // Four Java units share this package's scope, and one method changed. If
    // the class shape travelled on the package export channel, the sibling
    // declarer and the importer would both be re-read for a change neither can
    // see; the count is how that stays a claim rather than a hope.
    try testing.expectEqual(@as(usize, 1), try tree.editProvider(
        "package demo;\n\nclass Util {\n    protected static String make() { return null; }\n" ++
            "    public static String keep() { return null; }\n}\n",
    ));

    // The package channel still does its own job: a class appearing in the
    // package is what the declarers and the importer are owed.
    semidx.work.reset();
    _ = try tree.index.addUnit(
        "src/main/java/demo/Extra.java",
        .java,
        "package demo;\n\nclass Extra {}\n",
    );
    try testing.expect(semidx.work.upkeep_reanalyses > 1);
}

test "a class-shape change reaches every reader of that class, not only of one method" {
    var tree = try MemberTree.init();
    defer tree.deinit();

    // Two readers, each hinted on a different method of the same class.
    const second = try tree.index.addUnit(
        "src/main/java/demo/Second.java",
        .java,
        "package demo;\n\nclass Second {\n    void run() { Util.keep(); }\n}\n",
    );
    try tree.hint(tree.reader, "Util", "make");
    try tree.hint(second, "Util", "keep");

    // A declared supertype can hide a static method of any name, so every
    // reader of the class is owed a re-read, not only the ones whose own
    // method aspect moved.
    try testing.expectEqual(@as(usize, 2), try tree.editProvider(
        "package demo;\n\nclass Util extends Absent {\n    public static String make() { return null; }\n" ++
            "    public static String keep() { return null; }\n}\n",
    ));

    // And removing it again makes both eligible once more.
    try testing.expectEqual(@as(usize, 2), try tree.editProvider(
        "package demo;\n\nclass Util {\n    public static String make() { return null; }\n" ++
            "    public static String keep() { return null; }\n}\n",
    ));
}

test "a unit that reads nothing is not reached, and a stale hint costs a pass and no claim" {
    var tree = try MemberTree.init();
    defer tree.deinit();

    // The sibling declares a class in the same package and reads nothing of the
    // provider, so it is hinted on a pair it never asks about: a hint that has
    // gone stale, which the channel is allowed to hold and must survive.
    try tree.hint(tree.sibling, "Util", "make");

    var before = try tree.index.publish();
    const before_calls = before.countRelationships(.{ .kind = .calls, .resolution = .fact });
    before.deinit();

    // Two units are re-read for one method's access change: the reader that
    // asked about the pair, and the stale hint. The importer, which the package
    // channel would have reached, is not among them.
    try testing.expectEqual(@as(usize, 2), try tree.editProvider(
        "package demo;\n\nclass Util {\n    protected static String make() { return null; }\n" ++
            "    public static String keep() { return null; }\n}\n",
    ));

    var after = try tree.index.publish();
    defer after.deinit();
    const run = definitionIn(&after, "src/main/java/demo/Reader.java", "Reader", "run").?;
    // The reader's answer changed, because `protected` is outside the covered
    // access; the stale hint's unit says exactly what it said before, so the
    // only fact lost is the caller's.
    try testing.expectEqual(before_calls - 1, after.countRelationships(.{ .kind = .calls, .resolution = .fact }));
    try testing.expectEqual(@as(usize, 0), after.countRelationships(.{
        .kind = .calls,
        .source = run.id,
        .resolution = .fact,
    }));
    try expectExplanation(try staticCallFrom(&after, run, "Util.make()"), "access");
    try testing.expectEqual(@as(usize, 0), after.countApproximateAssertions());
}

test "deciding a static call costs the invoked name's candidates, not the repository" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit(
        "src/main/java/demo/Util.java",
        .java,
        "package demo;\n\nclass Util {\n    public static String make() { return null; }\n" ++
            "    public static String keep() { return null; }\n}\n",
    );
    const caller = try index.addUnit(
        "src/main/java/demo/Caller.java",
        .java,
        "package demo;\n\nclass Caller {\n    void run() { Util.make(); }\n}\n",
    );

    const Measure = struct {
        fn candidates(ix: *semidx.Index, unit: model.SourceUnitId, source: []const u8) !usize {
            semidx.frontends.java.work.reset();
            _ = try ix.applyEdit(unit, source);
            return semidx.frontends.java.work.method_candidates;
        }
    };

    const alone = try Measure.candidates(
        &index,
        caller,
        "package demo;\n\nclass Caller {\n    void run() { Util.make(); } // once\n}\n",
    );
    // One invocation, one candidate: the methods named `make` in the class the
    // receiver names. Not the class's other methods, and not the package's.
    try testing.expectEqual(@as(usize, 1), alone);

    // Twenty more classes in the same package and the same source root, each
    // declaring a method of the same name — every one of them a candidate a
    // repository-wide lookup would have to touch and reject.
    var extra: usize = 0;
    while (extra < 20) : (extra += 1) {
        const path = try std.fmt.allocPrint(
            testing.allocator,
            "src/main/java/demo/Filler{d}.java",
            .{extra},
        );
        defer testing.allocator.free(path);
        const source = try std.fmt.allocPrint(
            testing.allocator,
            "package demo;\n\nclass Filler{d} {{\n    public static String make() {{ return null; }}\n" ++
                "    public static String keep() {{ return null; }}\n}}\n",
            .{extra},
        );
        defer testing.allocator.free(source);
        _ = try index.addUnit(path, .java, source);
    }

    const crowded = try Measure.candidates(
        &index,
        caller,
        "package demo;\n\nclass Caller {\n    void run() { Util.make(); } // twice\n}\n",
    );
    try testing.expectEqual(alone, crowded);

    // And the answer did not change either: the crowd is invisible to it.
    var snapshot = try index.publish();
    defer snapshot.deinit();
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .calls,
        .source = definitionIn(&snapshot, "src/main/java/demo/Caller.java", "Caller", "run").?.id,
        .target = definitionIn(&snapshot, "src/main/java/demo/Util.java", "Util", "make").?.id,
        .resolution = .fact,
    }));
}

test "the write path and the java frontend report the work they do" {
    semidx.work.reset();
    semidx.frontends.java.work.reset();

    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    const provider = try index.addUnit(
        "demo/Helper.java",
        .java,
        "package demo;\n\nclass Helper {\n    public static String make() { return null; }\n}\n",
    );
    _ = try index.addUnit(
        "demo/Caller.java",
        .java,
        "package demo;\n\nclass Caller {\n    Helper helper;\n    void run() { Helper.make(); local(); }\n" ++
            "    void local() {}\n}\n",
    );

    // Deciding an invocation examines the candidates the frontend has, and
    // today they are the analyzed unit's own methods. The bound is the claim;
    // the exact number is Stage 3 and Stage 5's to tighten.
    const candidates = semidx.frontends.java.work.method_candidates;
    try testing.expect(candidates > 0);
    try testing.expect(candidates <= 4);

    // The field type is read across units, so the caller says what it read.
    try testing.expectEqual(@as(usize, 1), index.graph.dependencies.count());

    // Editing the provider reaches the caller through that declaration, one
    // round along the chain, and nothing runs out of budget.
    semidx.work.reset();
    _ = try index.applyEdit(
        provider,
        "package demo;\n\nclass Helper {\n    public static String make() { return null; }\n    void extra() {}\n}\n",
    );
    try testing.expectEqual(@as(usize, 1), semidx.work.upkeep_reanalyses);
    try testing.expectEqual(@as(u32, 2), semidx.work.propagation_rounds);
    try testing.expect(!semidx.work.propagation_exhausted);
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
    for ([_][]const u8{ "print", "greet", "report" }) |designator| {
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

/// `designator` is what the frontend must have recorded: the name the callee
/// names, and the scope in front of it where the frontend established one. The
/// query is anchored on the name, because that is what the index is keyed on,
/// and the qualifier is then checked against what the claim carries.
fn expectUnresolvedCall(snapshot: *const semidx.Snapshot, from: model.Entity, designator: model.Designator, fragment: []const u8) !void {
    // One name can be written through several scopes in one function, so the
    // bucket is walked for the claim that carries this qualifier rather than
    // taking the first claim of that name.
    var calls = snapshot.relationships(.{ .kind = .calls, .source = from.id, .designator = designator.name });
    const call = while (calls.next()) |candidate| {
        if (designator.eql(candidate.claim.relationship.target.designator)) break candidate;
    } else {
        std.debug.print("no current call `{s}/{s}` from `{s}`\n", .{
            designator.qualifier orelse "-",
            designator.name,
            from.identity.name.?,
        });
        return error.TestExpectedCall;
    };
    try testing.expect(!call.resolution.isFact());
    const explanation = call.resolution.unresolved.explanation;
    if (std.mem.indexOf(u8, explanation, fragment) == null) {
        std.debug.print("call `{s}`: expected \"{s}\" in \"{s}\"\n", .{ designator.name, fragment, explanation });
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

    try expectUnresolvedCall(&snapshot, send, .{ .name = "flush" }, "qualifier is a parameter or local binding");
    try expectUnresolvedCall(&snapshot, flush, .{ .name = "reset" }, "enclosing container declares a member");
    try expectUnresolvedCall(&snapshot, run, .{ .name = "hidden", .qualifier = "wire" }, "no current top-level `pub fn`");
    try expectUnresolvedCall(&snapshot, run, .{ .name = "twice", .qualifier = "wire" }, "no current top-level `pub fn`");
    try expectUnresolvedCall(&snapshot, run, .{ .name = "flushAll", .qualifier = "wire" }, "no current top-level `pub fn`");
    try expectUnresolvedCall(&snapshot, run, .{ .name = "encode", .qualifier = "wire.Frame" }, "not a bare name or a name qualified by a local import alias");
    try expectUnresolvedCall(&snapshot, run, .{ .name = "print", .qualifier = "std.debug" }, "not a bare name or a name qualified by a local import alias");
    try expectUnresolvedCall(&snapshot, run, .{ .name = "run", .qualifier = "outside" }, "the path escapes the indexed root");
    try expectUnresolvedCall(&snapshot, run, .{ .name = "run", .qualifier = "upper" }, "no indexed Zig source unit has the path `zig/imports/Wire.zig`");
    try expectUnresolvedCall(&snapshot, run, .{ .name = "run", .qualifier = "absent" }, "no indexed Zig source unit has the path `zig/imports/absent.zig`");
    try expectUnresolvedCall(&snapshot, run, .{ .name = "run", .qualifier = "twin" }, "declares this name more than once");
    try expectUnresolvedCall(&snapshot, run, .{ .name = "writeString" }, "not a top-level `@import` alias");
    try expectUnresolvedCall(&snapshot, shadowed, .{ .name = "writeString" }, "qualifier is a parameter or local binding");

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
        try expectUnresolvedCall(&after, run, .{ .name = "writeString", .qualifier = "wire" }, "no current top-level `pub fn`");
        try expectUnresolvedCall(&after, send, .{ .name = "writeString", .qualifier = "wire" }, "no current top-level `pub fn`");
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
        try expectUnresolvedCall(&after, run, .{ .name = "writeString", .qualifier = "wire" }, "no current top-level `pub fn`");
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
        try expectUnresolvedCall(&after, run, .{ .name = "writeString", .qualifier = "wire" }, "analysis is not current");
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
        try expectUnresolvedCall(&after, run, .{ .name = "writeString", .qualifier = "wire" }, "no indexed Zig source unit has the path `zig/imports/wire.zig`");
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

// Three cases ADR 009 requires and the first implementation did not answer.
// Each is a way for a class-qualified call to claim more than the graph knows,
// and each is now a decline with its own reason
// ([Follow-up 016](../docs/followups/016_java_static_call_rule_narrow_gaps.md)).

test "an on-demand static import leaves every simple-name receiver unresolved" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit("module/src/main/java/lib/Util.java", .java,
        \\package lib;
        \\
        \\class Util {
        \\    public static String make() { return null; }
        \\}
        \\
    );
    // Why the import is not safe to ignore: `import static lib.Holder.*;`
    // brings `Holder`'s static fields into scope, a field obscures a type of
    // its name, and this frontend records no fields, so it cannot tell whether
    // `Util` here is the class or a field named after it.
    _ = try index.addUnit("module/src/main/java/lib/Holder.java", .java,
        \\package lib;
        \\
        \\class Holder {
        \\    static String keep() { return null; }
        \\}
        \\
    );
    _ = try index.addUnit("module/src/main/java/lib/Importer.java", .java,
        \\package lib;
        \\
        \\import static lib.Holder.*;
        \\
        \\class Importer {
        \\    Util field;
        \\    void declined() { Util.make(); }
        \\}
        \\
    );
    // The same call in a unit without the import, so the decline above is the
    // import's doing and not the fixture's.
    _ = try index.addUnit("module/src/main/java/lib/Plain.java", .java,
        \\package lib;
        \\
        \\class Plain {
        \\    void covered() { Util.make(); }
        \\}
        \\
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    try expectStaticCall(&snapshot, .{
        .path = "module/src/main/java/lib/Importer.java",
        .class = "Importer",
        .method = "declined",
        .call = "Util.make()",
        .expect = .{ .unresolved = "imports static members on demand" },
    });
    try expectStaticCall(&snapshot, .{
        .path = "module/src/main/java/lib/Plain.java",
        .class = "Plain",
        .method = "covered",
        .call = "Util.make()",
        .expect = .{ .fact = .{
            .path = "module/src/main/java/lib/Util.java",
            .class = "Util",
            .method = "make",
        } },
    });

    // A type position is not a place a variable can claim a name, so the field
    // type in the importing unit still resolves. The guard is about receivers.
    const importer = definitionIn(&snapshot, "module/src/main/java/lib/Importer.java", null, "Importer").?;
    const util = definitionIn(&snapshot, "module/src/main/java/lib/Util.java", null, "Util").?;
    var references = snapshot.relationships(.{ .kind = .references, .source = importer.id });
    var resolved = false;
    while (references.next()) |reference| {
        if (!reference.resolution.isFact()) continue;
        if (reference.claim.relationship.target.entity == util.id) resolved = true;
    }
    try testing.expect(resolved);
}

test "an on-demand import that is not static leaves the receiver alone" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();
    try addStaticCallProviders(&index);

    // `import lib.*;` imports types, never members, so no variable enters
    // scope and nothing can obscure the receiver name.
    _ = try index.addUnit("module/src/main/java/app/Wildcard.java", .java,
        \\package app;
        \\
        \\import lib.*;
        \\import lib.Util;
        \\
        \\class Wildcard {
        \\    void covered() { Util.make(); }
        \\}
        \\
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();
    try expectStaticCall(&snapshot, .{
        .path = "module/src/main/java/app/Wildcard.java",
        .class = "Wildcard",
        .method = "covered",
        .call = "Util.make()",
        .expect = .{ .fact = .{
            .path = "module/src/main/java/lib/Util.java",
            .class = "Util",
            .method = "make",
        } },
    });
}

test "a target with no static label declines as unrecorded, not as an instance method" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    // A provider as an older producer would have left it: the class shape and
    // the access are recorded, `java.static` is not. The label's absence is
    // what the reader has to answer for, and it is not the same answer as the
    // method being an instance method.
    const provider = try index.graph.addSourceUnit(
        "module/src/main/java/lib/Legacy.java",
        .java,
        "package lib;\nclass Legacy { public static String make() { return null; } }\n",
    );
    try recordUnlabelledJavaMethod(&index, provider, "Legacy", "make");

    _ = try index.addUnit("module/src/main/java/lib/Reader.java", .java,
        \\package lib;
        \\
        \\class Reader {
        \\    void declined() { Legacy.make(); }
        \\}
        \\
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();
    try expectStaticCall(&snapshot, .{
        .path = "module/src/main/java/lib/Reader.java",
        .class = "Reader",
        .method = "declined",
        .call = "Legacy.make()",
        .expect = .{ .unresolved = "carries no record of whether it is `static`" },
    });
}

/// Writes one Java class and one of its methods into the graph the way the Java
/// frontend does, minus the `java.static` label. There is no input that makes
/// the current frontend omit it, so the case a producer change would create is
/// built directly rather than left untested.
fn recordUnlabelledJavaMethod(
    index: *semidx.Index,
    unit: model.SourceUnitId,
    class: []const u8,
    method: []const u8,
) !void {
    var builder = semidx.contract.BatchBuilder.init(
        testing.allocator,
        unit,
        semidx.frontends.capabilitiesFor(.java),
    );
    defer builder.deinit();

    const evidence: model.SourceEvidence = .{
        .unit = unit,
        .range = .{ .start_byte = 0, .end_byte = 1, .start_row = 0, .start_column = 0, .end_row = 0, .end_column = 1 },
        .text = class,
    };
    const class_index = try builder.addEntity(.{
        .kind = .definition,
        .identity = .{
            .scope = .{ .unit = unit },
            .language = .java,
            .role = "class",
            .name = try builder.dupe(class),
            .signature = try builder.dupe(class),
            .container_path = &.{},
        },
        .evidence = evidence,
        .extension = .{ .namespace = "java", .labels = try builder.labels(&.{
            .{ .key = "java.construct", .value = "class_declaration" },
            .{ .key = "java.package", .value = "lib" },
            .{ .key = "java.supertypes", .value = "none" },
        }) },
        .resolution = .{ .fact = .{ .method = "class declaration in the analyzed source unit" } },
    });
    const method_index = try builder.addEntity(.{
        .kind = .definition,
        .identity = .{
            .scope = .{ .unit = unit },
            .language = .java,
            .role = "method",
            .name = try builder.dupe(method),
            .signature = try builder.dupe(method),
            .container_path = try builder.dupeSlice(&.{class}),
        },
        .evidence = evidence,
        .extension = .{ .namespace = "java", .labels = try builder.labels(&.{
            .{ .key = "java.construct", .value = "method_declaration" },
            .{ .key = "java.package", .value = "lib" },
            .{ .key = "java.access", .value = "public" },
        }) },
        .resolution = .{ .fact = .{ .method = "method declaration in the analyzed source unit" } },
    });
    try builder.addRelationship(.{
        .kind = .defines,
        .source = .unit_container,
        .target = .{ .local = class_index },
        .evidence = evidence,
        .resolution = .{ .fact = .{ .method = "declared directly in this source unit" } },
    });
    try builder.addRelationship(.{
        .kind = .defines,
        .source = .{ .entity = class_index },
        .target = .{ .local = method_index },
        .evidence = evidence,
        .resolution = .{ .fact = .{ .method = "declared directly in this class body" } },
    });

    _ = try semidx.reconcile.integrate(&index.graph, builder.batch());
    // The package hint is what `indexUnit` would have written, and the reader's
    // context is built from it.
    try index.analyzer.java_packages.note(&index.graph, unit);
}

test "renaming a file inside its own directory re-reads nothing" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write("demo/Greeter.java", greeter_java);
    _ = try tree.rescan();
    const baseline = tree.invocations();

    // The directory is what a Java source root and a Zig local import are read
    // against, so a new file name inside it changes nothing a frontend reads.
    try tree.move("demo/Greeter.java", "demo/Renamed.java");
    const outcome = try tree.rescan();

    try testing.expectEqual(@as(usize, 1), outcome.renamed);
    try testing.expectEqual(@as(usize, 0), outcome.analyzed);
    try testing.expectEqual(baseline, tree.invocations());
}

// A unit's place decides which other units it may resolve names to, so a move
// is a semantic change even though it changes no byte
// ([Follow-up 015](../docs/followups/015_unit_path_change_does_not_reanalyze.md)).

test "a caller moved out of its provider's source root loses the fact it recorded" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write(
        "module/src/main/java/lib/Util.java",
        "package lib;\nclass Util { public static String make() { return null; } }\n",
    );
    try tree.write(
        "module/src/main/java/lib/Caller.java",
        "package lib;\nclass Caller { void covered() { Util.make(); } }\n",
    );
    _ = try tree.rescan();

    {
        var before = try tree.index.publish();
        defer before.deinit();
        try expectStaticCall(&before, .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "covered",
            .call = "Util.make()",
            .expect = .{ .fact = .{
                .path = "module/src/main/java/lib/Util.java",
                .class = "Util",
                .method = "make",
            } },
        });
    }

    // Another module is another visibility scope. The caller may no longer
    // resolve `Util`, so the fact it recorded while it could must go with it.
    try tree.move(
        "module/src/main/java/lib/Caller.java",
        "other/src/main/java/lib/Caller.java",
    );
    const outcome = try tree.rescan();
    try testing.expectEqual(@as(usize, 1), outcome.renamed);

    var after = try tree.index.publish();
    defer after.deinit();
    try expectStaticCall(&after, .{
        .path = "other/src/main/java/lib/Caller.java",
        .class = "Caller",
        .method = "covered",
        .call = "Util.make()",
        .expect = .{ .unresolved = "source root this unit can see" },
    });
}

test "a provider moved into the reader's source root turns its unresolved call into a fact" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    try tree.write(
        "module/src/main/java/lib/Caller.java",
        "package lib;\nclass Caller { void call() { Util.make(); } }\n",
    );
    try tree.write(
        "other/src/main/java/lib/Util.java",
        "package lib;\nclass Util { public static String make() { return null; } }\n",
    );
    _ = try tree.rescan();

    {
        var before = try tree.index.publish();
        defer before.deinit();
        try expectStaticCall(&before, .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "call",
            .call = "Util.make()",
            .expect = .{ .unresolved = "source root this unit can see" },
        });
    }

    // The caller's call resolved to nothing, so it declared no dependency and
    // nothing names it. Only the move's own channel can reach it.
    try tree.move(
        "other/src/main/java/lib/Util.java",
        "module/src/main/java/lib/Util.java",
    );
    _ = try tree.rescan();

    var after = try tree.index.publish();
    defer after.deinit();
    try expectStaticCall(&after, .{
        .path = "module/src/main/java/lib/Caller.java",
        .class = "Caller",
        .method = "call",
        .call = "Util.make()",
        .expect = .{ .fact = .{
            .path = "module/src/main/java/lib/Util.java",
            .class = "Util",
            .method = "make",
        } },
    });
}

test "moving a directory costs the units in it and the readers they reach" {
    var tree = try Tree.init(testing.allocator);
    defer tree.deinit();
    // Four providers in one package, one reader of one of them, and a unit in
    // another package that reads nothing of it.
    try tree.write(
        "module/src/main/java/lib/A.java",
        "package lib;\nclass A { public static String a() { return null; } }\n",
    );
    try tree.write(
        "module/src/main/java/lib/B.java",
        "package lib;\nclass B { public static String b() { return null; } }\n",
    );
    try tree.write(
        "module/src/main/java/lib/C.java",
        "package lib;\nclass C { public static String c() { return null; } }\n",
    );
    try tree.write(
        "module/src/main/java/lib/Reader.java",
        "package lib;\nclass Reader { void call() { A.a(); } }\n",
    );
    try tree.write(
        "module/src/main/java/app/Elsewhere.java",
        "package app;\nclass Elsewhere { void call() { } }\n",
    );
    _ = try tree.rescan();
    const baseline = tree.invocations();

    try tree.move("module/src/main/java/lib/A.java", "moved/src/main/java/lib/A.java");
    try tree.move("module/src/main/java/lib/B.java", "moved/src/main/java/lib/B.java");
    try tree.move("module/src/main/java/lib/C.java", "moved/src/main/java/lib/C.java");
    const outcome = try tree.rescan();

    try testing.expectEqual(@as(usize, 3), outcome.renamed);
    // The three that moved, plus the reader whose answer they change. The unit
    // in another package is not touched: it declares nothing in `lib` and
    // imports nothing from it.
    try testing.expectEqual(@as(usize, 4), tree.invocations() - baseline);
    try testing.expectEqual(@as(usize, 1), outcome.invalidated);

    var after = try tree.index.publish();
    defer after.deinit();
    try expectStaticCall(&after, .{
        .path = "module/src/main/java/lib/Reader.java",
        .class = "Reader",
        .method = "call",
        .call = "A.a()",
        .expect = .{ .unresolved = "source root this unit can see" },
    });
}

// -- Plan 014 Stage 1: interfaces are declarations the graph holds ------------

// Written against [ADR 011](../docs/adr/011_java_hierarchy_from_indexed_source.md).
// Two questions run through every case below: an interface is a declaration on
// the same terms as a class, and nothing else became one.

/// The unit every interface case resolves against: one interface with the three
/// member shapes whose recorded modifiers differ, and one that extends it.
fn addInterfaceProviders(index: *semidx.Index) !void {
    _ = try index.addUnit(
        "module/src/main/java/lib/Shape.java",
        .java,
        \\package lib;
        \\
        \\interface Shape {
        \\    String NAME = "shape";
        \\
        \\    String describe();
        \\
        \\    default String label() { return describe(); }
        \\
        \\    static Shape none() { return null; }
        \\}
        \\
        ,
    );
    _ = try index.addUnit(
        "module/src/main/java/lib/Drawable.java",
        .java,
        \\package lib;
        \\
        \\interface Drawable extends Shape {
        \\    static String make() { return null; }
        \\}
        \\
        ,
    );
}

test "a top-level interface is a definition with the labels a class carries" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();
    try addInterfaceProviders(&index);

    var snapshot = try index.publish();
    defer snapshot.deinit();

    const shape = snapshot.findDefinition("module/src/main/java/lib/Shape.java", "Shape").?;
    try testing.expectEqualStrings("interface", shape.identity.role);
    try testing.expectEqual(@as(usize, 0), shape.identity.container_path.len);
    try testing.expectEqualStrings("interface_declaration", shape.extension.get("java.construct").?);
    try testing.expectEqualStrings("lib", shape.extension.get("java.package").?);
    // An interface with no `extends` declares no supertypes, exactly as a class
    // with no `extends` does; one that extends another declares them.
    try testing.expectEqualStrings("none", shape.extension.get("java.supertypes").?);
    const drawable = snapshot.findDefinition("module/src/main/java/lib/Drawable.java", "Drawable").?;
    try testing.expectEqualStrings("declared", drawable.extension.get("java.supertypes").?);

    // The interface introduces its methods, and only its methods: the constant
    // is outside this coverage and is reported rather than left looking absent.
    try testing.expectEqual(@as(usize, 3), snapshot.countRelationships(.{
        .kind = .defines,
        .source = shape.id,
    }));

    const describe = definitionIn(&snapshot, "module/src/main/java/lib/Shape.java", "Shape", "describe").?;
    try testing.expectEqualStrings("method", describe.identity.role);
    try testing.expectEqualStrings("Shape", describe.identity.container_path[0]);
    try testing.expectEqualStrings("describe()", describe.identity.signature.?);
    try testing.expectEqualStrings("String", describe.extension.get("java.return_type").?);

    // The modifiers Java defines rather than the modifiers the source writes.
    // A method with no access keyword is public here and package-private in a
    // class, `default` changes neither answer, and only `static` is static.
    const label = definitionIn(&snapshot, "module/src/main/java/lib/Shape.java", "Shape", "label").?;
    const none = definitionIn(&snapshot, "module/src/main/java/lib/Shape.java", "Shape", "none").?;
    try testing.expectEqualStrings("public", describe.extension.get("java.access").?);
    try testing.expectEqualStrings("false", describe.extension.get("java.static").?);
    try testing.expectEqualStrings("public", label.extension.get("java.access").?);
    try testing.expectEqualStrings("false", label.extension.get("java.static").?);
    try testing.expectEqualStrings("public", none.extension.get("java.access").?);
    try testing.expectEqualStrings("true", none.extension.get("java.static").?);

    // A method body inside an interface is read exactly as one inside a class:
    // `label` calls the only `describe` its own type declares.
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .calls,
        .source = label.id,
        .target = describe.id,
        .resolution = .fact,
    }));
    // And the return type of a method of this unit's own interface resolves to
    // it, which is the same local answer a class would get.
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .references,
        .source = none.id,
        .target = shape.id,
        .resolution = .fact,
    }));
}

test "a top-level interface reports no unsupported construct and the other type declarations still do" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit(
        "module/src/main/java/lib/Kinds.java",
        .java,
        \\package lib;
        \\
        \\interface Admitted {}
        \\
        \\enum Colour { RED }
        \\
        \\record Point(int x, int y) {}
        \\
        \\@interface Marker {}
        \\
        ,
    );
    // A member interface is not a top-level declaration. It keeps the treatment
    // every other member type has: reported unsupported, and still claiming its
    // name against the enclosing class.
    _ = try index.addUnit(
        "module/src/main/java/lib/Outer.java",
        .java,
        \\package lib;
        \\
        \\class Outer {
        \\    Nested nested;
        \\
        \\    interface Nested {}
        \\}
        \\
        ,
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    try testing.expect(snapshot.findDefinition("module/src/main/java/lib/Kinds.java", "Admitted") != null);
    try testing.expect(snapshot.findDefinition("module/src/main/java/lib/Kinds.java", "Colour") == null);
    try testing.expect(snapshot.findDefinition("module/src/main/java/lib/Kinds.java", "Point") == null);
    try testing.expect(snapshot.findDefinition("module/src/main/java/lib/Kinds.java", "Marker") == null);
    try testing.expect(snapshot.findDefinition("module/src/main/java/lib/Outer.java", "Nested") == null);

    var seen_interface = false;
    var seen = [_]bool{ false, false, false };
    const remaining = [_][]const u8{ "enum_declaration", "record_declaration", "annotation_type_declaration" };
    for (snapshot.diagnostics) |diagnostic| {
        if (diagnostic.kind != .unsupported_construct) continue;
        if (std.mem.indexOf(u8, diagnostic.message, "`interface_declaration` at the top level") != null) {
            seen_interface = true;
        }
        for (remaining, 0..) |kind, at| {
            if (std.mem.indexOf(u8, diagnostic.message, kind) != null) seen[at] = true;
        }
    }
    try testing.expect(!seen_interface);
    for (seen) |reported| try testing.expect(reported);

    // The member interface still gives its name another meaning, so the field
    // type stays unresolved rather than reaching a declaration.
    const outer = snapshot.findDefinition("module/src/main/java/lib/Outer.java", "Outer").?;
    try expectExplanation(try referenceFrom(&snapshot, outer.id, "Nested"), "member type");
}

test "a static call to an interface is decided by the conditions a class is decided by" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();
    try addInterfaceProviders(&index);

    _ = try index.addUnit(
        "module/src/main/java/lib/Caller.java",
        .java,
        \\package lib;
        \\
        \\class Caller {
        \\    void covered() { Shape.none(); }
        \\    void notStatic() { Shape.describe(); }
        \\    void missingMethod() { Shape.absent(); }
        \\    void targetHasSupertypes() { Drawable.make(); }
        \\}
        \\
        ,
    );
    // Another package reaching the interface by single-type import, which is
    // the same route a class is reached by.
    _ = try index.addUnit(
        "module/src/main/java/app/Importer.java",
        .java,
        \\package app;
        \\
        \\import lib.Shape;
        \\
        \\class Importer {
        \\    void covered() { Shape.none(); }
        \\}
        \\
        ,
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    const none: StaticTarget = .{
        .path = "module/src/main/java/lib/Shape.java",
        .class = "Shape",
        .method = "none",
    };
    const cases = [_]StaticCall{
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "covered",
            .call = "Shape.none()",
            .expect = .{ .fact = none },
        },
        .{
            .path = "module/src/main/java/app/Importer.java",
            .class = "Importer",
            .method = "covered",
            .call = "Shape.none()",
            .expect = .{ .fact = none },
        },
        // An interface method is public, so access never declines it; what
        // declines it is the modifier the source did not write.
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "notStatic",
            .call = "Shape.describe()",
            .designator = .{ .name = "describe", .qualifier = "Shape" },
            .expect = .{ .unresolved = "is not static" },
        },
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "missingMethod",
            .call = "Shape.absent()",
            .expect = .{ .unresolved = "no method of this name" },
        },
        // An interface that extends another may inherit a method of the name,
        // and the guard reads that from the same label a class carries.
        .{
            .path = "module/src/main/java/lib/Caller.java",
            .class = "Caller",
            .method = "targetHasSupertypes",
            .call = "Drawable.make()",
            .expect = .{ .unresolved = "supertypes" },
        },
    };
    for (cases) |case| try expectStaticCall(&snapshot, case);
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
}

test "a simple name reaches an interface another unit declares in the same package" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();
    try addInterfaceProviders(&index);

    const user = try index.addUnit("module/src/main/java/lib/User.java", .java,
        \\package lib;
        \\
        \\class User {
        \\    Shape shape;
        \\}
        \\
    );
    // The same name in another source root is another scope, for an interface
    // exactly as for a class.
    _ = try index.addUnit("other/src/main/java/lib/Outsider.java", .java,
        \\package lib;
        \\
        \\class Outsider {
        \\    Shape shape;
        \\}
        \\
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    const shape = snapshot.findDefinition("module/src/main/java/lib/Shape.java", "Shape").?;
    const class = snapshot.findDefinition("module/src/main/java/lib/User.java", "User").?;
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
        .kind = .references,
        .source = class.id,
        .target = shape.id,
        .resolution = .fact,
    }));
    // Reading it declares the dependency that keeps the fact current, the same
    // declaration a resolved class name makes.
    try testing.expect(index.graph.dependencies.count() > 0);
    var declared = false;
    for (index.graph.dependencies.declarations.items) |declaration| {
        if (declaration.dependent == user) declared = true;
    }
    try testing.expect(declared);

    const outsider = snapshot.findDefinition("other/src/main/java/lib/Outsider.java", "Outsider").?;
    try expectExplanation(
        try referenceFrom(&snapshot, outsider.id, "Shape"),
        "source root this unit can see",
    );
}

test "an interface constant obscures a receiver name exactly as a class field does" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();
    try addStaticCallProviders(&index);

    // `Util` is a class declaring a static `make`. Inside an interface that
    // binds `Util` to a constant, the receiver is a value and not that class.
    _ = try index.addUnit(
        "module/src/main/java/lib/Holder.java",
        .java,
        \\package lib;
        \\
        \\interface Holder {
        \\    String Util = "shadow";
        \\
        \\    default String call() { return Util.make(); }
        \\}
        \\
        ,
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    try expectStaticCall(&snapshot, .{
        .path = "module/src/main/java/lib/Holder.java",
        .class = "Holder",
        .method = "call",
        .call = "Util.make()",
        .expect = .{ .unresolved = "is declared here as a binding" },
    });
}

// -- Plan 013 Stage 1: a designator is a structured name ---------------------

/// The claim of `kind` from `source` whose designator holds `name`, or an error
/// naming what was looked for. It anchors on the name, because that is the key
/// the designator index holds.
fn designatedClaim(
    snapshot: *const semidx.Snapshot,
    source: model.EntityId,
    kind: model.RelationshipKind,
    name: []const u8,
) !model.Assertion {
    var found = snapshot.relationships(.{ .kind = kind, .source = source, .designator = name });
    return found.next() orelse {
        std.debug.print("no {t} designating `{s}`\n", .{ kind, name });
        return error.TestExpectedRelationship;
    };
}

fn expectDesignator(
    assertion: model.Assertion,
    expected: model.Designator,
    evidence_text: []const u8,
) !void {
    const recorded = assertion.claim.relationship.target.designator;
    try testing.expectEqualStrings(expected.name, recorded.name);
    if (expected.qualifier) |qualifier| {
        try testing.expectEqualStrings(qualifier, recorded.qualifier orelse {
            std.debug.print("`{s}` recorded no qualifier, expected `{s}`\n", .{ recorded.name, qualifier });
            return error.TestExpectedQualifier;
        });
    } else if (recorded.qualifier) |unwanted| {
        std.debug.print("`{s}` recorded qualifier `{s}`, expected none\n", .{ recorded.name, unwanted });
        return error.TestUnexpectedQualifier;
    }
    // The written form is the evidence, with the range that locates it. Where
    // the source wrote more than a bare name the two are different strings, and
    // that difference is what [ADR 010](../docs/adr/010_designator_is_a_structured_name.md)
    // is: a name in the graph, the text in the evidence.
    try testing.expectEqualStrings(evidence_text, assertion.evidence.?.text);
}

test "a java designator is the invoked name, and the receiver expression stays in the evidence" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit("demo/Caller.java", .java,
        \\package demo;
        \\
        \\class Caller {
        \\    Helper helper;
        \\    void run() {
        \\        helper.describe(1, 2);
        \\        missing(1, 2);
        \\    }
        \\}
        \\
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    const caller = snapshot.findDefinition("demo/Caller.java", "Caller").?;
    const run = snapshot.findDefinition("demo/Caller.java", "run").?;

    // A receiver this frontend reads as a value names no scope, so the claim
    // carries the method name alone.
    const through_value = try designatedClaim(&snapshot, run.id, .calls, "describe");
    try expectDesignator(through_value, .{ .name = "describe" }, "helper.describe(1, 2)");
    try testing.expect(!through_value.resolution.isFact());

    // An unqualified invocation was already a name, and its evidence is now the
    // invocation rather than a copy of that name.
    const unqualified = try designatedClaim(&snapshot, run.id, .calls, "missing");
    try expectDesignator(unqualified, .{ .name = "missing" }, "missing(1, 2)");

    // A type reference is outside this rewrite and keeps the name as written.
    const field_type = try designatedClaim(&snapshot, caller.id, .references, "Helper");
    try expectDesignator(field_type, .{ .name = "Helper" }, "Helper");
}

test "a java designator carries the class where the receiver was established as one" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit("demo/Util.java", .java,
        \\package demo;
        \\
        \\public class Util {
        \\    public static void twice() {}
        \\    public static void twice(String name) {}
        \\}
        \\
    );
    _ = try index.addUnit("demo/Caller.java", .java,
        \\package demo;
        \\
        \\class Caller {
        \\    void run() {
        \\        Util.twice();
        \\    }
        \\}
        \\
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    const run = snapshot.findDefinition("demo/Caller.java", "run").?;
    const overloaded = try designatedClaim(&snapshot, run.id, .calls, "twice");
    // The class was established; only the method choice failed. The class is a
    // name the source wrote, so it is recorded as one.
    try expectDesignator(overloaded, .{ .name = "twice", .qualifier = "Util" }, "Util.twice()");
    try expectExplanation(overloaded, "overloads are not resolved");
}

test "a zig designator is the member name, qualified only by an import path" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit("demo/calls.zig", .zig,
        \\const std = @import("std");
        \\
        \\pub fn run(self: *@This()) void {
        \\    std.debug.print("x", .{});
        \\    self.bucket();
        \\}
        \\
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    const run = snapshot.findDefinition("demo/calls.zig", "run").?;

    const through_import = try designatedClaim(&snapshot, run.id, .calls, "print");
    try expectDesignator(through_import, .{ .name = "print", .qualifier = "std.debug" }, "std.debug.print");

    // `self` is a parameter, so the path is rooted in a value and names no
    // scope this frontend may claim the source wrote.
    const through_value = try designatedClaim(&snapshot, run.id, .calls, "bucket");
    try expectDesignator(through_value, .{ .name = "bucket" }, "self.bucket");
}

test "a clojure designator is the symbol's name, qualified by its namespace" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit("demo/join.clj", .clojure,
        \\(ns demo.join)
        \\(defn run [xs]
        \\  (str/join "," xs))
        \\
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    const run = snapshot.findDefinition("demo/join.clj", "run").?;
    const qualified = try designatedClaim(&snapshot, run.id, .calls, "join");
    try expectDesignator(qualified, .{ .name = "join", .qualifier = "str" }, "str/join");
}

test "two call sites naming one method share one designator key" {
    var index = try semidx.Index.init(testing.allocator, "tree");
    defer index.deinit();

    _ = try index.addUnit("demo/Twin.java", .java,
        \\package demo;
        \\
        \\class Twin {
        \\    Helper one;
        \\    Helper two;
        \\    void first() {
        \\        one.describe(1);
        \\    }
        \\    void second() {
        \\        two.describe(2, 3);
        \\    }
        \\}
        \\
    );

    var snapshot = try index.publish();
    defer snapshot.deinit();

    // Two invocations, two receivers, two spans of source text — and one name,
    // which is what a definition of that name can be asked by. Before ADR 010
    // these were two keys and this count was 1.
    try testing.expectEqual(@as(usize, 2), snapshot.countRelationships(.{
        .kind = .calls,
        .designator = "describe",
        .resolution = .unresolved,
    }));
}

test "the fixture corpus records the same facts it did before designators became names" {
    var index = try semidx.Index.init(testing.allocator, build_options.fixtures_dir);
    defer index.deinit();

    var root = try std.Io.Dir.cwd().openDir(testing.io, build_options.fixtures_dir, .{ .iterate = true, .follow_symlinks = false });
    defer root.close(testing.io);
    var found = try semidx.source.discovery.scanDir(testing.allocator, testing.io, root, build_options.fixtures_dir, .{});
    defer found.deinit();
    _ = try index.applyScan(found);

    var snapshot = try index.publish();
    defer snapshot.deinit();

    // ADR 010 required these to be identical before and after it: that stage
    // changed what a claim says its target is called, and nothing about what is
    // a fact.
    //
    // [ADR 011](../docs/adr/011_java_hierarchy_from_indexed_source.md) moved
    // them, and only by adding `java/Shape.java` to the corpus. Admitting
    // interfaces moved nothing that was already here: with the frontend changed
    // and the fixture absent the totals were still 134, 465, 396, 69, 0 and 54.
    // With the fixture the delta is exactly what one interface declaring three
    // methods contributes — 5 existence claims (the file and four definitions),
    // 1 `contains`, 4 `defines`, 3 `references` (two `String` return types
    // unresolved, `none`'s own `Shape` a local fact), 1 `calls` (`label` calls
    // `describe`), and 4 identity correspondences for `Greeter.java`, which is
    // reanalyzed because package `demo` gained an export.
    //
    // Diagnostics do not move, and that is the point of the fixture: a
    // top-level interface no longer reports an unsupported construct.
    try testing.expectEqual(@as(usize, 138), snapshot.countEntities(.{ .kind = .definition }));
    try testing.expectEqual(@as(usize, 483), snapshot.assertions.len);
    try testing.expectEqual(@as(usize, 412), snapshot.countAssertions(.{ .resolution = .fact }));
    try testing.expectEqual(@as(usize, 71), snapshot.countUnresolvedAssertions());
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
    try testing.expectEqual(@as(usize, 54), snapshot.diagnostics.len);
}
