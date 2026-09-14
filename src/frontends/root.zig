//! Language frontends and the parser lifecycle around them.
//!
//! A frontend is chosen by the language a source unit is presented as. Which
//! frontend ran, and whether it could run at all, is always visible to the
//! consumer: a parser that cannot produce a tree yields an unavailable-analysis
//! diagnostic, never an empty batch that reads as confirmed absence.

const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("semidx_core");
const ts = @import("semidx_tree_sitter");

pub const java = @import("java.zig");
pub const java_packages = @import("java_packages.zig");
pub const clojure = @import("clojure.zig");

const model = core.model;
const contract = core.contract;

pub fn capabilitiesFor(language: model.Language) contract.Capabilities {
    return switch (language) {
        .java => java.capabilities,
        .clojure => clojure.capabilities,
    };
}

fn grammarFor(language: model.Language) ts.Grammar {
    return switch (language) {
        .java => java.grammar,
        .clojure => clojure.grammar,
    };
}

pub const Analyzer = struct {
    gpa: Allocator,
    parsers: [std.enums.values(model.Language).len]?ts.Parser,
    /// A local guard against pathological input. Exceeding it is reported as
    /// failed analysis of that unit and leaves the rest of the graph alone.
    budget: ?ts.Budget,
    /// How many times a frontend has been asked to read a source unit.
    ///
    /// This is what makes "only the affected region was reanalyzed" a measured
    /// claim rather than an assumed one: a rescan of a repository with one
    /// changed file must move this by exactly one, whatever the repository's
    /// size.
    invocations: usize,
    /// Which units have declared classes in which Java package, so a Java
    /// unit's context is built from its own package rather than from the whole
    /// repository. Meaningful for the one graph this analyzer indexes into.
    java_packages: java_packages.Packages,

    pub const default_budget: ts.Budget = .{ .max_bytes = 8 << 20 };

    pub fn init(gpa: Allocator, budget: ?ts.Budget) Analyzer {
        return .{
            .gpa = gpa,
            .parsers = @splat(null),
            .budget = budget,
            .invocations = 0,
            .java_packages = java_packages.Packages.init(gpa),
        };
    }

    pub fn deinit(self: *Analyzer) void {
        for (&self.parsers) |*slot| {
            if (slot.*) |*parser| parser.deinit();
            slot.* = null;
        }
        self.java_packages.deinit();
        self.* = undefined;
    }

    fn parserFor(self: *Analyzer, language: model.Language) ts.Error!*ts.Parser {
        const slot = &self.parsers[@intFromEnum(language)];
        if (slot.* == null) slot.* = try ts.Parser.init(grammarFor(language));
        return &slot.*.?;
    }

    /// Runs the frontend for one source unit into `builder`.
    ///
    /// A changed unit is reparsed in full. Incrementality here is graph-level:
    /// only the changed unit is reanalyzed, and its entities keep their
    /// identities. Parser-level reuse would need the edit ranges this pipeline
    /// does not receive; see `tree_sitter.Parser.parse`.
    ///
    /// `graph` is where repository context is read from. Without one, the unit
    /// is analyzed on its own and every name that leaves it stays unresolved.
    pub fn analyze(
        self: *Analyzer,
        graph: ?*core.Graph,
        input: contract.FrontendInput,
        builder: *contract.BatchBuilder,
    ) !void {
        const language = input.unit.language;
        self.invocations += 1;

        const parser = self.parserFor(language) catch {
            try builder.addDiagnostic(.analysis_unavailable, try builder.print(
                "no {s} parser is available in this build, so the unit was not analyzed",
                .{language.tag()},
            ));
            return;
        };

        var tree = parser.parse(input.unit.bytes, self.budget) catch {
            try builder.addDiagnostic(.analysis_unavailable, try builder.print(
                "the {s} parser produced no tree for this source unit, so it was not analyzed",
                .{language.tag()},
            ));
            return;
        };
        defer tree.deinit();

        switch (language) {
            .java => {
                var scratch = std.heap.ArenaAllocator.init(self.gpa);
                defer scratch.deinit();
                const context = if (graph) |repository|
                    try self.javaContext(repository, input.unit.id, tree.root(), input.unit.bytes, scratch.allocator())
                else
                    java.Context.empty;
                try java.analyze(builder, input, tree, context);
            },
            .clojure => try clojure.analyze(builder, input, tree),
        }
    }

    fn javaContext(
        self: *Analyzer,
        graph: *core.Graph,
        unit: model.SourceUnitId,
        root: ts.Node,
        bytes: []const u8,
        allocator: Allocator,
    ) !java.Context {
        // A unit that does not parse yields no assertions, so it needs no
        // context either.
        if (root.hasError()) return java.Context.empty;
        const package = (try java.declaredPackage(allocator, root, bytes)) orelse
            return java.Context.empty;
        return self.java_packages.context(graph, package, unit, allocator);
    }

    /// Reanalyzes one source unit and applies the result to the graph.
    pub fn indexUnit(
        self: *Analyzer,
        graph: *core.Graph,
        unit: model.SourceUnitId,
    ) !core.reconcile.Outcome {
        const input = graph.frontendInput(unit) orelse return error.UnknownSourceUnit;
        var builder = contract.BatchBuilder.init(
            self.gpa,
            unit,
            capabilitiesFor(input.unit.language),
        );
        defer builder.deinit();
        try self.analyze(graph, input, &builder);
        const outcome = try core.reconcile.integrate(graph, builder.batch());
        if (input.unit.language == .java) try self.java_packages.note(graph, unit);
        return outcome;
    }
};

