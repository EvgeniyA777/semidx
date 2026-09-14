//! MCP tools as projections over one published snapshot.
//!
//! Every tool here reads a `Snapshot` and renders what the graph recorded:
//! entity ids, source-unit ids, paths, ranges, kinds, relationships, and for
//! every claim its resolution, freshness, and producer. Nothing here resolves a
//! name, promotes an unresolved or approximate assertion, or infers a
//! relationship the graph did not record. Name and path arguments only select
//! which recorded entities to show.
//!
//! Source text is never rendered unless the server was started with the
//! evidence-text opt-in. `SourceEvidence.text` is the only source-text field a
//! snapshot carries, and `writeEvidence` is the only place that reads it; the
//! server never reads a unit's contents at all.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Stringify = std.json.Stringify;
const Writer = std.Io.Writer;
const ObjectMap = std.json.ObjectMap;

const semidx = @import("semidx");
const protocol = @import("protocol.zig");

const model = semidx.model;
const Snapshot = semidx.Snapshot;

pub const Tool = enum {
    semidx_health,
    semidx_repo_map,
    semidx_find_definitions,
    semidx_references,
    semidx_context,
    semidx_refresh,
};

pub const Definition = struct {
    tool: Tool,
    title: []const u8,
    description: []const u8,
    /// A complete JSON Schema object on one line: it is copied into a stdio
    /// message verbatim.
    input_schema: []const u8,
};

const limit_schema = "{\"type\":\"integer\",\"minimum\":1";
const freshness_schema = "\"freshness\":{\"type\":\"string\",\"enum\":[\"current\",\"stale\",\"any\"],\"default\":\"current\"," ++
    "\"description\":\"Which claims to include: those about current unit contents (default), stale ones, or both.\"}";
const resolution_schema = "\"resolution\":{\"type\":\"string\",\"enum\":[\"any\",\"fact\",\"unresolved\",\"approximate\"],\"default\":\"any\"}";
const language_schema = "\"language\":{\"type\":\"string\",\"enum\":[\"java\",\"clojure\",\"zig\"]}";

pub const definitions = [_]Definition{
    .{
        .tool = .semidx_health,
        .title = "Index health",
        .description = "Report the configured root, the published snapshot revision, source-unit and graph counts, " ++
            "per-language frontend coverage and parser availability, diagnostic counts, and the last scan outcome.",
        .input_schema = "{\"type\":\"object\",\"additionalProperties\":false}",
    },
    .{
        .tool = .semidx_repo_map,
        .title = "Repository map",
        .description = "List indexed source units with their analysis state and the top-level definitions the graph " ++
            "records in each. Bounded; results report truncation.",
        .input_schema = "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{" ++
            "\"path_prefix\":{\"type\":\"string\",\"description\":\"Root-relative, '/'-separated path prefix.\"}," ++
            language_schema ++ "," ++
            "\"limit\":" ++ limit_schema ++ ",\"maximum\":1000,\"default\":100,\"description\":\"Maximum files.\"}," ++
            "\"definitions_per_file\":" ++ limit_schema ++ ",\"maximum\":500,\"default\":50}}}",
    },
    .{
        .tool = .semidx_find_definitions,
        .title = "Find definitions",
        .description = "Find definition entities by exact name, root-relative path, language, and role, with the " ++
            "producer, resolution, and freshness of each definition's existence claim.",
        .input_schema = "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{" ++
            "\"name\":{\"type\":\"string\",\"description\":\"Exact definition name.\"}," ++
            "\"path\":{\"type\":\"string\",\"description\":\"Exact root-relative path of the source unit.\"}," ++
            language_schema ++ "," ++
            "\"role\":{\"type\":\"string\",\"description\":\"Frontend role, such as function, container, class, method, or defn.\"}," ++
            freshness_schema ++ "," ++ resolution_schema ++ "," ++
            "\"limit\":" ++ limit_schema ++ ",\"maximum\":500,\"default\":50}}}",
    },
    .{
        .tool = .semidx_references,
        .title = "References and calls",
        .description = "Return the REFERENCES and CALLS relationships recorded for a definition, identified by " ++
            "entity_id or by exact name. A call is one occurrence and is listed once. Incoming relationships target the " ++
            "definition; outgoing ones start from it and may be unresolved designators.",
        .input_schema = "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{" ++
            "\"entity_id\":{\"type\":\"integer\",\"minimum\":0}," ++
            "\"name\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"}," ++ language_schema ++ "," ++
            "\"direction\":{\"type\":\"string\",\"enum\":[\"incoming\",\"outgoing\",\"both\"],\"default\":\"incoming\"}," ++
            freshness_schema ++ "," ++ resolution_schema ++ "," ++
            "\"limit\":" ++ limit_schema ++ ",\"maximum\":1000,\"default\":100}}}",
    },
    .{
        .tool = .semidx_context,
        .title = "Graph context",
        .description = "Return a bounded graph neighborhood around an entity (entity_id), a definition name, or a " ++
            "source unit (path): the entity, its unit's analysis state, incoming and outgoing relationships of every " ++
            "kind, the unit's diagnostics, and the entity's last identity event.",
        .input_schema = "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{" ++
            "\"entity_id\":{\"type\":\"integer\",\"minimum\":0}," ++
            "\"name\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"}," ++ language_schema ++ "," ++
            freshness_schema ++ "," ++
            "\"relationship_limit\":" ++ limit_schema ++ ",\"maximum\":500,\"default\":50}}}",
    },
    .{
        .tool = .semidx_refresh,
        .title = "Refresh index",
        .description = "Rescan the configured root, reconcile the changes into the graph, and publish the next " ++
            "snapshot. Later calls observe the new snapshot; a failed refresh keeps the previous one.",
        .input_schema = "{\"type\":\"object\",\"additionalProperties\":false}",
    },
};

