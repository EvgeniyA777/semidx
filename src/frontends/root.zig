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
pub const java_members = @import("java_members.zig");
pub const java_hierarchy = @import("java_hierarchy.zig");
pub const clojure = @import("clojure.zig");
pub const zig = @import("zig.zig");

const model = core.model;
const contract = core.contract;

pub fn capabilitiesFor(language: model.Language) contract.Capabilities {
    return switch (language) {
        .java => java.capabilities,
        .clojure => clojure.capabilities,
        .zig => zig.capabilities,
    };
}

fn grammarFor(language: model.Language) ts.Grammar {
    return switch (language) {
        .java => java.grammar,
        .clojure => clojure.grammar,
        .zig => zig.grammar,
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
    /// Which units have read which `Class.method` pair, so a provider edit
    /// reaches the callers it can change without reanalyzing a package.
    /// Populated by the Java frontend's readers; a superset, never an answer.
    java_members: java_members.Members,

    pub const default_budget: ts.Budget = .{ .max_bytes = 8 << 20 };

    pub fn init(gpa: Allocator, budget: ?ts.Budget) Analyzer {
        return .{
            .gpa = gpa,
            .parsers = @splat(null),
            .budget = budget,
            .invocations = 0,
            .java_packages = java_packages.Packages.init(gpa),
            .java_members = java_members.Members.init(gpa),
        };
    }

    pub fn deinit(self: *Analyzer) void {
        for (&self.parsers) |*slot| {
            if (slot.*) |*parser| parser.deinit();
            slot.* = null;
        }
        self.java_packages.deinit();
        self.java_members.deinit();
        self.* = undefined;
    }

    fn parserFor(self: *Analyzer, language: model.Language) ts.Error!*ts.Parser {
        const slot = &self.parsers[@intFromEnum(language)];
        if (slot.* == null) slot.* = try ts.Parser.init(grammarFor(language));
        return &slot.*.?;
    }

    /// Whether a parser for `language` can be created in this build, without
    /// analyzing anything. A consumer reporting parser availability asks here
    /// rather than reaching past the frontends to the parser adapter.
    pub fn probeParser(self: *Analyzer, language: model.Language) ts.Error!void {
        _ = try self.parserFor(language);
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
            .zig => {
                var scratch = std.heap.ArenaAllocator.init(self.gpa);
                defer scratch.deinit();
                const context = if (graph) |repository|
                    try zigContext(repository, input.unit, tree.root(), scratch.allocator())
                else
                    zig.Context.empty;
                try zig.analyze(builder, input, tree, context);
            },
        }
    }

    /// The indexed Zig units the unit's top-level imports name, read from the
    /// graph by exact root-relative path. A path no live Zig unit has is left
    /// out, and the frontend reports it.
    fn zigContext(
        graph: *core.Graph,
        unit: contract.SourceUnit,
        root: ts.Node,
        allocator: Allocator,
    ) !zig.Context {
        // A unit that does not parse yields no assertions, so it needs no
        // providers either.
        if (root.hasError()) return .{ .repository = true, .providers = &.{} };
        var providers: std.ArrayList(zig.Provider) = .empty;
        for (try zig.localImportPaths(allocator, root, unit.bytes, unit.path)) |path| {
            const id = graph.unitByPath(path) orelse continue;
            const record = graph.unit(id) orelse continue;
            if (!record.isLive() or record.language != .zig) continue;
            const current = record.analysis() == .current;
            try providers.append(allocator, .{
                .path = path,
                .unit = id,
                .current = current,
                .exports = if (current) try zigExports(graph, id, allocator) else &.{},
            });
        }
        return .{ .repository = true, .providers = providers.items };
    }

    /// The functions a Zig unit currently exports: live top-level function
    /// definitions it labels exported, whose existence the Zig frontend
    /// recorded as a current fact.
    fn zigExports(
        graph: *core.Graph,
        unit: model.SourceUnitId,
        allocator: Allocator,
    ) ![]const zig.Export {
        var definitions: std.ArrayList(model.EntityId) = .empty;
        try graph.definitionsInUnit(unit, &definitions, allocator);

        var exports: std.ArrayList(zig.Export) = .empty;
        for (definitions.items) |id| {
            const entity = graph.entity(id).?;
            if (entity.identity.language != .zig) continue;
            if (!std.mem.eql(u8, entity.identity.role, "function")) continue;
            if (entity.identity.container_path.len != 0) continue;
            const name = entity.identity.name orelse continue;
            if (!std.mem.eql(u8, entity.extension.namespace, "zig")) continue;
            const label = entity.extension.get(zig.export_label.key) orelse continue;
            if (!std.mem.eql(u8, label, zig.export_label.value)) continue;
            const fact = graph.currentDefinitionFact(id) orelse continue;
            if (!std.mem.eql(u8, fact.producer.name, zig.capabilities.producer.name)) continue;
            try exports.append(allocator, .{ .name = name, .entity = id });
        }
        return exports.items;
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
        const record = graph.unit(unit) orelse return java.Context.empty;
        const source_root = java.sourceRoot(record.path, package);
        const imports = try java.singleTypeImports(allocator, root, bytes);
        // Remember where this unit reads from even when nothing resolves, so a
        // class appearing in an imported package later reaches the importer.
        try self.java_packages.noteImports(unit, imports);
        var context = try self.java_packages.context(
            graph,
            package,
            unit,
            source_root,
            imports,
            allocator,
        );

        // What the unit writes after a `.` is both what it must be able to
        // answer and what it must be reached for later. The pairs are recorded
        // as read before anything is resolved, because the reader that most
        // needs reaching is the one whose call resolves to nothing today.
        // What the unit writes after a `.`, from both sides: the name itself
        // where it may be a type, and the declared type of the binding where it
        // is a value. Both are recorded as read before anything is resolved,
        // because the reader that most needs reaching is the one whose call
        // resolves to nothing today.
        const named = try java.staticCallReceivers(allocator, root, bytes);
        const valued = try java.valueReceiverPairs(allocator, root, bytes);
        const receivers = try std.mem.concat(allocator, java.Receiver, &.{ named, valued });
        for (receivers) |receiver| {
            try self.java_members.noteReader(unit, receiver.class, receiver.method);
        }
        context.members = try java_members.membersFor(graph, context, receivers, allocator);

        // The same shape, for the types this unit names as supertypes: the
        // names are recorded as read before anything is resolved, so a unit
        // whose chain is open today is reached when the type that closes it
        // appears ([ADR 011](../../docs/adr/011_java_hierarchy_from_indexed_source.md), D7).
        // A receiver's declared type needs its own chain answered too, so the
        // names asked about are the supertypes this unit writes and the types
        // its value receivers are declared with.
        var asked: std.ArrayList([]const u8) = .empty;
        try asked.appendSlice(allocator, try java.supertypeNames(allocator, root, bytes));
        for (valued) |pair| {
            if (std.mem.indexOfScalar(u8, pair.class, 0) != null) continue;
            var seen = false;
            for (asked.items) |name| {
                if (std.mem.eql(u8, name, pair.class)) seen = true;
            }
            if (!seen) try asked.append(allocator, pair.class);
        }
        for (asked.items) |name| try self.java_members.noteTypeReader(unit, name);
        context.hierarchies = try java_hierarchy.hierarchiesFor(graph, context, asked.items, allocator);
        // A reader depends on every type its walk can reach, not only on the
        // one it named, so the whole closure is hinted too.
        for (context.hierarchies) |reached| {
            for (reached.types) |type_name| try self.java_members.noteTypeReader(unit, type_name);
        }
        return context;
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

    // Two files of one package may each declare a non-public class of the same
    // name, so ambiguity is expressed the way Java allows it: one source root,
    // one package, two file names.
    _ = try addJava(&analyzer, &graph, "demo/First.java", "package demo;\nclass Helper {}\n");
    _ = try addJava(&analyzer, &graph, "demo/Second.java", "package demo;\nclass Helper {}\n");
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

test "the java and clojure frontends describe the same core kinds" {
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

fn indexZig(analyzer: *Analyzer, graph: *core.Graph, source: []const u8) !core.reconcile.Outcome {
    const unit = try graph.addSourceUnit("probe.zig", .zig, source);
    return analyzer.indexUnit(graph, unit);
}

test "a zig unit with only uncovered declarations yields no invented facts" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const outcome = try indexZig(&analyzer, &graph, "const std = @import(\"std\");\nconst io = @import(\"io\");\ntest \"t\" {}\n");
    try testing.expect(outcome.applied);

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try testing.expectEqual(@as(usize, 0), snapshot.countEntities(.{ .kind = .definition }));
    try testing.expectEqual(@as(usize, 0), snapshot.countAssertions(.{ .resolution = .fact, .producer = "frontend.zig" }));
    // Two uncovered kinds, each reported once with its count, beside the
    // narrower claim that no covered declaration is there.
    try testing.expectEqual(@as(usize, 2), snapshot.countDiagnostics(.unsupported_construct));
    try testing.expectEqual(@as(usize, 1), snapshot.countDiagnostics(.confirmed_absence));
}

test "only exact zig declaration shapes become definitions" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const outcome = try indexZig(&analyzer, &graph,
        \\const Plain = struct { a: u8 };
        \\pub const Packed = packed struct { bits: u8 };
        \\const Typed: type = enum { a };
        \\const Tagged = union(enum) { x: u8 };
        \\const Handle = opaque { const size = 1; };
        \\extern fn external() void;
        \\pub inline fn inlined() void {}
        \\var Mutable = struct { a: u8 };
        \\const Alias = Plain;
        \\const Chosen = if (true) struct { a: u8 } else struct { b: u8 };
        \\const Made = Make(u8);
        \\const Failure = error{Bad};
        \\threadlocal var counter: u32 = 0;
        \\
    );
    try testing.expect(outcome.applied);

    var snapshot = try graph.publish();
    defer snapshot.deinit();

    for ([_][]const u8{ "Plain", "Packed", "Typed", "Tagged", "Handle" }) |name| {
        const container = snapshot.findDefinition("probe.zig", name).?;
        try testing.expectEqualStrings("container", container.identity.role);
        try testing.expectEqualStrings("container", container.extension.get("zig.construct").?);
    }
    try testing.expectEqualStrings("struct", snapshot.findDefinition("probe.zig", "Packed").?.extension.get("zig.container").?);
    try testing.expectEqualStrings("enum", snapshot.findDefinition("probe.zig", "Typed").?.extension.get("zig.container").?);
    try testing.expectEqualStrings("union", snapshot.findDefinition("probe.zig", "Tagged").?.extension.get("zig.container").?);
    try testing.expectEqualStrings("opaque", snapshot.findDefinition("probe.zig", "Handle").?.extension.get("zig.container").?);

    for ([_][]const u8{ "external", "inlined" }) |name| {
        const function = snapshot.findDefinition("probe.zig", name).?;
        try testing.expectEqualStrings("function", function.identity.role);
        try testing.expect(function.identity.signature == null);
    }

    // A `var`, an alias, a conditional, a call, an error set, and a plain
    // variable are not container declarations, however they evaluate.
    for ([_][]const u8{ "Mutable", "Alias", "Chosen", "Made", "Failure", "counter" }) |name| {
        try testing.expect(snapshot.findDefinition("probe.zig", name) == null);
    }
    try testing.expectEqual(@as(usize, 7), snapshot.countEntities(.{ .kind = .definition }));
    try testing.expectEqual(@as(usize, 7), snapshot.countRelationships(.{ .kind = .defines }));
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());
    try testing.expectEqual(@as(usize, 0), snapshot.countDiagnostics(.confirmed_absence));

    // Six uncovered top-level declarations of one kind, and the members of
    // the covered containers: fields and one nested declaration.
    var top_level_reported = false;
    for (snapshot.diagnostics) |diagnostic| {
        if (std.mem.indexOf(u8, diagnostic.message, "6 top-level `variable_declaration`") != null) top_level_reported = true;
    }
    try testing.expect(top_level_reported);
    try testing.expectEqual(@as(usize, 3), snapshot.countDiagnostics(.unsupported_construct));
}