const testing = std.testing;

test "the java frontend keeps parse node types out of the shared core" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();

    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit(
        "Greeter.java",
        .java,
        "class Greeter { String greet() { return greeting(); } String greeting() { return \"hi\"; } }",
    );
    _ = try analyzer.indexUnit(&graph, unit);

    var snapshot = try graph.publish();
    defer snapshot.deinit();

    const greet = snapshot.findDefinition("Greeter.java", "greet").?;
    try testing.expectEqualStrings("method", greet.identity.role);
    try testing.expectEqualStrings("java", greet.extension.namespace);
    // The parse node type is retained as a language extension label, not as a
    // shared-core kind.
    try testing.expectEqualStrings("method_declaration", greet.extension.get("java.construct").?);
    try testing.expectEqual(model.EntityKind.definition, greet.kind);
}

fn addJava(
    analyzer: *Analyzer,
    graph: *core.Graph,
    path: []const u8,
    source: []const u8,
) !model.SourceUnitId {
    const unit = try graph.addSourceUnit(path, .java, source);
    _ = try analyzer.indexUnit(graph, unit);
    return unit;
}

/// The context `unit` would be analyzed with, as `declaredPackage` reads it.
fn contextFor(
    analyzer: *Analyzer,
    graph: *core.Graph,
    unit: model.SourceUnitId,
    allocator: Allocator,
) !java.Context {
    const input = graph.frontendInput(unit).?;
    var parser = try ts.Parser.init(.java);
    defer parser.deinit();
    var tree = try parser.parse(input.unit.bytes, null);
    defer tree.deinit();
    return analyzer.javaContext(graph, unit, tree.root(), input.unit.bytes, allocator);
}

test "a java unit alone receives an empty context" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const unit = try addJava(&analyzer, &graph, "demo/Greeter.java", "package demo;\nclass Greeter { Helper helper; }\n");
    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();
    const context = try contextFor(&analyzer, &graph, unit, scratch.allocator());
    try testing.expectEqualStrings("demo", context.package);
    try testing.expectEqual(@as(usize, 0), context.types.len);
    try testing.expect(context.lookup("demo", "Greeter") == null);
}

test "a java unit's context names the one class of that name its package declares elsewhere" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const helper = try addJava(&analyzer, &graph, "demo/Helper.java", "package demo;\nclass Helper {}\n");
    const greeter = try addJava(&analyzer, &graph, "demo/Greeter.java", "package demo;\nclass Greeter {}\n");

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    const helper_class = snapshot.findDefinition("demo/Helper.java", "Helper").?;

    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();
    const context = try contextFor(&analyzer, &graph, greeter, scratch.allocator());
    const binding = context.lookup("demo", "Helper").?;
    try testing.expectEqual(helper_class.id, binding.unique.entity);
    try testing.expectEqual(helper, binding.unique.provider);

    // A binding answers only for the package it was read for.
    try testing.expect(context.lookup("other", "Helper") == null);
}

test "a class name declared twice in a package reaches the context as ambiguous" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    _ = try addJava(&analyzer, &graph, "one/Helper.java", "package demo;\nclass Helper {}\n");
    _ = try addJava(&analyzer, &graph, "two/Helper.java", "package demo;\nclass Helper {}\n");
    const greeter = try addJava(&analyzer, &graph, "demo/Greeter.java", "package demo;\nclass Greeter {}\n");

    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();
    const context = try contextFor(&analyzer, &graph, greeter, scratch.allocator());
    try testing.expectEqual(@as(u32, 2), context.lookup("demo", "Helper").?.ambiguous);
}