pub fn byName(name: []const u8) ?Tool {
    return std.meta.stringToEnum(Tool, name);
}

pub fn writeToolList(s: *Stringify) Writer.Error!void {
    try s.beginArray();
    for (definitions) |definition| {
        try s.beginObject();
        try s.objectField("name");
        try s.write(@tagName(definition.tool));
        try s.objectField("title");
        try s.write(definition.title);
        try s.objectField("description");
        try s.write(definition.description);
        try s.objectField("inputSchema");
        try s.beginWriteRaw();
        try s.writer.writeAll(definition.input_schema);
        s.endWriteRaw();
        try s.objectField("annotations");
        try s.beginObject();
        try s.objectField("readOnlyHint");
        try s.write(definition.tool != .semidx_refresh);
        if (definition.tool == .semidx_refresh) {
            // It rebuilds the server's own index and touches no file;
            // repeating it over unchanged files changes nothing.
            try s.objectField("destructiveHint");
            try s.write(false);
            try s.objectField("idempotentHint");
            try s.write(true);
        }
        try s.objectField("openWorldHint");
        try s.write(false);
        try s.endObject();
        try s.endObject();
    }
    try s.endArray();
}

// -- call context -----------------------------------------------------------

pub const Error = error{ToolFailed} || Writer.Error || Allocator.Error;

pub const max_evidence_text_bytes: usize = 400;

pub const LanguageStatus = struct {
    language: model.Language,
    extensions: []const []const u8,
    /// Null when a parser for the language could be created.
    parser_error: ?[]const u8,
    capabilities: semidx.contract.Capabilities,
};

/// What `semidx_health` reports beyond the snapshot.
pub const Status = struct {
    root: []const u8,
    languages: []const LanguageStatus,
    last_scan: semidx.Index.ScanOutcome,
};

pub const Context = struct {
    arena: Allocator,
    snapshot: *const Snapshot,
    /// Whether evidence text may be rendered.
    evidence_text: bool,
    /// Why a call failed, reported as a tool execution error.
    failure: ?[]const u8 = null,
    existence: ?std.AutoHashMapUnmanaged(model.EntityId, usize) = null,

    pub fn fail(self: *Context, comptime fmt: []const u8, args: anytype) Error {
        self.failure = try std.fmt.allocPrint(self.arena, fmt, args);
        return error.ToolFailed;
    }

    /// The latest existence assertion recorded for each entity.
    fn existenceOf(self: *Context, id: model.EntityId) Allocator.Error!?model.Assertion {
        if (self.existence == null) {
            var map: std.AutoHashMapUnmanaged(model.EntityId, usize) = .empty;
            for (self.snapshot.assertions, 0..) |assertion, i| {
                switch (assertion.claim) {
                    .entity_exists => |entity| {
                        const slot = try map.getOrPut(self.arena, entity);
                        if (!slot.found_existing or self.snapshot.assertions[slot.value_ptr.*].revision <= assertion.revision) {
                            slot.value_ptr.* = i;
                        }
                    },
                    else => {},
                }
            }
            self.existence = map;
        }
        const index = self.existence.?.get(id) orelse return null;
        return self.snapshot.assertions[index];
    }
};

const FreshnessArg = enum { current, stale, any };
const ResolutionArg = enum { any, fact, unresolved, approximate };
const DirectionArg = enum { incoming, outgoing, both };

fn freshnessFilter(arg: FreshnessArg) ?model.Freshness {
    return switch (arg) {
        .current => .current,
        .stale => .stale,
        .any => null,
    };
}