fn zigCall(snapshot: *const core.Snapshot, from: []const u8, designator: []const u8) ?model.Assertion {
    const source = snapshot.findDefinition("probe.zig", from) orelse return null;
    var calls = snapshot.relationships(.{ .kind = .calls, .source = source.id, .designator = designator });
    return calls.next();
}

fn expectZigCallUnresolved(snapshot: *const core.Snapshot, from: []const u8, designator: []const u8, fragment: []const u8) !void {
    const call = zigCall(snapshot, from, designator) orelse return error.TestExpectedCall;
    try testing.expect(!call.resolution.isFact());
    try testing.expect(std.mem.indexOf(u8, call.resolution.unresolved.explanation, fragment) != null);
}

test "a bare zig call resolves only to the unit's one top-level function of that name" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const outcome = try indexZig(&analyzer, &graph,
        \\const std = @import("std");
        \\const Shape = struct { size: u8 };
        \\const alias = helper;
        \\fn helper() u8 { return 1; }
        \\fn twice() void {}
        \\fn twice() void {}
        \\fn main(param: u8) void {
        \\    _ = helper();
        \\    _ = @as(u8, helper());
        \\    std.debug.print("", .{});
        \\    _ = Shape.make();
        \\    _ = param();
        \\    _ = missing();
        \\    twice();
        \\    _ = alias();
        \\    _ = Shape();
        \\    _ = std();
        \\    const local = 1;
        \\    _ = local();
        \\    for (items) |capture| _ = capture();
        \\    const Inner = struct { fn run() void { helper(); } };
        \\    _ = Inner;
        \\}
        \\test "calls in tests are not analyzed" { _ = helper(); }
        \\comptime { _ = helper(); }
        \\
    );
    try testing.expect(outcome.applied);

    var snapshot = try graph.publish();
    defer snapshot.deinit();

    const main = snapshot.findDefinition("probe.zig", "main").?;
    const helper = snapshot.findDefinition("probe.zig", "helper").?;

    // Both bare calls to `helper`, one inside a builtin's arguments, are facts;
    // the builtin itself records nothing.
    try testing.expectEqual(@as(usize, 2), snapshot.countRelationships(.{
        .kind = .calls,
        .source = main.id,
        .target = helper.id,
        .resolution = .fact,
    }));
    var facts = snapshot.relationships(.{ .kind = .calls, .resolution = .fact });
    while (facts.next()) |fact| {
        try testing.expectEqualStrings("frontend.zig", fact.producer.name);
        try testing.expect(fact.evidence != null);
    }
    try testing.expectEqual(@as(usize, 2), snapshot.countRelationships(.{ .kind = .calls, .resolution = .fact }));

    try expectZigCallUnresolved(&snapshot, "main", "print", "not a bare name");
    try expectZigCallUnresolved(&snapshot, "main", "make", "not a top-level `@import` alias");
    try expectZigCallUnresolved(&snapshot, "main", "param", "local binding");
    try expectZigCallUnresolved(&snapshot, "main", "local", "local binding");
    try expectZigCallUnresolved(&snapshot, "main", "capture", "local binding");
    try expectZigCallUnresolved(&snapshot, "main", "missing", "no top-level declaration");
    try expectZigCallUnresolved(&snapshot, "main", "twice", "more than one");
    try expectZigCallUnresolved(&snapshot, "main", "alias", "not a covered function");
    try expectZigCallUnresolved(&snapshot, "main", "Shape", "not a covered function");
    try expectZigCallUnresolved(&snapshot, "main", "std", "not a covered function");

    // Two resolved and ten unresolved occurrences, each answered once by the
    // reference query and never as a separate reference.
    try testing.expectEqual(@as(usize, 12), snapshot.countRelationships(.{ .source = main.id, .kind = .calls }));
    try testing.expectEqual(@as(usize, 12), snapshot.countRelationships(.{ .source = main.id, .reference_query = true }));
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .kind = .references }));
    try testing.expectEqual(@as(usize, 0), snapshot.countApproximateAssertions());

    // The call inside the container in `main`'s body, and the calls in the test
    // and the comptime block, were not recorded; the container is reported.
    try testing.expectEqual(@as(usize, 12), snapshot.countRelationships(.{ .kind = .calls }));
    var reported = false;
    for (snapshot.diagnostics) |diagnostic| {
        if (std.mem.indexOf(u8, diagnostic.message, "`struct_declaration` inside a function body") != null) reported = true;
    }
    try testing.expect(reported);
}

