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
    try testing.expectEqual(@as(usize, 5), snapshot.countEntities(.{ .kind = .definition }));

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

    // The `greet` method inside `Greeter`, the `name` field, the import, the
    // constant, and the test are not definitions, and they are reported
    // instead of looking absent.
    try testing.expectEqual(@as(usize, 1), snapshot.countEntities(.{ .kind = .definition, .name = "greet" }));
    for ([_][]const u8{ "name", "std", "limit" }) |name| {
        try testing.expect(snapshot.findDefinition(zig_path, name) == null);
    }
    try testing.expect(hasDiagnosticContaining(&snapshot, .unsupported_construct, "2 top-level `variable_declaration`"));
    try testing.expect(hasDiagnosticContaining(&snapshot, .unsupported_construct, "`test_declaration`"));
    try testing.expect(hasDiagnosticContaining(&snapshot, .unsupported_construct, "`function_declaration` declared inside a top-level container"));
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
    try testing.expectEqual(@as(usize, 5), outcome.preserved);
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
    try testing.expectEqual(@as(usize, 5), outcome.preserved);
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
    try testing.expectEqual(@as(usize, 4), outcome.preserved);
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
    try testing.expectEqual(@as(usize, 5), repaired.preserved);
    try testing.expectEqual(@as(usize, 0), repaired.created);

    var repaired_snapshot = try fixture.index.publish();
    defer repaired_snapshot.deinit();
    try testing.expectEqual(greet_before.id, repaired_snapshot.findDefinition(zig_path, "greet").?.id);
    try testing.expectEqual(@as(usize, 0), repaired_snapshot.countDiagnostics(.analysis_failed));
}