fn resolutionMatches(arg: ResolutionArg, resolution: model.Resolution) bool {
    return switch (arg) {
        .any => true,
        .fact => resolution.category() == .fact,
        .unresolved => resolution.category() == .unresolved,
        .approximate => resolution.category() == .approximate,
    };
}

const Args = struct {
    ctx: *Context,
    map: ?ObjectMap,

    fn allowOnly(self: Args, names: []const []const u8) Error!void {
        const map = self.map orelse return;
        var keys = map.iterator();
        outer: while (keys.next()) |entry| {
            for (names) |name| {
                if (std.mem.eql(u8, entry.key_ptr.*, name)) continue :outer;
            }
            return self.ctx.fail("unknown argument \"{s}\"", .{entry.key_ptr.*});
        }
    }

    fn string(self: Args, name: []const u8) Error!?[]const u8 {
        const value = (self.map orelse return null).get(name) orelse return null;
        return switch (value) {
            .string => |s| s,
            else => self.ctx.fail("argument \"{s}\" must be a string", .{name}),
        };
    }

    fn count(self: Args, name: []const u8, default: u32, maximum: u32) Error!u32 {
        const value = (self.map orelse return default).get(name) orelse return default;
        const n = switch (value) {
            .integer => |n| n,
            else => return self.ctx.fail("argument \"{s}\" must be an integer", .{name}),
        };
        if (n < 1 or n > maximum) return self.ctx.fail("argument \"{s}\" must be between 1 and {d}", .{ name, maximum });
        return @intCast(n);
    }

    fn entityId(self: Args, name: []const u8) Error!?model.EntityId {
        const value = (self.map orelse return null).get(name) orelse return null;
        const n = switch (value) {
            .integer => |n| n,
            else => return self.ctx.fail("argument \"{s}\" must be an integer", .{name}),
        };
        if (n < 0 or n > std.math.maxInt(u32)) return self.ctx.fail("argument \"{s}\" is not an entity id", .{name});
        return @enumFromInt(@as(u32, @intCast(n)));
    }

    fn choice(self: Args, comptime E: type, name: []const u8, default: E) Error!E {
        const text = try self.string(name) orelse return default;
        return std.meta.stringToEnum(E, text) orelse self.ctx.fail("argument \"{s}\" has unsupported value \"{s}\"", .{ name, text });
    }

    fn language(self: Args) Error!?model.Language {
        const text = try self.string("language") orelse return null;
        return std.meta.stringToEnum(model.Language, text) orelse self.ctx.fail("argument \"language\" has unsupported value \"{s}\"", .{text});
    }
};

/// Refuses any argument, for tools that take none.
pub fn expectNoArguments(ctx: *Context, arguments: ?ObjectMap) Error!void {
    try (Args{ .ctx = ctx, .map = arguments }).allowOnly(&.{});
}

// -- rendering --------------------------------------------------------------

/// Opens a structured result with the fields every tool result carries.
pub fn beginStructured(ctx: *Context, s: *Stringify) Error!void {
    try s.beginObject();
    try s.objectField("snapshot");
    try s.beginObject();
    try s.objectField("revision");
    try s.write(ctx.snapshot.revision);
    try s.endObject();
    // The preview publishes no semantic contract; saying so explicitly keeps a
    // client from assuming one.
    try s.objectField("semantic_contract_version");
    try s.write(null);
}

fn writeRange(s: *Stringify, range: model.SourceRange) Error!void {
    try s.beginObject();
    try s.objectField("start_line");
    try s.write(range.start_row + 1);
    try s.objectField("start_column");
    try s.write(range.start_column);
    try s.objectField("end_line");
    try s.write(range.end_row + 1);
    try s.objectField("end_column");
    try s.write(range.end_column);
    try s.objectField("start_byte");
    try s.write(range.start_byte);
    try s.objectField("end_byte");
    try s.write(range.end_byte);
    try s.endObject();
}

fn writeProducer(s: *Stringify, producer: model.Producer) Error!void {
    try s.beginObject();
    try s.objectField("name");
    try protocol.writeString(s, producer.name);
    try s.objectField("version");
    try protocol.writeString(s, producer.version);
    try s.endObject();
}

fn writeResolution(s: *Stringify, resolution: model.Resolution) Error!void {
    try s.beginObject();
    try s.objectField("category");
    try s.write(@tagName(resolution.category()));
    switch (resolution) {
        .fact => |fact| {
            try s.objectField("method");
            try protocol.writeString(s, fact.method);
        },
        .unresolved => |unresolved| {
            try s.objectField("missing");
            try s.write(@tagName(unresolved.missing));
            try s.objectField("explanation");
            try protocol.writeString(s, unresolved.explanation);
        },
        .approximate => |approximate| {
            try s.objectField("basis");
            try protocol.writeString(s, approximate.basis);
            try s.objectField("confidence");
            try s.write(approximate.confidence);
        },
    }
    try s.endObject();
}