test "usingnamespace leaves every bare zig call unresolved" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    _ = try indexZig(&analyzer, &graph,
        \\usingnamespace @import("other.zig");
        \\fn helper() void {}
        \\fn main() void { helper(); }
        \\
    );

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try expectZigCallUnresolved(&snapshot, "main", "helper", "usingnamespace");
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .kind = .calls, .resolution = .fact }));
}

test "a destructuring binding shadows a zig call of the same name" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    _ = try indexZig(&analyzer, &graph,
        \\fn first() void {}
        \\fn second() void {}
        \\fn pair() void {}
        \\fn main() void {
        \\    const first, var second = pair();
        \\    first();
        \\    second();
        \\    const F = fn (pair: u8) void;
        \\    _ = F;
        \\    pair();
        \\}
        \\
    );

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try expectZigCallUnresolved(&snapshot, "main", "first", "local binding");
    try expectZigCallUnresolved(&snapshot, "main", "second", "local binding");
    // A parameter name inside a nested function type counts as a binding too:
    // over-counting bindings can only leave calls unresolved.
    try expectZigCallUnresolved(&snapshot, "main", "pair", "local binding");
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .kind = .calls, .resolution = .fact }));
}

test "an empty zig container fails the unit's analysis rather than yielding a guess" {
    // The pinned grammar reads `struct {}` as a container field with a missing
    // name. That is a parse error, so the whole unit is reported as failed;
    // nothing here repairs the tree by assuming what was meant.
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const outcome = try indexZig(&analyzer, &graph, "const Empty = struct {};\nfn greet() void {}\n");
    try testing.expect(!outcome.applied);

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try testing.expectEqual(@as(usize, 1), snapshot.countDiagnostics(.analysis_failed));
    try testing.expectEqual(@as(usize, 0), snapshot.countEntities(.{ .kind = .definition }));
}

