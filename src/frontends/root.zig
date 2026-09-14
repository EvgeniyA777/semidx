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

    pub const default_budget: ts.Budget = .{ .max_bytes = 8 << 20 };

    pub fn init(gpa: Allocator, budget: ?ts.Budget) Analyzer {
        return .{
            .gpa = gpa,
            .parsers = @splat(null),
            .budget = budget,
        };
    }

    pub fn deinit(self: *Analyzer) void {
        for (&self.parsers) |*slot| {
            if (slot.*) |*parser| parser.deinit();
            slot.* = null;
        }
        self.* = undefined;
    }

    fn parserFor(self: *Analyzer, language: model.Language) ts.Error!*ts.Parser {
        const slot = &self.parsers[@intFromEnum(language)];
        if (slot.* == null) slot.* = try ts.Parser.init(grammarFor(language));
        return &slot.*.?;
    }

    /// Runs the frontend for one source unit into `builder`.
    ///
    /// The slice reparses a changed unit in full rather than feeding the
    /// previous tree back: reusing a tree requires the edit ranges that
    /// produced it, and this pipeline receives replacement contents rather than
    /// edits. Incrementality here is graph-level — only the changed unit is
    /// reanalyzed — and `contract.PreviousParse` is where a future adapter that
    /// does track edits would supply the tree.
    pub fn analyze(
        self: *Analyzer,
        input: contract.FrontendInput,
        builder: *contract.BatchBuilder,
    ) !void {
        const language = input.unit.language;

        const parser = self.parserFor(language) catch {
            try builder.addDiagnostic(.analysis_unavailable, try builder.print(
                "no {s} parser is available in this build, so the unit was not analyzed",
                .{language.tag()},
            ));
            return;
        };

        var tree = parser.parse(input.unit.bytes, null, self.budget) catch {
            try builder.addDiagnostic(.analysis_unavailable, try builder.print(
                "the {s} parser produced no tree for this source unit, so it was not analyzed",
                .{language.tag()},
            ));
            return;
        };
        defer tree.deinit();

        switch (language) {
            .java => try java.analyze(builder, input, tree),
            .clojure => try clojure.analyze(builder, input, tree),
        }
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
        try self.analyze(input, &builder);
        return core.reconcile.integrate(graph, builder.batch());
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
    try testing.expectEqual(@as(usize, 0), snapshot.countEntities(.definition));
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
    try testing.expectEqual(@as(usize, 0), snapshot.countEntities(.definition));
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
    try testing.expectEqual(@as(usize, 0), snapshot.countEntities(.definition));
}