fn writeUnitRef(ctx: *Context, s: *Stringify, id: model.SourceUnitId) Error!void {
    try s.beginObject();
    try s.objectField("id");
    try s.write(@intFromEnum(id));
    try s.objectField("path");
    if (ctx.snapshot.unit(id)) |view| try protocol.writeString(s, view.path) else try s.write(null);
    try s.endObject();
}

pub fn writeUnit(ctx: *Context, s: *Stringify, view: semidx.core.graph.SourceUnitView) Error!void {
    _ = ctx;
    try s.beginObject();
    try s.objectField("id");
    try s.write(@intFromEnum(view.id));
    try s.objectField("path");
    try protocol.writeString(s, view.path);
    try s.objectField("language");
    try s.write(@tagName(view.language));
    try s.objectField("analysis");
    try s.write(@tagName(view.analysis()));
    try s.objectField("file_entity_id");
    try s.write(@intFromEnum(view.entity));
    try s.objectField("content_revision");
    try s.write(view.content_revision);
    try s.objectField("analysis_revision");
    try s.write(view.analysis_revision);
    try s.endObject();
}

/// Where a claim was observed. The source text a producer recorded for the
/// claim is included only under the opt-in, bounded, and cut at a UTF-8
/// boundary.
fn writeEvidence(ctx: *Context, s: *Stringify, evidence: ?model.SourceEvidence) Error!void {
    const observed = evidence orelse return s.write(null);
    try s.beginObject();
    try s.objectField("unit");
    try writeUnitRef(ctx, s, observed.unit);
    try s.objectField("range");
    try writeRange(s, observed.range);
    if (ctx.evidence_text) {
        var end = @min(observed.text.len, max_evidence_text_bytes);
        while (end > 0 and end < observed.text.len and (observed.text[end] & 0xC0) == 0x80) end -= 1;
        try s.objectField("source_text");
        try s.beginObject();
        try s.objectField("text");
        try protocol.writeString(s, observed.text[0..end]);
        try s.objectField("truncated");
        try s.write(end < observed.text.len);
        try s.endObject();
    }
    try s.endObject();
}

const Detail = enum { brief, full };

fn writeEntity(ctx: *Context, s: *Stringify, entity: model.Entity, detail: Detail) Error!void {
    try s.beginObject();
    try s.objectField("id");
    try s.write(@intFromEnum(entity.id));
    try s.objectField("kind");
    try s.write(@tagName(entity.kind));
    try s.objectField("language");
    if (entity.identity.language) |language| try s.write(@tagName(language)) else try s.write(null);
    try s.objectField("role");
    try protocol.writeString(s, entity.identity.role);
    try s.objectField("name");
    if (entity.identity.name) |name| try protocol.writeString(s, name) else try s.write(null);
    try s.objectField("freshness");
    try s.write(@tagName(ctx.snapshot.entityFreshness(entity)));
    try s.objectField("evidence");
    try writeEvidence(ctx, s, entity.evidence);
    if (detail == .full) {
        try s.objectField("container_path");
        try s.beginArray();
        for (entity.identity.container_path) |segment| try protocol.writeString(s, segment);
        try s.endArray();
        try s.objectField("extension");
        try s.beginObject();
        try s.objectField("namespace");
        try protocol.writeString(s, entity.extension.namespace);
        try s.objectField("labels");
        try s.beginArray();
        for (entity.extension.labels) |label| {
            try s.beginObject();
            try s.objectField("key");
            try protocol.writeString(s, label.key);
            try s.objectField("value");
            try protocol.writeString(s, label.value);
            try s.endObject();
        }
        try s.endArray();
        try s.endObject();
        try s.objectField("existence");
        if (try ctx.existenceOf(entity.id)) |assertion| {
            try s.beginObject();
            try s.objectField("assertion_id");
            try s.write(@intFromEnum(assertion.id));
            try s.objectField("resolution");
            try writeResolution(s, assertion.resolution);
            try s.objectField("producer");
            try writeProducer(s, assertion.producer);
            try s.objectField("freshness");
            try s.write(@tagName(ctx.snapshot.assertionFreshness(assertion)));
            try s.objectField("revision");
            try s.write(assertion.revision);
            try s.endObject();
        } else try s.write(null);
        try s.objectField("created_revision");
        try s.write(entity.created_revision);
        try s.objectField("observed_revision");
        try s.write(entity.observed_revision);
    }
    try s.endObject();
}