test "only direct member functions of a covered zig container become member definitions" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    _ = try indexZig(&analyzer, &graph,
        \\const Outer = struct {
        \\    field: u8,
        \\    pub const Inner = struct { a: u8, fn deep() void {} };
        \\    fn method() void {}
        \\    pub fn other() void {}
        \\    extern fn declared() void;
        \\    test "t" {}
        \\};
        \\fn run() void {
        \\    const Local = struct { a: u8, fn hidden() void {} };
        \\    _ = Local;
        \\}
        \\
    );

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    const outer = snapshot.findDefinition("probe.zig", "Outer").?;
    try testing.expectEqual(@as(usize, 0), outer.identity.container_path.len);
    for ([_][]const u8{ "method", "other", "declared" }) |name| {
        const member = snapshot.findDefinition("probe.zig", name).?;
        try testing.expectEqualStrings("function", member.identity.role);
        try testing.expect(member.identity.signature == null);
        try testing.expectEqual(@as(usize, 1), member.identity.container_path.len);
        try testing.expectEqualStrings("Outer", member.identity.container_path[0]);
        try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{
            .kind = .defines,
            .source = outer.id,
            .target = member.id,
            .resolution = .fact,
        }));
    }
    // The nested container, its member, a field, a test, and a container in a
    // function body are not definitions.
    for ([_][]const u8{ "Inner", "deep", "field", "Local", "hidden" }) |name| {
        try testing.expect(snapshot.findDefinition("probe.zig", name) == null);
    }
    try testing.expectEqual(@as(usize, 5), snapshot.countEntities(.{ .kind = .definition }));
    // Members are reported per kind: a field, a nested declaration, a test;
    // and the container in `run`'s body.
    try testing.expectEqual(@as(usize, 4), snapshot.countDiagnostics(.unsupported_construct));
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .kind = .calls }));
}

test "an empty zig unit reports confirmed absence" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const outcome = try indexZig(&analyzer, &graph, "// nothing but a comment\n");
    try testing.expect(outcome.applied);

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try testing.expectEqual(@as(usize, 1), snapshot.countDiagnostics(.confirmed_absence));
    try testing.expectEqual(@as(usize, 0), snapshot.countDiagnostics(.unsupported_construct));
}

test "zig source that does not parse is reported as failed analysis" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const outcome = try indexZig(&analyzer, &graph, "fn greet( void {\n");
    try testing.expect(!outcome.applied);

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try testing.expectEqual(@as(usize, 1), snapshot.countDiagnostics(.analysis_failed));
    try testing.expectEqual(@as(usize, 0), snapshot.countDiagnostics(.confirmed_absence));
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