test "a java context leaves out other packages, the default package, the unit itself, and stale classes" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    _ = try addJava(&analyzer, &graph, "other/Helper.java", "package other;\nclass Helper {}\n");
    _ = try addJava(&analyzer, &graph, "Loose.java", "class Loose {}\n");
    _ = try addJava(&analyzer, &graph, "demo/sub/Deep.java", "package demo.sub;\nclass Deep {}\n");
    const edited = try addJava(&analyzer, &graph, "demo/Edited.java", "package demo;\nclass Edited {}\n");
    const greeter = try addJava(
        &analyzer,
        &graph,
        "demo/Greeter.java",
        "@Deprecated package demo;\nclass Greeter {}\nclass Second {}\n",
    );

    // Edited into source that does not parse: its class is still recorded, but
    // it is no longer a current fact anything may be resolved to.
    _ = try graph.setSourceUnitBytes(edited, "package demo;\nclass Edited {\n");
    const failed = try analyzer.indexUnit(&graph, edited);
    try testing.expect(!failed.applied);

    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();
    const context = try contextFor(&analyzer, &graph, greeter, scratch.allocator());
    // The annotation is not part of the package name.
    try testing.expectEqualStrings("demo", context.package);
    try testing.expect(context.lookup("demo", "Helper") == null);
    try testing.expect(context.lookup("demo", "Loose") == null);
    try testing.expect(context.lookup("demo", "Deep") == null);
    try testing.expect(context.lookup("demo", "Edited") == null);
    try testing.expect(context.lookup("demo", "Greeter") == null);
    try testing.expect(context.lookup("demo", "Second") == null);
    try testing.expectEqual(@as(usize, 0), context.types.len);

    // Repaired, it is current again and back in the context.
    _ = try graph.setSourceUnitBytes(edited, "package   demo ;\nclass Edited {}\n");
    _ = try analyzer.indexUnit(&graph, edited);
    const repaired = try contextFor(&analyzer, &graph, greeter, scratch.allocator());
    try testing.expect(repaired.lookup("demo", "Edited") != null);
}

test "the clojure frontend keeps its own vocabulary in extension payloads" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();

    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit(
        "greeter.clj",
        .clojure,
        "(ns demo.greeter)\n(defn greet [] (str \"hi\"))\n",
    );
    _ = try analyzer.indexUnit(&graph, unit);

    var snapshot = try graph.publish();
    defer snapshot.deinit();

    const namespace = snapshot.findDefinition("greeter.clj", "demo.greeter").?;
    try testing.expectEqual(model.EntityKind.definition, namespace.kind);
    try testing.expectEqualStrings("namespace", namespace.identity.role);
    try testing.expectEqualStrings("ns", namespace.extension.get("clojure.form").?);

    const greet = snapshot.findDefinition("greeter.clj", "greet").?;
    try testing.expectEqualStrings("defn", greet.extension.get("clojure.form").?);
    try testing.expectEqualStrings("true", greet.extension.get("clojure.var").?);
    try testing.expectEqualStrings("greet/0", greet.identity.signature.?);
}

test "both frontends describe the same core kinds" {
    // Coverage differs; the core meaning does not. Both frontends produce
    // definitions and the same three relationship kinds.
    for ([_]model.Language{ .java, .clojure }) |language| {
        const capabilities = capabilitiesFor(language);
        try testing.expectEqual(language, capabilities.language);
        try testing.expectEqual(@as(usize, 3), capabilities.relationship_kinds.len);
        try testing.expect(capabilities.coverage_note.len > 0);
    }
    try testing.expect(!std.mem.eql(
        u8,
        capabilitiesFor(.java).producer.name,
        capabilitiesFor(.clojure).producer.name,
    ));
}

test "a parse failure is reported as unavailable analysis, not as no entities" {
    // A zero byte budget cancels the parse, which is the same path a missing
    // or failing parser takes.
    var analyzer = Analyzer.init(testing.allocator, .{ .max_bytes = 0 });
    defer analyzer.deinit();

    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(testing.allocator);
    try source.appendSlice(testing.allocator, "class Greeter {\n");
    for (0..4000) |index| {
        try source.print(testing.allocator, "  String m{d}() {{ return \"x\"; }}\n", .{index});
    }
    try source.appendSlice(testing.allocator, "}\n");

    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("Greeter.java", .java, source.items);
    const outcome = try analyzer.indexUnit(&graph, unit);
    try testing.expect(!outcome.applied);

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try testing.expectEqual(@as(usize, 0), snapshot.countEntities(.{ .kind = .definition }));
    try testing.expectEqual(@as(usize, 1), snapshot.countDiagnostics(.analysis_unavailable));
    try testing.expectEqual(@as(usize, 0), snapshot.countDiagnostics(.confirmed_absence));
}

test "a source unit with no definitions reports confirmed absence" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();

    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("Empty.java", .java, "package demo;\n");
    const outcome = try analyzer.indexUnit(&graph, unit);
    try testing.expect(outcome.applied);

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try testing.expectEqual(@as(usize, 0), snapshot.countEntities(.{ .kind = .definition }));
    try testing.expectEqual(@as(usize, 1), snapshot.countDiagnostics(.confirmed_absence));
    try testing.expectEqual(@as(usize, 0), snapshot.countDiagnostics(.analysis_unavailable));
}

test "source that does not parse is reported as failed analysis" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();

    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();
    const unit = try graph.addSourceUnit("Broken.java", .java, "class Greeter { String greet( \n");
    const outcome = try analyzer.indexUnit(&graph, unit);
    try testing.expect(!outcome.applied);

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try testing.expectEqual(@as(usize, 1), snapshot.countDiagnostics(.analysis_failed));
    try testing.expectEqual(@as(usize, 0), snapshot.countEntities(.{ .kind = .definition }));
}