fn writeEntityRef(ctx: *Context, s: *Stringify, id: model.EntityId) Error!void {
    if (ctx.snapshot.entityById(id)) |entity| return writeEntity(ctx, s, entity, .brief);
    // A stale relationship may name an entity that has since been withdrawn.
    try s.beginObject();
    try s.objectField("id");
    try s.write(@intFromEnum(id));
    try s.objectField("present_in_snapshot");
    try s.write(false);
    try s.endObject();
}

fn writeRelationship(ctx: *Context, s: *Stringify, assertion: model.Assertion, direction: ?[]const u8) Error!void {
    const relationship = assertion.relationship().?;
    try s.beginObject();
    try s.objectField("assertion_id");
    try s.write(@intFromEnum(assertion.id));
    if (direction) |value| {
        try s.objectField("direction");
        try s.write(value);
    }
    try s.objectField("kind");
    try s.write(@tagName(relationship.kind));
    try s.objectField("source");
    try writeEntityRef(ctx, s, relationship.source);
    try s.objectField("target");
    try s.beginObject();
    switch (relationship.target) {
        .entity => |id| {
            try s.objectField("entity");
            try writeEntityRef(ctx, s, id);
        },
        .designator => |designator| {
            try s.objectField("designator");
            try protocol.writeString(s, designator);
        },
    }
    try s.endObject();
    try s.objectField("resolution");
    try writeResolution(s, assertion.resolution);
    try s.objectField("producer");
    try writeProducer(s, assertion.producer);
    try s.objectField("freshness");
    try s.write(@tagName(ctx.snapshot.assertionFreshness(assertion)));
    try s.objectField("revision");
    try s.write(assertion.revision);
    try s.objectField("evidence");
    try writeEvidence(ctx, s, assertion.evidence);
    try s.endObject();
}

fn writeDiagnostic(ctx: *Context, s: *Stringify, diagnostic: model.Diagnostic) Error!void {
    try s.beginObject();
    try s.objectField("kind");
    try s.write(@tagName(diagnostic.kind));
    try s.objectField("unit");
    if (diagnostic.unit) |unit| try writeUnitRef(ctx, s, unit) else try s.write(null);
    try s.objectField("producer");
    try writeProducer(s, diagnostic.producer);
    try s.objectField("message");
    try protocol.writeString(s, diagnostic.message);
    try s.objectField("revision");
    try s.write(diagnostic.revision);
    try s.endObject();
}

pub fn writeDiagnosticCounts(ctx: *Context, s: *Stringify, unit: ?model.SourceUnitId) Error!void {
    var counts = std.enums.EnumArray(model.DiagnosticKind, usize).initFill(0);
    for (ctx.snapshot.diagnostics) |diagnostic| {
        if (unit) |id| {
            if (diagnostic.unit != id) continue;
        }
        counts.getPtr(diagnostic.kind).* += 1;
    }
    try s.beginObject();
    for (std.enums.values(model.DiagnosticKind)) |kind| {
        try s.objectField(@tagName(kind));
        try s.write(counts.get(kind));
    }
    try s.endObject();
}

pub fn writeUnitCounts(ctx: *Context, s: *Stringify) Error!void {
    const snapshot = ctx.snapshot;
    try s.beginObject();
    try s.objectField("total");
    try s.write(snapshot.units.len);
    for (std.enums.values(semidx.core.graph.UnitAnalysis)) |analysis| {
        try s.objectField(@tagName(analysis));
        try s.write(snapshot.countUnits(analysis));
    }
    try s.objectField("by_language");
    try s.beginObject();
    for (std.enums.values(model.Language)) |language| {
        var n: usize = 0;
        for (snapshot.units) |view| {
            if (view.language == language) n += 1;
        }
        try s.objectField(@tagName(language));
        try s.write(n);
    }
    try s.endObject();
    try s.endObject();
}

// -- tools ------------------------------------------------------------------