test "a zig import path resolves lexically against the importer and never leaves the root" {
    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();
    const allocator = scratch.allocator();

    const files = [_]struct { importer: []const u8, literal: []const u8, path: []const u8 }{
        .{ .importer = "src/mcp/tools.zig", .literal = "protocol.zig", .path = "src/mcp/protocol.zig" },
        .{ .importer = "src/mcp/tools.zig", .literal = "../root.zig", .path = "src/root.zig" },
        .{ .importer = "probe.zig", .literal = "./a/../b.zig", .path = "b.zig" },
        .{ .importer = "zig/imports/session.zig", .literal = "./support/../support/util.zig", .path = "zig/imports/support/util.zig" },
        // Case is kept byte for byte, so only an exact path can ever match.
        .{ .importer = "zig/imports/session.zig", .literal = "Wire.zig", .path = "zig/imports/Wire.zig" },
    };
    for (files) |case| {
        const resolved = try zig.resolveImportPath(allocator, case.importer, case.literal);
        try testing.expectEqualStrings(case.path, resolved.file);
    }

    const rejected = [_]struct { importer: []const u8, literal: []const u8, reason: []const u8 }{
        .{ .importer = "zig/imports/session.zig", .literal = "../../../outside.zig", .reason = "escapes" },
        .{ .importer = "probe.zig", .literal = "../probe.zig", .reason = "escapes" },
        .{ .importer = "a/b.zig", .literal = "/abs.zig", .reason = "absolute" },
        .{ .importer = "a/b.zig", .literal = "x//y.zig", .reason = "empty segment" },
        .{ .importer = "a/b.zig", .literal = "x\\y.zig", .reason = "backslash" },
    };
    for (rejected) |case| {
        const resolved = try zig.resolveImportPath(allocator, case.importer, case.literal);
        try testing.expect(std.mem.indexOf(u8, resolved.rejected, case.reason) != null);
    }

    for ([_][]const u8{ "std", "builtin", "root", "", "wire.zig.bak" }) |literal| {
        try testing.expectEqual(zig.ImportPath.package, try zig.resolveImportPath(allocator, "a/b.zig", literal));
    }
}

fn dependenciesOf(graph: *const core.Graph, dependent: model.SourceUnitId, out: []model.SourceUnitId) usize {
    var count: usize = 0;
    for (graph.dependencies.declarations.items) |declaration| {
        if (declaration.dependent != dependent) continue;
        if (count < out.len) out[count] = declaration.provider;
        count += 1;
    }
    return count;
}

fn hasZigDiagnostic(snapshot: *const core.Snapshot, fragment: []const u8) bool {
    for (snapshot.diagnostics) |diagnostic| {
        if (std.mem.indexOf(u8, diagnostic.message, fragment) != null) return true;
    }
    return false;
}

test "only an exact top-level zig import declaration naming an indexed unit declares a dependency" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const wire = try graph.addSourceUnit("lib/wire.zig", .zig, "pub fn writeString() void {}\n");
    _ = try analyzer.indexUnit(&graph, wire);
    // Registered but never analyzed: the alias is still established.
    const other = try graph.addSourceUnit("lib/other.zig", .zig, "pub fn go() void {}\n");
    const main = try graph.addSourceUnit("app/main.zig", .zig,
        \\const std = @import("std");
        \\const wire = @import("../lib/wire.zig");
        \\pub const other = @import("../lib/other.zig");
        \\var mutable = @import("../lib/wire.zig");
        \\const typed: type = @import("../lib/wire.zig");
        \\const member = @import("../lib/wire.zig").Frame;
        \\const escaped = @import("..\x2flib/wire.zig");
        \\const missing = @import("../lib/missing.zig");
        \\const upper = @import("../lib/Wire.zig");
        \\const itself = @import("main.zig");
        \\const outside = @import("../../outside.zig");
        \\fn run() void {}
        \\
    );
    const outcome = try analyzer.indexUnit(&graph, main);
    try testing.expect(outcome.applied);

    var providers: [4]model.SourceUnitId = undefined;
    try testing.expectEqual(@as(usize, 2), dependenciesOf(&graph, main, &providers));
    try testing.expectEqual(wire, providers[0]);
    try testing.expectEqual(other, providers[1]);

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try testing.expect(hasZigDiagnostic(&snapshot, "`const missing = @import(\"../lib/missing.zig\")` establishes no local import alias: no indexed Zig source unit has the path `lib/missing.zig`"));
    try testing.expect(hasZigDiagnostic(&snapshot, "no indexed Zig source unit has the path `lib/Wire.zig`"));
    try testing.expect(hasZigDiagnostic(&snapshot, "`const itself = @import(\"main.zig\")` establishes no local import alias: the path names the analyzed unit itself"));
    try testing.expect(hasZigDiagnostic(&snapshot, "`const outside = @import(\"../../outside.zig\")` establishes no local import alias: the path escapes the indexed root"));
    // `std` is a package import, and the `var`, typed, member, and escaped
    // shapes are not import declarations: none of them is reported as one.
    for ([_][]const u8{ "const std =", "mutable", "typed", "member", "escaped" }) |fragment| {
        try testing.expect(!hasZigDiagnostic(&snapshot, fragment));
    }
    // An alias is analysis context, not graph content.
    try testing.expectEqual(@as(usize, 1), snapshot.countEntities(.{ .kind = .definition, .path = "app/main.zig" }));
    try testing.expectEqual(@as(usize, 0), snapshot.countRelationships(.{ .kind = .references }));
}