pub fn health(ctx: *Context, s: *Stringify, arguments: ?ObjectMap, status: Status) Error!void {
    try expectNoArguments(ctx, arguments);
    const snapshot = ctx.snapshot;

    try beginStructured(ctx, s);
    try s.objectField("server");
    try protocol.writeImplementation(s);
    try s.objectField("root");
    try protocol.writeString(s, status.root);
    try s.objectField("evidence_text");
    try s.beginObject();
    try s.objectField("enabled");
    try s.write(ctx.evidence_text);
    try s.objectField("max_bytes");
    try s.write(max_evidence_text_bytes);
    try s.endObject();
    try s.objectField("units");
    try writeUnitCounts(ctx, s);

    try s.objectField("graph");
    try s.beginObject();
    try s.objectField("entities");
    try s.beginObject();
    for (std.enums.values(model.EntityKind)) |kind| {
        try s.objectField(@tagName(kind));
        try s.write(snapshot.countEntities(.{ .kind = kind }));
    }
    try s.objectField("stale");
    try s.write(snapshot.countEntities(.{ .freshness = .stale }));
    try s.endObject();
    try s.objectField("assertions");
    try s.beginObject();
    try s.objectField("recorded");
    try s.write(snapshot.assertions.len);
    try s.objectField("current");
    try s.beginObject();
    for (std.enums.values(model.ResolutionCategory)) |category| {
        try s.objectField(@tagName(category));
        try s.write(snapshot.countAssertions(.{ .resolution = category }));
    }
    try s.endObject();
    try s.objectField("stale");
    try s.write(snapshot.countAssertions(.{ .freshness = .stale }));
    try s.endObject();
    try s.endObject();

    try s.objectField("languages");
    try s.beginArray();
    for (status.languages) |language| {
        const capabilities = language.capabilities;
        try s.beginObject();
        try s.objectField("language");
        try s.write(@tagName(language.language));
        try s.objectField("extensions");
        try s.write(language.extensions);
        try s.objectField("parser");
        try s.beginObject();
        try s.objectField("available");
        try s.write(language.parser_error == null);
        if (language.parser_error) |message| {
            try s.objectField("error");
            try protocol.writeString(s, message);
        }
        try s.endObject();
        try s.objectField("producer");
        try writeProducer(s, capabilities.producer);
        try s.objectField("entity_roles");
        try s.write(capabilities.entity_roles);
        try s.objectField("relationship_kinds");
        try s.beginArray();
        for (capabilities.relationship_kinds) |kind| try s.write(@tagName(kind));
        try s.endArray();
        try s.objectField("coverage_note");
        try s.write(capabilities.coverage_note);
        try s.endObject();
    }
    try s.endArray();

    try s.objectField("diagnostics");
    try writeDiagnosticCounts(ctx, s, null);
    try s.objectField("last_scan");
    try s.write(status.last_scan);
    try s.endObject();
}

fn lessPath(snapshot: *const Snapshot, a: usize, b: usize) bool {
    return std.mem.lessThan(u8, snapshot.units[a].path, snapshot.units[b].path);
}

pub fn repoMap(ctx: *Context, s: *Stringify, arguments: ?ObjectMap) Error!void {
    const args: Args = .{ .ctx = ctx, .map = arguments };
    try args.allowOnly(&.{ "path_prefix", "language", "limit", "definitions_per_file" });
    const prefix = try args.string("path_prefix");
    const language = try args.language();
    const limit = try args.count("limit", 100, 1000);
    const per_file = try args.count("definitions_per_file", 50, 500);
    const snapshot = ctx.snapshot;

    var order: std.ArrayList(usize) = .empty;
    for (snapshot.units, 0..) |view, i| {
        if (prefix) |p| {
            if (!std.mem.startsWith(u8, view.path, p)) continue;
        }
        if (language) |l| {
            if (view.language != l) continue;
        }
        try order.append(ctx.arena, i);
    }
    std.mem.sort(usize, order.items, snapshot, lessPath);

    try beginStructured(ctx, s);
    try s.objectField("files");
    try s.beginArray();
    for (order.items[0..@min(order.items.len, limit)]) |i| {
        const view = snapshot.units[i];
        try s.beginObject();
        try s.objectField("unit");
        try writeUnit(ctx, s, view);
        try s.objectField("diagnostics");
        try writeDiagnosticCounts(ctx, s, view.id);

        var top_level: usize = 0;
        var nested: usize = 0;
        try s.objectField("definitions");
        try s.beginArray();
        var found = snapshot.entitiesMatching(.{ .kind = .definition, .scope = .{ .unit = view.id } });
        while (found.next()) |entity| {
            if (entity.identity.container_path.len != 0) {
                nested += 1;
                continue;
            }
            top_level += 1;
            if (top_level <= per_file) try writeEntity(ctx, s, entity, .brief);
        }
        try s.endArray();
        try s.objectField("top_level_definitions_total");
        try s.write(top_level);
        try s.objectField("definitions_truncated");
        try s.write(top_level > per_file);
        try s.objectField("nested_definitions_total");
        try s.write(nested);
        try s.endObject();
    }
    try s.endArray();
    try s.objectField("files_total");
    try s.write(order.items.len);
    try s.objectField("truncated");
    try s.write(order.items.len > limit);
    try s.endObject();
}