test "a duplicated or usingnamespace-shadowed zig import alias declares no dependency" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const wire = try graph.addSourceUnit("wire.zig", .zig, "pub fn go() void {}\n");
    _ = try analyzer.indexUnit(&graph, wire);
    const twin = try graph.addSourceUnit("twin.zig", .zig,
        \\const wire = @import("wire.zig");
        \\fn wire() void {}
        \\
    );
    _ = try analyzer.indexUnit(&graph, twin);
    const using = try graph.addSourceUnit("using.zig", .zig,
        \\usingnamespace @import("other.zig");
        \\const wire = @import("wire.zig");
        \\
    );
    _ = try analyzer.indexUnit(&graph, using);

    var providers: [2]model.SourceUnitId = undefined;
    try testing.expectEqual(@as(usize, 0), dependenciesOf(&graph, twin, &providers));
    try testing.expectEqual(@as(usize, 0), dependenciesOf(&graph, using, &providers));

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    try testing.expect(hasZigDiagnostic(&snapshot, "declares this name more than once"));
    try testing.expect(hasZigDiagnostic(&snapshot, "`usingnamespace` declaration"));
}

test "a zig unit analyzed without a graph establishes no import alias" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();

    const input: contract.FrontendInput = .{ .unit = .{
        .id = @enumFromInt(0),
        .path = "main.zig",
        .language = .zig,
        .bytes = "const wire = @import(\"wire.zig\");\nfn run() void {}\n",
    } };
    var builder = contract.BatchBuilder.init(testing.allocator, input.unit.id, zig.capabilities);
    defer builder.deinit();
    try analyzer.analyze(null, input, &builder);

    const batch = builder.batch();
    try testing.expectEqual(@as(usize, 0), batch.dependencies.len);
    var reported = false;
    for (batch.diagnostics) |diagnostic| {
        if (std.mem.indexOf(u8, diagnostic.message, "without repository context") != null) reported = true;
    }
    try testing.expect(reported);
}

test "a zig unit exports only a top-level pub fn whose name it declares once" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    _ = try indexZig(&analyzer, &graph,
        \\pub fn open() void {}
        \\fn closed() void {}
        \\pub fn twice() void {}
        \\pub const twice = 1;
        \\pub extern fn external() void;
        \\pub const Shape = struct {
        \\    size: u8,
        \\    pub fn member() void {}
        \\};
        \\
    );
    const using = try graph.addSourceUnit("using.zig", .zig,
        \\pub usingnamespace @import("other.zig");
        \\pub fn open() void {}
        \\
    );
    _ = try analyzer.indexUnit(&graph, using);

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    for ([_][]const u8{ "open", "external" }) |name| {
        try testing.expectEqualStrings("callable", snapshot.findDefinition("probe.zig", name).?.extension.get("zig.export").?);
    }
    for ([_][]const u8{ "closed", "twice", "member", "Shape" }) |name| {
        try testing.expect(snapshot.findDefinition("probe.zig", name).?.extension.get("zig.export") == null);
    }
    try testing.expect(snapshot.findDefinition("using.zig", "open").?.extension.get("zig.export") == null);
}

test "calls in a zig member body follow the same narrow rules, with the container's names in scope" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const wire = try graph.addSourceUnit("wire.zig", .zig, "pub fn send() void {}\npub fn reset() void {}\n");
    _ = try analyzer.indexUnit(&graph, wire);
    const main = try graph.addSourceUnit("probe.zig", .zig,
        \\const wire = @import("wire.zig");
        \\fn helper() void {}
        \\fn size() void {}
        \\const Server = struct {
        \\    size: u8,
        \\    const reset = 0;
        \\    fn run(self: Server) void {
        \\        helper();
        \\        size();
        \\        wire.send();
        \\        self.stop();
        \\        const local = wire;
        \\        local.send();
        \\    }
        \\    fn stop(wire: u8) void {
        \\        wire.send();
        \\    }
        \\};
        \\const Mixed = struct {
        \\    usingnamespace @import("other.zig");
        \\    fn go() void {
        \\        helper();
        \\        wire.send();
        \\    }
        \\};
        \\const Shadow = struct {
        \\    const wire = 1;
        \\    fn go() void {
        \\        wire.send();
        \\    }
        \\};
        \\
    );
    _ = try analyzer.indexUnit(&graph, main);

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    const send = snapshot.findDefinition("wire.zig", "send").?;
    const helper = snapshot.findDefinition("probe.zig", "helper").?;
    const run = snapshot.findDefinition("probe.zig", "run").?;
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{ .kind = .calls, .source = run.id, .target = helper.id, .resolution = .fact }));
    try testing.expectEqual(@as(usize, 1), snapshot.countRelationships(.{ .kind = .calls, .source = run.id, .target = send.id, .resolution = .fact }));
    try expectZigCallUnresolved(&snapshot, "run", "size", "enclosing container declares a member");
    try expectZigCallUnresolved(&snapshot, "run", "stop", "qualifier is a parameter or local binding");
    try expectZigCallUnresolved(&snapshot, "run", "send", "qualifier is a parameter or local binding");
    try expectZigCallUnresolved(&snapshot, "stop", "send", "qualifier is a parameter or local binding");

    // The two `go` members are told apart by their container.
    var goes = snapshot.entitiesMatching(.{ .kind = .definition, .path = "probe.zig", .name = "go" });
    var checked: usize = 0;
    while (goes.next()) |go| : (checked += 1) {
        const container = go.identity.container_path[0];
        var calls = snapshot.relationships(.{ .kind = .calls, .source = go.id });
        while (calls.next()) |call| {
            try testing.expect(!call.resolution.isFact());
            const fragment = if (std.mem.eql(u8, container, "Mixed")) "container has a `usingnamespace`" else "declares a member with the qualifier's name";
            try testing.expect(std.mem.indexOf(u8, call.resolution.unresolved.explanation, fragment) != null);
        }
    }
    try testing.expectEqual(@as(usize, 2), checked);
    try testing.expectEqual(@as(usize, 2), snapshot.countRelationships(.{ .kind = .calls, .resolution = .fact }));
}