pub fn findDefinitions(ctx: *Context, s: *Stringify, arguments: ?ObjectMap) Error!void {
    const args: Args = .{ .ctx = ctx, .map = arguments };
    try args.allowOnly(&.{ "name", "path", "language", "role", "freshness", "resolution", "limit" });
    const filter: Snapshot.EntityFilter = .{
        .kind = .definition,
        .name = try args.string("name"),
        .path = try args.string("path"),
        .role = try args.string("role"),
        .language = try args.language(),
        .freshness = freshnessFilter(try args.choice(FreshnessArg, "freshness", .current)),
    };
    const resolution = try args.choice(ResolutionArg, "resolution", .any);
    const limit = try args.count("limit", 50, 500);

    try beginStructured(ctx, s);
    try s.objectField("definitions");
    try s.beginArray();
    var total: usize = 0;
    var found = ctx.snapshot.entitiesMatching(filter);
    while (found.next()) |entity| {
        if (resolution != .any) {
            const existence = try ctx.existenceOf(entity.id) orelse continue;
            if (!resolutionMatches(resolution, existence.resolution)) continue;
        }
        total += 1;
        if (total <= limit) try writeEntity(ctx, s, entity, .full);
    }
    try s.endArray();
    try s.objectField("total");
    try s.write(total);
    try s.objectField("truncated");
    try s.write(total > limit);
    try s.endObject();
}

const max_targets: usize = 50;

/// The entities a references or context call is about.
fn selectTargets(ctx: *Context, args: Args, freshness: ?model.Freshness, allow_path_only: bool) Error![]model.Entity {
    const id = try args.entityId("entity_id");
    const name = try args.string("name");
    const path = try args.string("path");
    const language = try args.language();

    var targets: std.ArrayList(model.Entity) = .empty;
    if (id) |entity_id| {
        if (name != null or path != null or language != null) {
            return ctx.fail("give either entity_id or name/path/language, not both", .{});
        }
        const entity = ctx.snapshot.entityById(entity_id) orelse
            return ctx.fail("no entity with id {d} in snapshot revision {d}", .{ @intFromEnum(entity_id), ctx.snapshot.revision });
        try targets.append(ctx.arena, entity);
        return targets.items;
    }
    if (name == null) {
        if (allow_path_only) {
            if (path) |p| {
                const view = ctx.snapshot.unitByPath(p) orelse
                    return ctx.fail("no source unit at path \"{s}\" in snapshot revision {d}", .{ p, ctx.snapshot.revision });
                try targets.append(ctx.arena, ctx.snapshot.entityById(view.entity).?);
                return targets.items;
            }
            return ctx.fail("give entity_id, name, or path", .{});
        }
        return ctx.fail("give entity_id or name", .{});
    }
    var found = ctx.snapshot.entitiesMatching(.{
        .kind = .definition,
        .name = name,
        .path = path,
        .language = language,
        .freshness = freshness,
    });
    while (found.next()) |entity| try targets.append(ctx.arena, entity);
    return targets.items;
}

pub fn references(ctx: *Context, s: *Stringify, arguments: ?ObjectMap) Error!void {
    const args: Args = .{ .ctx = ctx, .map = arguments };
    try args.allowOnly(&.{ "entity_id", "name", "path", "language", "direction", "freshness", "resolution", "limit" });
    const direction = try args.choice(DirectionArg, "direction", .incoming);
    const freshness = freshnessFilter(try args.choice(FreshnessArg, "freshness", .current));
    const resolution = try args.choice(ResolutionArg, "resolution", .any);
    const limit = try args.count("limit", 100, 1000);
    const targets = try selectTargets(ctx, args, freshness, false);
    const shown_targets = targets[0..@min(targets.len, max_targets)];

    try beginStructured(ctx, s);
    try s.objectField("targets");
    try s.beginArray();
    for (shown_targets) |target| try writeEntity(ctx, s, target, .full);
    try s.endArray();
    try s.objectField("targets_total");
    try s.write(targets.len);
    try s.objectField("targets_truncated");
    try s.write(targets.len > max_targets);

    var seen: std.AutoHashMapUnmanaged(model.AssertionId, void) = .empty;
    var total: usize = 0;
    try s.objectField("relationships");
    try s.beginArray();
    for (shown_targets) |target| {
        const passes = [_]struct { name: []const u8, enabled: bool, filter: Snapshot.RelationshipFilter }{
            .{ .name = "incoming", .enabled = direction != .outgoing, .filter = .{ .target = target.id, .reference_query = true, .freshness = freshness } },
            .{ .name = "outgoing", .enabled = direction != .incoming, .filter = .{ .source = target.id, .reference_query = true, .freshness = freshness } },
        };
        for (passes) |pass| {
            if (!pass.enabled) continue;
            var found = ctx.snapshot.relationships(pass.filter);
            while (found.next()) |assertion| {
                if (!resolutionMatches(resolution, assertion.resolution)) continue;
                // A recursive call is incoming and outgoing at once; it is
                // still one occurrence.
                if ((try seen.getOrPut(ctx.arena, assertion.id)).found_existing) continue;
                total += 1;
                if (total <= limit) try writeRelationship(ctx, s, assertion, pass.name);
            }
        }
    }
    try s.endArray();
    try s.objectField("relationships_total");
    try s.write(total);
    try s.objectField("truncated");
    try s.write(total > limit);
    try s.endObject();
}

const max_focus: usize = 10;
const max_context_diagnostics: usize = 50;

pub fn context(ctx: *Context, s: *Stringify, arguments: ?ObjectMap) Error!void {
    const args: Args = .{ .ctx = ctx, .map = arguments };
    try args.allowOnly(&.{ "entity_id", "name", "path", "language", "freshness", "relationship_limit" });
    const freshness = freshnessFilter(try args.choice(FreshnessArg, "freshness", .current));
    const limit = try args.count("relationship_limit", 50, 500);
    const targets = try selectTargets(ctx, args, freshness, true);
    const snapshot = ctx.snapshot;

    try beginStructured(ctx, s);
    try s.objectField("focus");
    try s.beginArray();
    for (targets[0..@min(targets.len, max_focus)]) |entity| {
        try s.beginObject();
        try s.objectField("entity");
        try writeEntity(ctx, s, entity, .full);

        const unit_id: ?model.SourceUnitId = switch (entity.identity.scope) {
            .unit => |id| id,
            .repository => null,
        };
        try s.objectField("unit");
        if (unit_id) |id| {
            if (snapshot.unit(id)) |view| try writeUnit(ctx, s, view) else try s.write(null);
        } else try s.write(null);

        const passes = [_]struct { name: []const u8, filter: Snapshot.RelationshipFilter }{
            .{ .name = "incoming", .filter = .{ .target = entity.id, .freshness = freshness } },
            .{ .name = "outgoing", .filter = .{ .source = entity.id, .freshness = freshness } },
        };
        for (passes) |pass| {
            var n: usize = 0;
            try s.objectField(pass.name);
            try s.beginArray();
            var found = snapshot.relationships(pass.filter);
            while (found.next()) |assertion| {
                n += 1;
                if (n <= limit) try writeRelationship(ctx, s, assertion, null);
            }
            try s.endArray();
            try s.objectField(if (pass.name[0] == 'i') "incoming_total" else "outgoing_total");
            try s.write(n);
            try s.objectField(if (pass.name[0] == 'i') "incoming_truncated" else "outgoing_truncated");
            try s.write(n > limit);
        }

        var diagnostics: usize = 0;
        try s.objectField("diagnostics");
        try s.beginArray();
        if (unit_id) |id| {
            for (snapshot.diagnostics) |diagnostic| {
                if (diagnostic.unit != id) continue;
                diagnostics += 1;
                if (diagnostics <= max_context_diagnostics) try writeDiagnostic(ctx, s, diagnostic);
            }
        }
        try s.endArray();
        try s.objectField("diagnostics_total");
        try s.write(diagnostics);
        try s.objectField("diagnostics_truncated");
        try s.write(diagnostics > max_context_diagnostics);

        try s.objectField("last_identity_event");
        if (snapshot.lastIdentityEvent(entity.id)) |event| {
            try s.beginObject();
            try s.objectField("kind");
            try s.write(@tagName(event.kind));
            try s.objectField("replacement_entity_id");
            if (event.replacement) |replacement| try s.write(@intFromEnum(replacement)) else try s.write(null);
            try s.objectField("reason");
            try protocol.writeString(s, event.reason);
            try s.objectField("revision");
            try s.write(event.revision);
            try s.endObject();
        } else try s.write(null);
        try s.endObject();
    }
    try s.endArray();
    try s.objectField("focus_total");
    try s.write(targets.len);
    try s.objectField("focus_truncated");
    try s.write(targets.len > max_focus);
    try s.endObject();
}

test "every tool schema is one line of valid JSON naming an object" {
    for (definitions) |definition| {
        try std.testing.expect(std.mem.indexOfScalar(u8, definition.input_schema, '\n') == null);
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, definition.input_schema, .{});
        defer parsed.deinit();
        try std.testing.expectEqualStrings("object", parsed.value.object.get("type").?.string);
    }
    try std.testing.expectEqual(std.enums.values(Tool).len, definitions.len);
    for (definitions, std.enums.values(Tool)) |definition, tool| try std.testing.expectEqual(tool, definition.tool);
}