// -- Plan 012: the Java member projection -------------------------------------

/// The shape of the one class named `name` in `unit`, as the graph holds it.
fn shapeOf(
    graph: *core.Graph,
    unit: model.SourceUnitId,
    name: []const u8,
    gpa: Allocator,
) !?java_members.ClassShape {
    var definitions: std.ArrayList(model.EntityId) = .empty;
    defer definitions.deinit(gpa);
    try graph.definitionsInUnit(unit, &definitions, gpa);
    for (definitions.items) |id| {
        const shape = java_members.classShapeOf(graph, id) orelse continue;
        if (std.mem.eql(u8, shape.name, name)) return shape;
    }
    return null;
}

test "a java class carries the modifiers and supertype shape a static call must check" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const unit = try addJava(&analyzer, &graph, "demo/Util.java",
        \\package demo;
        \\
        \\class Util {
        \\    public static String make() { return null; }
        \\    public static String twice() { return null; }
        \\    public static String twice(String name) { return null; }
        \\    protected static String guarded() { return null; }
        \\    static String packaged() { return null; }
        \\    private static String hidden() { return null; }
        \\    public String instance() { return null; }
        \\}
        \\
        \\class Shaped extends Absent {
        \\    public static String make() { return null; }
        \\}
        \\
    );

    const util = (try shapeOf(&graph, unit, "Util", testing.allocator)).?;
    try testing.expectEqual(java_members.Supertypes.none, util.supertypes);
    try testing.expectEqualStrings("demo", util.package);

    var methods: std.ArrayList(java_members.Method) = .empty;
    defer methods.deinit(testing.allocator);
    try java_members.methodsOf(&graph, util, testing.allocator, &methods);
    try testing.expectEqual(@as(usize, 7), methods.items.len);

    // One name, one method: the only selection a static call may act on.
    const make = java_members.select(methods.items, "make").unique;
    try testing.expectEqual(java_members.Access.public, make.access);
    try testing.expectEqual(java_members.Static.yes, make.static);

    // Overloads are reported as what they are, not resolved to the first.
    try testing.expectEqual(@as(u32, 2), java_members.select(methods.items, "twice").overloaded);
    try testing.expectEqual(java_members.Selection.missing, java_members.select(methods.items, "absent"));

    // Every access the frontend distinguishes, including the one Java gives a
    // member that names none.
    try testing.expectEqual(
        java_members.Access.protected,
        java_members.select(methods.items, "guarded").unique.access,
    );
    try testing.expectEqual(
        java_members.Access.package_private,
        java_members.select(methods.items, "packaged").unique.access,
    );
    try testing.expectEqual(
        java_members.Access.private,
        java_members.select(methods.items, "hidden").unique.access,
    );
    try testing.expectEqual(
        java_members.Static.no,
        java_members.select(methods.items, "instance").unique.static,
    );

    // A class that declares a supertype says so, because what it may inherit is
    // what a caller cannot see.
    const shaped = (try shapeOf(&graph, unit, "Shaped", testing.allocator)).?;
    try testing.expectEqual(java_members.Supertypes.declared, shaped.supertypes);
}

test "a provider whose analysis failed exposes no class shape at all" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const unit = try addJava(
        &analyzer,
        &graph,
        "demo/Util.java",
        "package demo;\n\nclass Util {\n    public static String make() { return null; }\n}\n",
    );
    try testing.expect((try shapeOf(&graph, unit, "Util", testing.allocator)) != null);

    // The unit no longer parses, so nothing it once declared is current, and a
    // call must not select against what the working copy may not contain.
    _ = try graph.setSourceUnitBytes(unit, "package demo;\n\nclass Util {\n");
    _ = try analyzer.indexUnit(&graph, unit);
    try testing.expect((try shapeOf(&graph, unit, "Util", testing.allocator)) == null);

    var aspects: std.ArrayList(java_members.Aspect) = .empty;
    defer aspects.deinit(testing.allocator);
    try java_members.aspectsOf(&graph, unit, testing.allocator, &aspects);
    try testing.expectEqual(@as(usize, 0), aspects.items.len);
}

test "one method edit changes one aspect, and leaves the class's others alone" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    const unit = try addJava(&analyzer, &graph, "demo/Util.java",
        \\package demo;
        \\
        \\class Util {
        \\    public static String make() { return null; }
        \\    public static String keep() { return null; }
        \\}
        \\
    );

    var before: std.ArrayList(java_members.Aspect) = .empty;
    defer before.deinit(testing.allocator);
    try java_members.aspectsOf(&graph, unit, testing.allocator, &before);
    // The class itself, and one aspect per method name.
    try testing.expectEqual(@as(usize, 3), before.items.len);

    _ = try graph.setSourceUnitBytes(unit,
        \\package demo;
        \\
        \\class Util {
        \\    static String make() { return null; }
        \\    public static String keep() { return null; }
        \\}
        \\
    );
    _ = try analyzer.indexUnit(&graph, unit);

    var after: std.ArrayList(java_members.Aspect) = .empty;
    defer after.deinit(testing.allocator);
    try java_members.aspectsOf(&graph, unit, testing.allocator, &after);

    var changed: usize = 0;
    for (before.items) |candidate| {
        var same = false;
        for (after.items) |other| {
            if (candidate.eql(other)) same = true;
        }
        if (!same) changed += 1;
    }
    // Only `make` moved: losing `public` is a different answer for that name
    // and the same answer for every other.
    try testing.expectEqual(@as(usize, 1), changed);
    for (after.items) |aspect| {
        if (!std.mem.eql(u8, aspect.method, "make")) continue;
        try testing.expectEqual(java_members.Access.package_private, aspect.access);
    }
}

test "a class outside the visibility boundary is never a candidate to select a member from" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    _ = try addJava(
        &analyzer,
        &graph,
        "moduleA/src/main/java/demo/Util.java",
        "package demo;\n\nclass Util {\n    public static String make() { return null; }\n}\n",
    );
    const reader = try addJava(
        &analyzer,
        &graph,
        "moduleB/src/main/java/demo/Caller.java",
        "package demo;\n\nclass Caller {\n    void run() { Util.make(); }\n}\n",
    );

    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();
    const context = try contextFor(&analyzer, &graph, reader, scratch.allocator());

    // The member projection is only ever reached through a class the type rule
    // already selected, and across source roots there is none to hand it.
    const binding = context.lookup("demo", "Util").?;
    try testing.expectEqual(@as(u32, 1), binding.out_of_scope);
}

test "reader hints remember the pair and the class, and answer for both" {
    var members = java_members.Members.init(testing.allocator);
    defer members.deinit();

    const caller: model.SourceUnitId = @enumFromInt(1);
    const other: model.SourceUnitId = @enumFromInt(2);
    try members.noteReader(caller, "Util", "make");
    try members.noteReader(other, "Util", "keep");
    // Noting the same pair twice does not make two readers of one unit.
    try members.noteReader(caller, "Util", "make");

    const make_readers = try members.readersOf("Util", "make", testing.allocator);
    try testing.expectEqual(@as(usize, 1), make_readers.len);
    try testing.expectEqual(caller, make_readers[0]);

    // A class-level change reaches every reader of any of its methods.
    const class_readers = try members.readersOf("Util", "", testing.allocator);
    try testing.expectEqual(@as(usize, 2), class_readers.len);

    // A pair nobody read has no readers, rather than falling back to the class.
    try testing.expectEqual(
        @as(usize, 0),
        (try members.readersOf("Util", "absent", testing.allocator)).len,
    );
    try testing.expectEqual(
        @as(usize, 0),
        (try members.readersOf("Absent", "make", testing.allocator)).len,
    );
}

test "the member projection resolves a receiver name in the same order resolveType does" {
    var analyzer = Analyzer.init(testing.allocator, null);
    defer analyzer.deinit();
    var graph = try core.Graph.init(testing.allocator, "fixtures");
    defer graph.deinit();

    // Two classes of one name: one in the caller's own package, one reached by
    // a single-type import. Java prefers the import, and both `resolveType` and
    // this projection must prefer it too. Their agreement is what makes the two
    // "shape not read" and "supertypes unknown" declines in the frontend
    // unreachable, so it is pinned here rather than assumed
    // ([Follow-up 016](../../docs/followups/016_java_static_call_rule_narrow_gaps.md)).
    const imported = try addJava(
        &analyzer,
        &graph,
        "module/src/main/java/lib/Util.java",
        "package lib;\nclass Util { public static String make() { return null; } }\n",
    );
    _ = try addJava(
        &analyzer,
        &graph,
        "module/src/main/java/app/Util.java",
        "package app;\nclass Util { public static String make() { return null; } }\n",
    );
    const caller = try addJava(
        &analyzer,
        &graph,
        "module/src/main/java/app/Caller.java",
        "package app;\n\nimport lib.Util;\n\nclass Caller { void call() { Util.make(); } }\n",
    );

    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();
    const context = try contextFor(&analyzer, &graph, caller, scratch.allocator());
    const members = context.memberLookup("Util").?;
    try testing.expectEqual(@as(usize, 1), members.methods.len);
    try testing.expectEqualStrings("make", members.methods[0].name);
    try testing.expectEqual(imported, members.methods[0].target.provider);

    var snapshot = try graph.publish();
    defer snapshot.deinit();
    const make = snapshot.findDefinition("module/src/main/java/lib/Util.java", "make").?;
    const call_site = snapshot.findDefinition("module/src/main/java/app/Caller.java", "call").?;
    var calls = snapshot.relationships(.{ .kind = .calls, .source = call_site.id });
    var named: ?model.EntityId = null;
    while (calls.next()) |call| {
        if (!call.resolution.isFact()) continue;
        named = call.claim.relationship.target.entity;
    }
    try testing.expectEqual(make.id, named.?);
}
