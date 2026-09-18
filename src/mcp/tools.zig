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
    semidx_outline,
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
    /// Every argument the tool accepts. The advertised schema and the argument
    /// validator are both derived from this list.
    params: []const Param,
    /// A complete JSON Schema object on one line, generated from `params`: it
    /// is copied into a stdio message verbatim.
    input_schema: []const u8,
};

/// One tool argument, declared once. `inputSchema` renders it into the
/// advertised schema and `Args` validates against it, so the two cannot name
/// different types, enum values, defaults, or maxima.
pub const Param = struct {
    name: []const u8,
    type: ParamType,
    description: ?[]const u8 = null,
};

pub const ParamType = union(enum) {
    string,
    /// A non-negative integer naming a graph entity.
    entity_id,
    /// A positive integer bounded by `maximum`.
    count: struct { default: u32, maximum: u32 },
    /// One of an enum's tag names.
    choice: struct { values: []const []const u8, default: ?[]const u8 },
};

fn countParam(comptime name: []const u8, comptime default: u32, comptime maximum: u32, comptime description: ?[]const u8) Param {
    return .{ .name = name, .type = .{ .count = .{ .default = default, .maximum = maximum } }, .description = description };
}

fn choiceParam(comptime E: type, comptime name: []const u8, comptime default: ?E, comptime description: ?[]const u8) Param {
    const values = comptime values: {
        var list: [std.meta.fields(E).len][]const u8 = undefined;
        for (std.meta.fields(E), &list) |field, *value| value.* = field.name;
        break :values list;
    };
    return .{
        .name = name,
        .type = .{ .choice = .{ .values = &values, .default = if (default) |value| @tagName(value) else null } },
        .description = description,
    };
}

const FreshnessArg = enum { current, stale, any };
const ResolutionArg = enum { any, fact, unresolved, approximate };
const DirectionArg = enum { incoming, outgoing, both };
/// How much of each value a result renders. `full` is every recorded field.
/// `compact` renders a subset of the same fields with the same names and
/// types.
const DetailArg = enum { compact, full };

/// Arguments shared by several tools.
const shared_params = struct {
    const freshness = choiceParam(FreshnessArg, "freshness", .current, "Which claims to include: those about current unit contents (default), stale ones, or both.");
    const resolution = choiceParam(ResolutionArg, "resolution", .any, null);
    const language = choiceParam(model.Language, "language", null, null);
    const entity_id: Param = .{ .name = "entity_id", .type = .entity_id };
    const name: Param = .{ .name = "name", .type = .string };
    const path: Param = .{ .name = "path", .type = .string };
    const detail = choiceParam(DetailArg, "detail", .compact, "compact (default) renders a subset of the full fields for orientation; " ++
        "full renders every recorded field.");
    const max_response_bytes = countParam("max_response_bytes", 32_000, 2_000_000, "Stop appending whole items once the structured " ++
        "result would exceed this many bytes; the first item is always returned, and the result reports budget_exhausted.");
    const cursor: Param = .{ .name = "cursor", .type = .string, .description = "Opaque next_cursor from an earlier result of this tool; " ++
        "repeat that call's other arguments. Only limit and max_response_bytes may change between pages." };
};

/// Renders a JSON string literal at compile time.
fn jsonString(comptime text: []const u8) []const u8 {
    comptime var out: []const u8 = "\"";
    inline for (text) |c| {
        out = out ++ switch (c) {
            '"' => "\\\"",
            '\\' => "\\\\",
            0...0x1f => @compileError("control character in a tool schema string"),
            else => &[_]u8{c},
        };
    }
    return out ++ "\"";
}

fn inputSchema(comptime params: []const Param) []const u8 {
    comptime var out: []const u8 = "{\"type\":\"object\",\"additionalProperties\":false";
    if (params.len != 0) {
        out = out ++ ",\"properties\":{";
        inline for (params, 0..) |param, i| {
            if (i != 0) out = out ++ ",";
            const body: []const u8 = switch (param.type) {
                .string => "\"type\":\"string\"",
                .entity_id => "\"type\":\"integer\",\"minimum\":0",
                .count => |count| std.fmt.comptimePrint("\"type\":\"integer\",\"minimum\":1,\"maximum\":{d},\"default\":{d}", .{ count.maximum, count.default }),
                .choice => |choice| choice: {
                    comptime var values: []const u8 = "";
                    inline for (choice.values, 0..) |value, j| values = values ++ (if (j == 0) "" else ",") ++ jsonString(value);
                    break :choice "\"type\":\"string\",\"enum\":[" ++ values ++ "]" ++
                        (if (choice.default) |default| ",\"default\":" ++ jsonString(default) else "");
                },
            };
            out = out ++ jsonString(param.name) ++ ":{" ++ body ++
                (if (param.description) |description| ",\"description\":" ++ jsonString(description) else "") ++ "}";
        }
        out = out ++ "}";
    }
    return out ++ "}";
}

fn define(comptime tool: Tool, comptime title: []const u8, comptime description: []const u8, comptime params: []const Param) Definition {
    return .{ .tool = tool, .title = title, .description = description, .params = params, .input_schema = inputSchema(params) };
}

pub const definitions = [_]Definition{
    define(.semidx_health, "Index health", "Report the configured root, the published snapshot revision, source-unit and graph counts, " ++
        "per-language frontend coverage and parser availability, diagnostic counts, and the last scan outcome.", &.{}),
    define(.semidx_outline, "Repository outline", "List the directories and files directly under one directory, each with counts of " ++
        "source units by language and analysis state, diagnostics by kind, and top-level and nested definitions, without " ++
        "listing any definition. Start orientation here, then call semidx_repo_map with a path_prefix. Bounded; results report truncation.", &.{
        .{ .name = "path_prefix", .type = .string, .description = "Root-relative, '/'-separated directory; omit for the root." },
        shared_params.language,
        countParam("limit", 100, 1000, "Maximum entries."),
        shared_params.max_response_bytes,
        shared_params.cursor,
    }),
    define(.semidx_repo_map, "Repository map", "List indexed source units with their analysis state and the top-level definitions the graph " ++
        "records in each. Bounded; results report truncation.", &.{
        .{ .name = "path_prefix", .type = .string, .description = "Root-relative, '/'-separated path prefix." },
        shared_params.language,
        countParam("limit", 100, 1000, "Maximum files."),
        countParam("definitions_per_file", 50, 500, null),
        shared_params.detail,
        shared_params.max_response_bytes,
        shared_params.cursor,
    }),
    define(.semidx_find_definitions, "Find definitions", "Find definition entities by exact name, root-relative path, language, and role, with the " ++
        "producer, resolution, and freshness of each definition's existence claim.", &.{
        .{ .name = "name", .type = .string, .description = "Exact definition name." },
        .{ .name = "path", .type = .string, .description = "Exact root-relative path of the source unit." },
        shared_params.language,
        .{ .name = "role", .type = .string, .description = "Frontend role, such as function, container, class, method, or defn." },
        shared_params.freshness,
        shared_params.resolution,
        countParam("limit", 50, 500, null),
        shared_params.max_response_bytes,
        shared_params.cursor,
    }),
    define(.semidx_references, "References and calls", "Return the REFERENCES and CALLS relationships recorded for a definition, identified by " ++
        "entity_id or by exact name. A call is one occurrence and is listed once. Incoming relationships target the " ++
        "definition; outgoing ones start from it and may be unresolved designators.", &.{
        shared_params.entity_id,
        shared_params.name,
        shared_params.path,
        shared_params.language,
        choiceParam(DirectionArg, "direction", .incoming, null),
        shared_params.freshness,
        shared_params.resolution,
        countParam("limit", 100, 1000, null),
        shared_params.detail,
        shared_params.max_response_bytes,
        shared_params.cursor,
    }),
    define(.semidx_context, "Graph context", "Return a bounded graph neighborhood around an entity (entity_id), a definition name, or a " ++
        "source unit (path): the entity, its unit's analysis state, incoming and outgoing relationships of every " ++
        "kind, the unit's diagnostics, and the entity's last identity event; with depth 2 or 3, also the relationships " ++
        "of the entities those reach.", &.{
        shared_params.entity_id,
        shared_params.name,
        shared_params.path,
        shared_params.language,
        shared_params.freshness,
        choiceParam(DirectionArg, "direction", .both, "Which relationships to list and follow: into each entity, out of it, or both (default)."),
        countParam("depth", 1, 3, "Steps to follow relationships from each focus entity. 1 (default) is the focus's own relationships; " ++
            "2 and 3 add a traversal of the entities they reach, each rendered once and named by id afterwards."),
        countParam("relationship_limit", 50, 500, "Maximum incoming and, separately, outgoing relationships per focus entity, " ++
            "and per entity a traversal expands."),
        countParam("diagnostic_limit", 50, 500, "Maximum diagnostics per focus entity's unit."),
        shared_params.detail,
        shared_params.max_response_bytes,
    }),
    define(.semidx_refresh, "Refresh index", "Rescan the configured root, reconcile the changes into the graph, and publish the next " ++
        "snapshot. Later calls observe the new snapshot; a failed refresh keeps the previous one.", &.{}),
};

/// The secret a server generates per process to authenticate its cursors.
pub const CursorKey = Cursor.Key;

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
    recovery: Recovery,
};

pub const Recovery = struct {
    /// Times the index was rebuilt after a failed refresh.
    rebuilds: u32,
    /// A rebuilt index exists that the next refresh publishes.
    rebuilt_index_unpublished: bool,
    /// A failed refresh left the index untrusted and the rebuild failed too.
    needs_rebuild: bool,
};

pub const Context = struct {
    arena: Allocator,
    snapshot: *const Snapshot,
    /// Whether evidence text may be rendered.
    evidence_text: bool,
    /// Authenticates the cursors this process issues. Revision numbers start
    /// again in a new process, and a client may hand back anything, so a
    /// cursor is honored only when it verifies under this key.
    cursor_key: Cursor.Key = @splat(0),
    /// Why a call failed, reported as a tool execution error.
    failure: ?[]const u8 = null,
    existence: ?std.AutoHashMapUnmanaged(model.EntityId, usize) = null,
    /// The response budget of a list tool: whole items stop being appended
    /// once the next one would take the structured result past this many
    /// bytes. Null for a tool without one.
    max_response_bytes: ?usize = null,
    /// Items appended under the budget so far.
    admitted: usize = 0,
    /// Set when the budget refused an item. No later item is appended, so what
    /// a list returns is always a prefix of what it selected.
    budget_exhausted: bool = false,
    /// Set for a traversal: every entity rendered in full so far, so each is
    /// rendered once and named by `{id}` afterwards.
    rendered: ?std.AutoHashMapUnmanaged(model.EntityId, void) = null,
    /// Entities added to `rendered` since the current item began, undone when
    /// the budget refuses the item.
    rendered_journal: std.ArrayList(model.EntityId) = .empty,

    pub fn fail(self: *Context, comptime fmt: []const u8, args: anytype) Error {
        self.failure = try std.fmt.allocPrint(self.arena, fmt, args);
        return error.ToolFailed;
    }

    /// Renders one whole list item on its own with `render(ctx, s, args...)`
    /// and returns its JSON when appending it at `s` keeps the structured
    /// result within the budget, or null when it does not. The first item of
    /// a response is always returned, so a continuation always advances.
    fn item(self: *Context, s: *Stringify, comptime render: anytype, args: anytype) Error!?[]const u8 {
        if (self.budget_exhausted) return null;
        var scratch: Writer.Allocating = .init(self.arena);
        var inner: Stringify = .{ .writer = &scratch.writer };
        self.rendered_journal.clearRetainingCapacity();
        try @call(.auto, render, .{ self, &inner } ++ args);
        const rendered = scratch.written();
        if (self.max_response_bytes) |max| {
            // Every tool result is rendered into one allocating writer, whose
            // buffer holds everything written so far; +1 for a separator.
            if (self.admitted != 0 and s.writer.end + rendered.len + 1 > max) {
                self.budget_exhausted = true;
                if (self.rendered) |*set| {
                    for (self.rendered_journal.items) |id| _ = set.remove(id);
                }
                return null;
            }
        }
        self.admitted += 1;
        return rendered;
    }

    /// Whether `id` is rendered in full elsewhere in this traversal response,
    /// and so is named by `{id}`. Marks it rendered when it is not.
    fn renderOnce(self: *Context, id: model.EntityId) Allocator.Error!bool {
        if (self.rendered) |*set| {
            if ((try set.getOrPut(self.arena, id)).found_existing) return true;
            try self.rendered_journal.append(self.arena, id);
        }
        return false;
    }

    /// `item`, appended to the array open at `s`. Returns whether it was.
    fn append(self: *Context, s: *Stringify, comptime render: anytype, args: anytype) Error!bool {
        const rendered = try self.item(s, render, args) orelse return false;
        try writeRaw(s, rendered);
        return true;
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

/// The validated arguments of one tool. Every accessor names a parameter the
/// tool's definition declares and takes its type, default, and maximum from
/// that declaration; naming an undeclared parameter, or reading one as the
/// wrong type, is a compile error.
fn Args(comptime tool: Tool) type {
    return struct {
        const Self = @This();
        const params = definitions[@intFromEnum(tool)].params;

        ctx: *Context,
        map: ?ObjectMap,

        /// Refuses any argument the definition does not declare.
        fn init(ctx: *Context, map: ?ObjectMap) Error!Self {
            if (map) |object| {
                var keys = object.iterator();
                outer: while (keys.next()) |entry| {
                    for (params) |param| {
                        if (std.mem.eql(u8, entry.key_ptr.*, param.name)) continue :outer;
                    }
                    return ctx.fail("unknown argument \"{s}\"", .{entry.key_ptr.*});
                }
            }
            return .{ .ctx = ctx, .map = map };
        }

        fn declared(comptime name: []const u8, comptime tag: std.meta.Tag(ParamType)) Param {
            for (params) |param| {
                if (!std.mem.eql(u8, param.name, name)) continue;
                if (param.type != tag) @compileError(@tagName(tool) ++ " declares \"" ++ name ++ "\" as " ++ @tagName(param.type));
                return param;
            }
            @compileError(@tagName(tool) ++ " does not declare an argument \"" ++ name ++ "\"");
        }

        fn value(self: Self, name: []const u8) ?std.json.Value {
            return (self.map orelse return null).get(name);
        }

        /// Whether the call gave the argument at all.
        fn given(self: Self, comptime name: []const u8) bool {
            _ = comptime for (params) |param| {
                if (std.mem.eql(u8, param.name, name)) break param;
            } else @compileError(@tagName(tool) ++ " does not declare an argument \"" ++ name ++ "\"");
            return self.value(name) != null;
        }

        /// The named arguments the call did not give, for a hint.
        fn unset(self: Self, comptime names: []const []const u8) Allocator.Error![]const []const u8 {
            var out: std.ArrayList([]const u8) = .empty;
            inline for (names) |name| {
                if (!self.given(name)) try out.append(self.ctx.arena, name);
            }
            return out.items;
        }

        /// The maximum a count argument declares.
        fn maximum(comptime name: []const u8) u32 {
            return comptime declared(name, .count).type.count.maximum;
        }

        fn string(self: Self, comptime name: []const u8) Error!?[]const u8 {
            _ = comptime declared(name, .string);
            return switch (self.value(name) orelse return null) {
                .string => |s| s,
                else => self.ctx.fail("argument \"{s}\" must be a string", .{name}),
            };
        }

        fn count(self: Self, comptime name: []const u8) Error!u32 {
            const bounds = comptime declared(name, .count).type.count;
            const n = switch (self.value(name) orelse return bounds.default) {
                .integer => |n| n,
                else => return self.ctx.fail("argument \"{s}\" must be an integer", .{name}),
            };
            if (n < 1 or n > bounds.maximum) return self.ctx.fail("argument \"{s}\" must be between 1 and {d}", .{ name, bounds.maximum });
            return @intCast(n);
        }

        fn entityId(self: Self, comptime name: []const u8) Error!?model.EntityId {
            _ = comptime declared(name, .entity_id);
            const n = switch (self.value(name) orelse return null) {
                .integer => |n| n,
                else => return self.ctx.fail("argument \"{s}\" must be an integer", .{name}),
            };
            if (n < 0 or n > std.math.maxInt(u32)) return self.ctx.fail("argument \"{s}\" is not an entity id", .{name});
            return @enumFromInt(@as(u32, @intCast(n)));
        }

        /// A choice read as `E`, whose tag names must be the declared values.
        /// Null only when the parameter declares no default and is absent.
        fn choice(self: Self, comptime E: type, comptime name: []const u8) Error!(if (declared(name, .choice).type.choice.default == null) ?E else E) {
            const declaration = comptime declared(name, .choice).type.choice;
            comptime {
                const tags = std.meta.fieldNames(E);
                if (tags.len != declaration.values.len) @compileError("\"" ++ name ++ "\" is not declared with the values of " ++ @typeName(E));
                for (tags, declaration.values) |tag, declared_value| {
                    if (!std.mem.eql(u8, tag, declared_value)) @compileError("\"" ++ name ++ "\" is not declared with the values of " ++ @typeName(E));
                }
            }
            const default: ?E = comptime if (declaration.default) |text| std.meta.stringToEnum(E, text).? else null;
            const text = switch (self.value(name) orelse return if (default) |d| d else null) {
                .string => |s| s,
                else => return self.ctx.fail("argument \"{s}\" must be a string", .{name}),
            };
            return std.meta.stringToEnum(E, text) orelse self.ctx.fail("argument \"{s}\" has unsupported value \"{s}\"", .{ name, text });
        }
    };
}

/// Refuses any argument, for tools that take none.
pub fn expectNoArguments(ctx: *Context, arguments: ?ObjectMap) Error!void {
    _ = try Args(.semidx_refresh).init(ctx, arguments);
}

// -- narrowing hints --------------------------------------------------------

const HintAction = enum {
    /// Give one of these arguments to select fewer items.
    narrow,
    /// Give a larger value for one of these arguments.
    raise,
    /// Give a smaller value for one of these arguments.
    lower,
    /// Repeat the call with the returned cursor.
    @"continue",
};

/// Usage guidance for a bounded result: which declared arguments of the same
/// tool narrow, enlarge, or continue a list that was cut. A hint is derived
/// only from which list was cut and which arguments the call gave. It is not
/// a graph claim: it says nothing about the omitted items, and it never
/// changes what a query selects.
const Hints = struct {
    items: std.ArrayList(Hint) = .empty,

    const Hint = struct { list: []const u8, action: HintAction, arguments: []const []const u8 };

    /// Adds a hint once per list and action; a hint naming no argument is
    /// dropped.
    fn add(self: *Hints, arena: Allocator, list: []const u8, action: HintAction, arguments: []const []const u8) Allocator.Error!void {
        if (arguments.len == 0) return;
        for (self.items.items) |hint| {
            if (hint.action == action and std.mem.eql(u8, hint.list, list)) return;
        }
        try self.items.append(arena, .{ .list = list, .action = action, .arguments = arguments });
    }

    /// Writes `narrowing_hints` only when a list was cut, so a complete result
    /// carries none.
    fn write(self: Hints, s: *Stringify) Error!void {
        if (self.items.items.len == 0) return;
        try s.objectField("narrowing_hints");
        try s.beginArray();
        for (self.items.items) |hint| {
            try s.beginObject();
            try s.objectField("list");
            try s.write(hint.list);
            try s.objectField("action");
            try s.write(@tagName(hint.action));
            try s.objectField("arguments");
            try s.write(hint.arguments);
            try s.endObject();
        }
        try s.endArray();
    }
};

// -- cursors ----------------------------------------------------------------

/// A continuation of one tool call over one snapshot. It carries the tool, the
/// snapshot revision, the call's canonical arguments, and the position of the
/// next item in the call's deterministic order.
///
/// The encoding is opaque to clients and authenticated: every cursor carries a
/// tag over all of those fields, keyed by a secret this process generates at
/// startup. A cursor whose tag does not verify — altered, truncated, or issued
/// by another process, whose revision numbers start again — is refused rather
/// than honored, so a page is never a continuation of something the server did
/// not issue. The verified fields must still match the call the cursor arrives
/// with, and the arguments are compared byte for byte, so no two argument sets
/// can be taken for each other.
///
/// The body is `tool` (1 byte), `revision` and `position` (8 bytes each,
/// little-endian), the canonical arguments' length (4 bytes), and those
/// arguments; the tag follows it, and the whole is URL-safe base64 after the
/// prefix.
const Cursor = struct {
    tool: Tool,
    revision: u64,
    position: usize,
    /// `canonicalArguments` of the call that issued it.
    arguments: []const u8,

    const prefix = "sdx2.";
    const Base64 = std.base64.url_safe_no_pad;
    const Mac = std.crypto.auth.siphash.SipHash128(1, 3);
    pub const Key = [Mac.key_length]u8;
    const header_bytes = 1 + 8 + 8 + 4;
    /// Refuses an oversized string before decoding it. A cursor holds the
    /// arguments of the call that issued it, so it grows with their length.
    const max_text_bytes = 8192;

    fn encode(self: Cursor, arena: Allocator, key: *const Key) Allocator.Error![]const u8 {
        const signed = try arena.alloc(u8, header_bytes + self.arguments.len + Mac.mac_length);
        signed[0] = @intFromEnum(self.tool);
        std.mem.writeInt(u64, signed[1..9], self.revision, .little);
        std.mem.writeInt(u64, signed[9..17], self.position, .little);
        std.mem.writeInt(u32, signed[17..21], @intCast(self.arguments.len), .little);
        @memcpy(signed[header_bytes..][0..self.arguments.len], self.arguments);
        const body = signed[0 .. header_bytes + self.arguments.len];
        Mac.create(signed[body.len..][0..Mac.mac_length], body, key);
        const out = try arena.alloc(u8, prefix.len + Base64.Encoder.calcSize(signed.len));
        @memcpy(out[0..prefix.len], prefix);
        _ = Base64.Encoder.encode(out[prefix.len..], signed);
        return out;
    }

    /// Null for anything this process did not issue, including a cursor whose
    /// fields were changed after it was issued.
    fn decode(arena: Allocator, text: []const u8, key: *const Key) Allocator.Error!?Cursor {
        if (!std.mem.startsWith(u8, text, prefix) or text.len > max_text_bytes) return null;
        const encoded = text[prefix.len..];
        const size = Base64.Decoder.calcSizeForSlice(encoded) catch return null;
        if (size < header_bytes + Mac.mac_length) return null;
        const signed = try arena.alloc(u8, size);
        Base64.Decoder.decode(signed, encoded) catch return null;
        const body = signed[0 .. size - Mac.mac_length];
        var expected: [Mac.mac_length]u8 = undefined;
        Mac.create(&expected, body, key);
        if (!std.crypto.timing_safe.eql([Mac.mac_length]u8, expected, signed[body.len..][0..Mac.mac_length].*)) return null;
        if (body[0] >= std.enums.values(Tool).len) return null;
        const arguments_len = std.mem.readInt(u32, body[17..21], .little);
        if (body.len - header_bytes != arguments_len) return null;
        return .{
            .tool = @enumFromInt(body[0]),
            .revision = std.mem.readInt(u64, body[1..9], .little),
            .position = std.math.cast(usize, std.mem.readInt(u64, body[9..17], .little)) orelse return null,
            .arguments = body[header_bytes..],
        };
    }
};

/// Every argument a tool declares, in declaration order, with its default
/// applied when the call omits it, except those a caller may change between
/// pages (`cursor`, `limit`, `max_response_bytes`).
///
/// Each value is written with its type and, for a string, its length, so no
/// two argument sets encode the same bytes: an absent argument, an empty
/// string, and a string whose text continues into the next argument's are all
/// distinct. A cursor carries these bytes and they are compared byte for byte,
/// so page continuation never depends on a hash.
fn canonicalArguments(comptime tool: Tool, map: ?ObjectMap, arena: Allocator) Allocator.Error![]const u8 {
    const kind = struct {
        const absent: u8 = 0;
        const string: u8 = 1;
        const integer: u8 = 2;
        /// A JSON type argument validation refuses. Unreachable through a tool
        /// call, which validates every argument before reading a cursor.
        const invalid: u8 = 0xff;

        fn writeString(out: *std.ArrayList(u8), a: Allocator, text: []const u8) Allocator.Error!void {
            try out.append(a, string);
            var length: [4]u8 = undefined;
            std.mem.writeInt(u32, &length, @intCast(text.len), .little);
            try out.appendSlice(a, &length);
            try out.appendSlice(a, text);
        }

        fn writeInteger(out: *std.ArrayList(u8), a: Allocator, value: i64) Allocator.Error!void {
            try out.append(a, integer);
            var bytes: [8]u8 = undefined;
            std.mem.writeInt(i64, &bytes, value, .little);
            try out.appendSlice(a, &bytes);
        }
    };

    var out: std.ArrayList(u8) = .empty;
    inline for (definitions[@intFromEnum(tool)].params) |param| {
        const paged = comptime std.mem.eql(u8, param.name, "cursor") or std.mem.eql(u8, param.name, "limit") or
            std.mem.eql(u8, param.name, "max_response_bytes");
        if (!paged) {
            const given: ?std.json.Value = if (map) |object| object.get(param.name) else null;
            if (given) |value| switch (value) {
                .string => |text| try kind.writeString(&out, arena, text),
                .integer => |n| try kind.writeInteger(&out, arena, n),
                else => try out.append(arena, kind.invalid),
            } else switch (param.type) {
                .count => |count| try kind.writeInteger(&out, arena, count.default),
                .choice => |choice| if (choice.default) |default|
                    try kind.writeString(&out, arena, default)
                else
                    try out.append(arena, kind.absent),
                .string, .entity_id => try out.append(arena, kind.absent),
            }
        }
    }
    return out.items;
}

/// The position a paged call starts at: 0 without a cursor, otherwise the
/// position of a cursor this tool issued over the published snapshot for the
/// same canonical arguments. Every mismatch is a tool error naming it.
fn cursorPosition(ctx: *Context, comptime tool: Tool, args: Args(tool)) Error!usize {
    const text = try args.string("cursor") orelse return 0;
    const cursor = try Cursor.decode(ctx.arena, text, &ctx.cursor_key) orelse
        return ctx.fail("cursor is not one this server process issued, or it was changed after it was issued; " ++
            "repeat the call without cursor", .{});
    if (cursor.tool != tool) {
        return ctx.fail("cursor was issued by {t}, not {t}; pass it to {t}", .{ cursor.tool, tool, cursor.tool });
    }
    if (cursor.revision != ctx.snapshot.revision) {
        return ctx.fail("cursor was issued at snapshot revision {d}, but revision {d} is published; repeat the call without cursor " ++
            "to start over on the new snapshot", .{ cursor.revision, ctx.snapshot.revision });
    }
    if (!std.mem.eql(u8, cursor.arguments, try canonicalArguments(tool, args.map, ctx.arena))) {
        return ctx.fail("cursor was issued for different arguments; repeat the call that returned it, changing only cursor, limit, " ++
            "or max_response_bytes", .{});
    }
    return cursor.position;
}

/// Refuses a position past the end, which only an altered cursor can name.
fn checkPosition(ctx: *Context, position: usize, total: usize) Error!void {
    if (position > total) return ctx.fail("cursor position {d} is past the {d} items this call selects", .{ position, total });
}

/// `offset`, and `next_cursor` when items remain after this page, with a
/// `continue` hint for `list`.
fn writePage(ctx: *Context, s: *Stringify, comptime tool: Tool, args: Args(tool), hints: *Hints, list: []const u8, position: usize, returned: usize, total: usize) Error!void {
    try s.objectField("offset");
    try s.write(position);
    const next = position + returned;
    if (next >= total) return;
    const cursor: Cursor = .{
        .tool = tool,
        .revision = ctx.snapshot.revision,
        .position = next,
        .arguments = try canonicalArguments(tool, args.map, ctx.arena),
    };
    try s.objectField("next_cursor");
    try s.write(try cursor.encode(ctx.arena, &ctx.cursor_key));
    try hints.add(ctx.arena, list, .@"continue", &.{"cursor"});
}

/// Writes JSON already rendered by `Context.item` as the next value at `s`.
fn writeRaw(s: *Stringify, rendered: []const u8) Error!void {
    try s.beginWriteRaw();
    try s.writer.writeAll(rendered);
    s.endWriteRaw();
}

/// `budget_exhausted`, and when it is true, `omitted_by_budget`: how many
/// items each list selected within its own limit but did not return.
fn writeBudgetOutcome(ctx: *Context, s: *Stringify, omitted: anytype) Error!void {
    try s.objectField("budget_exhausted");
    try s.write(ctx.budget_exhausted);
    if (ctx.budget_exhausted) {
        try s.objectField("omitted_by_budget");
        try s.write(omitted);
    }
}

/// `name` alone when the call's value for it is below its declared maximum.
fn raisable(comptime tool: Tool, comptime name: []const u8, current: u32) []const []const u8 {
    return if (current < Args(tool).maximum(name)) &.{name} else &.{};
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

/// Lines are 1-based; columns and bytes, rendered only in full, are 0-based.
fn writeRange(s: *Stringify, range: model.SourceRange, detail: DetailArg) Error!void {
    try s.beginObject();
    try s.objectField("start_line");
    try s.write(range.start_row + 1);
    if (detail == .full) {
        try s.objectField("start_column");
        try s.write(range.start_column);
    }
    try s.objectField("end_line");
    try s.write(range.end_row + 1);
    if (detail == .full) {
        try s.objectField("end_column");
        try s.write(range.end_column);
        try s.objectField("start_byte");
        try s.write(range.start_byte);
        try s.objectField("end_byte");
        try s.write(range.end_byte);
    }
    try s.endObject();
}

fn writeProducer(s: *Stringify, producer: model.Producer, detail: DetailArg) Error!void {
    try s.beginObject();
    try s.objectField("name");
    try protocol.writeString(s, producer.name);
    if (detail == .full) {
        try s.objectField("version");
        try protocol.writeString(s, producer.version);
    }
    try s.endObject();
}

/// The category always; compact keeps what is missing from an unresolved
/// claim and an approximate claim's confidence, and drops the prose.
fn writeResolution(s: *Stringify, resolution: model.Resolution, detail: DetailArg) Error!void {
    try s.beginObject();
    try s.objectField("category");
    try s.write(@tagName(resolution.category()));
    switch (resolution) {
        .fact => |fact| {
            if (detail == .full) {
                try s.objectField("method");
                try protocol.writeString(s, fact.method);
            }
        },
        .unresolved => |unresolved| {
            try s.objectField("missing");
            try s.write(@tagName(unresolved.missing));
            if (detail == .full) {
                try s.objectField("explanation");
                try protocol.writeString(s, unresolved.explanation);
            }
        },
        .approximate => |approximate| {
            if (detail == .full) {
                try s.objectField("basis");
                try protocol.writeString(s, approximate.basis);
            }
            try s.objectField("confidence");
            try s.write(approximate.confidence);
        },
    }
    try s.endObject();
}

fn writeUnitRef(ctx: *Context, s: *Stringify, id: model.SourceUnitId, detail: DetailArg) Error!void {
    try s.beginObject();
    if (detail == .full) {
        try s.objectField("id");
        try s.write(@intFromEnum(id));
    }
    try s.objectField("path");
    if (ctx.snapshot.unit(id)) |view| try protocol.writeString(s, view.path) else try s.write(null);
    try s.endObject();
}

pub fn writeUnit(ctx: *Context, s: *Stringify, view: semidx.core.graph.SourceUnitView, detail: DetailArg) Error!void {
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
    if (detail == .compact) return s.endObject();
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
fn writeEvidence(ctx: *Context, s: *Stringify, evidence: ?model.SourceEvidence, detail: DetailArg) Error!void {
    const observed = evidence orelse return s.write(null);
    try s.beginObject();
    try s.objectField("unit");
    try writeUnitRef(ctx, s, observed.unit, detail);
    try s.objectField("range");
    try writeRange(s, observed.range, detail);
    try writeSourceText(ctx, s, observed);
    try s.endObject();
}

fn writeSourceText(ctx: *Context, s: *Stringify, observed: model.SourceEvidence) Error!void {
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
}

const EntityShape = enum {
    /// Id, role, name, freshness, and `range` lines in place of `evidence`:
    /// a definition listed under its unit, which gives its kind, language,
    /// and evidence unit. Recorded evidence text stays under the opt-in.
    listed,
    /// The id alone: the entity is already in view, as the focus end of a
    /// compact context relationship.
    id,
    /// Id, kind, role, name, freshness, and evidence path and lines.
    compact,
    /// `compact` plus container path and the existence claim's category,
    /// producer name, and freshness: a compact context focus.
    focus,
    brief,
    full,
};

fn writeEntity(ctx: *Context, s: *Stringify, entity: model.Entity, shape: EntityShape) Error!void {
    try s.beginObject();
    try s.objectField("id");
    try s.write(@intFromEnum(entity.id));
    if (shape == .id) return s.endObject();
    if (shape != .listed) {
        try s.objectField("kind");
        try s.write(@tagName(entity.kind));
    }
    if (shape == .focus or shape == .brief or shape == .full) {
        try s.objectField("language");
        if (entity.identity.language) |language| try s.write(@tagName(language)) else try s.write(null);
    }
    try s.objectField("role");
    try protocol.writeString(s, entity.identity.role);
    try s.objectField("name");
    if (entity.identity.name) |name| try protocol.writeString(s, name) else try s.write(null);
    try s.objectField("freshness");
    try s.write(@tagName(ctx.snapshot.entityFreshness(entity)));
    if (shape == .listed) {
        if (entity.evidence) |observed| {
            try s.objectField("range");
            try writeRange(s, observed.range, .compact);
            try writeSourceText(ctx, s, observed);
        }
        return s.endObject();
    }
    const detail: DetailArg = if (shape == .compact or shape == .focus) .compact else .full;
    try s.objectField("evidence");
    try writeEvidence(ctx, s, entity.evidence, detail);
    if (shape == .focus or shape == .full) {
        try s.objectField("container_path");
        try s.beginArray();
        for (entity.identity.container_path) |segment| try protocol.writeString(s, segment);
        try s.endArray();
        try s.objectField("existence");
        if (try ctx.existenceOf(entity.id)) |assertion| {
            try s.beginObject();
            if (detail == .full) {
                try s.objectField("assertion_id");
                try s.write(@intFromEnum(assertion.id));
            }
            try s.objectField("resolution");
            try writeResolution(s, assertion.resolution, detail);
            try s.objectField("producer");
            try writeProducer(s, assertion.producer, detail);
            try s.objectField("freshness");
            try s.write(@tagName(ctx.snapshot.assertionFreshness(assertion)));
            if (detail == .full) {
                try s.objectField("revision");
                try s.write(assertion.revision);
            }
            try s.endObject();
        } else try s.write(null);
    }
    if (shape == .full) {
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
        try s.objectField("created_revision");
        try s.write(entity.created_revision);
        try s.objectField("observed_revision");
        try s.write(entity.observed_revision);
    }
    try s.endObject();
}

fn writeEntityRef(ctx: *Context, s: *Stringify, id: model.EntityId, shape: EntityShape) Error!void {
    if (ctx.snapshot.entityById(id)) |entity| return writeEntity(ctx, s, entity, shape);
    // A stale relationship may name an entity that has since been withdrawn.
    try s.beginObject();
    try s.objectField("id");
    try s.write(@intFromEnum(id));
    try s.objectField("present_in_snapshot");
    try s.write(false);
    try s.endObject();
}

/// Where a traversal found a relationship: the step it was found at and the
/// entity whose relationships were being expanded.
const Step = struct { distance: u32, from: model.EntityId };

/// A compact relationship renders an end already in view (a context focus or
/// a references target) as its id alone and the other end as a compact
/// entity. In a traversal every end is rendered in full once in the response
/// and named by id afterwards. Every detail level keeps the claim's resolution
/// category, producer name, and freshness.
fn writeRelationship(ctx: *Context, s: *Stringify, assertion: model.Assertion, direction: ?[]const u8, detail: DetailArg, in_view: []const model.EntityId, step: ?Step) Error!void {
    const relationship = assertion.relationship().?;
    const end = struct {
        fn write(c: *Context, w: *Stringify, d: DetailArg, view: []const model.EntityId, id: model.EntityId) Error!void {
            const shape: EntityShape = if (c.rendered != null)
                (if (try c.renderOnce(id)) .id else if (d == .full) .brief else .compact)
            else if (d == .full)
                .brief
            else if (std.mem.indexOfScalar(model.EntityId, view, id) != null) .id else .compact;
            try writeEntityRef(c, w, id, shape);
        }
    };
    try s.beginObject();
    try s.objectField("assertion_id");
    try s.write(@intFromEnum(assertion.id));
    if (direction) |value| {
        try s.objectField("direction");
        try s.write(value);
    }
    if (step) |found| {
        try s.objectField("distance");
        try s.write(found.distance);
        try s.objectField("from");
        try s.write(@intFromEnum(found.from));
    }
    try s.objectField("kind");
    try s.write(@tagName(relationship.kind));
    try s.objectField("source");
    try end.write(ctx, s, detail, in_view, relationship.source);
    try s.objectField("target");
    try s.beginObject();
    switch (relationship.target) {
        .entity => |id| {
            try s.objectField("entity");
            try end.write(ctx, s, detail, in_view, id);
        },
        .designator => |designator| {
            try s.objectField("designator");
            try protocol.writeString(s, designator);
        },
    }
    try s.endObject();
    try s.objectField("resolution");
    try writeResolution(s, assertion.resolution, detail);
    try s.objectField("producer");
    try writeProducer(s, assertion.producer, detail);
    try s.objectField("freshness");
    try s.write(@tagName(ctx.snapshot.assertionFreshness(assertion)));
    if (detail == .full) {
        try s.objectField("revision");
        try s.write(assertion.revision);
    }
    try s.objectField("evidence");
    try writeEvidence(ctx, s, assertion.evidence, detail);
    try s.endObject();
}

/// Compact drops the unit, which the context focus already names, and the
/// revision.
fn writeDiagnostic(ctx: *Context, s: *Stringify, diagnostic: model.Diagnostic, detail: DetailArg) Error!void {
    try s.beginObject();
    try s.objectField("kind");
    try s.write(@tagName(diagnostic.kind));
    if (detail == .full) {
        try s.objectField("unit");
        if (diagnostic.unit) |unit| try writeUnitRef(ctx, s, unit, .full) else try s.write(null);
    }
    try s.objectField("producer");
    try writeProducer(s, diagnostic.producer, detail);
    try s.objectField("message");
    try protocol.writeString(s, diagnostic.message);
    if (detail == .full) {
        try s.objectField("revision");
        try s.write(diagnostic.revision);
    }
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
    _ = try Args(.semidx_health).init(ctx, arguments);
    const snapshot = ctx.snapshot;

    try beginStructured(ctx, s);
    try s.objectField("product_version");
    try s.write(protocol.product_version);
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
        try writeProducer(s, capabilities.producer, .full);
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
    try s.objectField("recovery");
    try s.write(status.recovery);
    try s.endObject();
}

fn lessPath(snapshot: *const Snapshot, a: usize, b: usize) bool {
    return std.mem.lessThan(u8, snapshot.units[a].path, snapshot.units[b].path);
}

/// Counts of source units and what the graph records in them, summed over the
/// units under one outline entry. Definitions are current definitions, split
/// as the repository map splits them.
const OutlineCounts = struct {
    units: usize = 0,
    languages: std.enums.EnumArray(model.Language, usize) = .initFill(0),
    analysis: std.enums.EnumArray(semidx.core.graph.UnitAnalysis, usize) = .initFill(0),
    diagnostics: std.enums.EnumArray(model.DiagnosticKind, usize) = .initFill(0),
    top_level_definitions: usize = 0,
    nested_definitions: usize = 0,

    fn add(self: *OutlineCounts, view: semidx.core.graph.SourceUnitView, unit: OutlineCounts) void {
        self.units += 1;
        self.languages.getPtr(view.language).* += 1;
        self.analysis.getPtr(view.analysis()).* += 1;
        for (std.enums.values(model.DiagnosticKind)) |kind| self.diagnostics.getPtr(kind).* += unit.diagnostics.get(kind);
        self.top_level_definitions += unit.top_level_definitions;
        self.nested_definitions += unit.nested_definitions;
    }

    /// A file entry leaves out what its unit already says.
    fn write(self: OutlineCounts, s: *Stringify, per_unit: bool) Error!void {
        try s.beginObject();
        if (per_unit) {
            try s.objectField("units");
            try s.write(self.units);
            inline for (.{ .{ "languages", &self.languages }, .{ "analysis", &self.analysis } }) |field| {
                try s.objectField(field[0]);
                try s.beginObject();
                for (std.enums.values(@TypeOf(field[1].*).Key)) |key| {
                    try s.objectField(@tagName(key));
                    try s.write(field[1].get(key));
                }
                try s.endObject();
            }
        }
        try s.objectField("diagnostics");
        try s.beginObject();
        for (std.enums.values(model.DiagnosticKind)) |kind| {
            try s.objectField(@tagName(kind));
            try s.write(self.diagnostics.get(kind));
        }
        try s.endObject();
        try s.objectField("top_level_definitions");
        try s.write(self.top_level_definitions);
        try s.objectField("nested_definitions");
        try s.write(self.nested_definitions);
        try s.endObject();
    }
};

/// Diagnostic and current definition counts of every unit, in one pass over
/// the snapshot each.
fn unitCounts(ctx: *Context) Allocator.Error!std.AutoHashMapUnmanaged(model.SourceUnitId, OutlineCounts) {
    var counts: std.AutoHashMapUnmanaged(model.SourceUnitId, OutlineCounts) = .empty;
    for (ctx.snapshot.units) |view| try counts.put(ctx.arena, view.id, .{});
    for (ctx.snapshot.diagnostics) |diagnostic| {
        const unit = counts.getPtr(diagnostic.unit orelse continue) orelse continue;
        unit.diagnostics.getPtr(diagnostic.kind).* += 1;
    }
    var found = ctx.snapshot.entitiesMatching(.{ .kind = .definition });
    while (found.next()) |entity| {
        const id = switch (entity.identity.scope) {
            .unit => |id| id,
            .repository => continue,
        };
        const unit = counts.getPtr(id) orelse continue;
        if (entity.identity.container_path.len == 0) unit.top_level_definitions += 1 else unit.nested_definitions += 1;
    }
    return counts;
}

const OutlineEntry = struct {
    name: []const u8,
    /// The file's unit; null for a directory.
    unit: ?semidx.core.graph.SourceUnitView,
    counts: OutlineCounts = .{},

    fn less(_: void, a: OutlineEntry, b: OutlineEntry) bool {
        return std.mem.lessThan(u8, a.name, b.name);
    }
};

pub fn outline(ctx: *Context, s: *Stringify, arguments: ?ObjectMap) Error!void {
    const args = try Args(.semidx_outline).init(ctx, arguments);
    const prefix = std.mem.trimEnd(u8, try args.string("path_prefix") orelse "", "/");
    const language = try args.choice(model.Language, "language");
    const limit = try args.count("limit");
    const max_bytes = try args.count("max_response_bytes");
    ctx.max_response_bytes = max_bytes;
    const directory = if (prefix.len == 0) "" else try std.mem.concat(ctx.arena, u8, &.{ prefix, "/" });

    const counts = try unitCounts(ctx);
    var totals: OutlineCounts = .{};
    var entries: std.ArrayList(OutlineEntry) = .empty;
    var by_name: std.StringHashMapUnmanaged(usize) = .empty;
    for (ctx.snapshot.units) |view| {
        if (!std.mem.startsWith(u8, view.path, directory)) continue;
        if (language) |l| {
            if (view.language != l) continue;
        }
        const unit = counts.get(view.id).?;
        totals.add(view, unit);
        const rest = view.path[directory.len..];
        if (std.mem.indexOfScalar(u8, rest, '/')) |slash| {
            const slot = try by_name.getOrPut(ctx.arena, rest[0..slash]);
            if (!slot.found_existing) {
                slot.value_ptr.* = entries.items.len;
                try entries.append(ctx.arena, .{ .name = rest[0..slash], .unit = null });
            }
            entries.items[slot.value_ptr.*].counts.add(view, unit);
        } else {
            var entry: OutlineEntry = .{ .name = rest, .unit = view };
            entry.counts.add(view, unit);
            try entries.append(ctx.arena, entry);
        }
    }
    std.mem.sort(OutlineEntry, entries.items, {}, OutlineEntry.less);
    const position = try cursorPosition(ctx, .semidx_outline, args);
    try checkPosition(ctx, position, entries.items.len);

    try beginStructured(ctx, s);
    try s.objectField("path_prefix");
    try protocol.writeString(s, directory);
    try s.objectField("entries");
    try s.beginArray();
    const page = entries.items[position..@min(entries.items.len, position + limit)];
    var returned: usize = 0;
    for (page) |entry| {
        if (!try ctx.append(s, writeOutlineEntry, .{ directory, entry })) break;
        returned += 1;
    }
    try s.endArray();
    try s.objectField("entries_total");
    try s.write(entries.items.len);
    try s.objectField("truncated");
    try s.write(returned < entries.items.len);
    try s.objectField("totals");
    try totals.write(s, true);
    try writeBudgetOutcome(ctx, s, .{ .entries = page.len - returned });
    var hints: Hints = .{};
    try writePage(ctx, s, .semidx_outline, args, &hints, if (ctx.budget_exhausted) "response" else "entries", position, returned, entries.items.len);
    const narrow = try std.mem.concat(ctx.arena, []const u8, &.{ &.{"path_prefix"}, try args.unset(&.{"language"}) });
    if (position + limit < entries.items.len) {
        try hints.add(ctx.arena, "entries", .narrow, narrow);
        try hints.add(ctx.arena, "entries", .raise, raisable(.semidx_outline, "limit", limit));
    }
    if (ctx.budget_exhausted) {
        try hints.add(ctx.arena, "response", .narrow, narrow);
        try hints.add(ctx.arena, "response", .raise, raisable(.semidx_outline, "max_response_bytes", max_bytes));
    }
    try hints.write(s);
    try s.objectField("budget");
    try s.write(.{ .limit = limit, .max_response_bytes = max_bytes });
    try s.endObject();
}

fn writeOutlineEntry(ctx: *Context, s: *Stringify, directory: []const u8, entry: OutlineEntry) Error!void {
    try s.beginObject();
    try s.objectField("name");
    try protocol.writeString(s, entry.name);
    try s.objectField("path");
    try protocol.writeString(s, try std.mem.concat(ctx.arena, u8, &.{ directory, entry.name, if (entry.unit == null) "/" else "" }));
    try s.objectField("type");
    try s.write(if (entry.unit == null) "directory" else "file");
    if (entry.unit) |view| {
        try s.objectField("unit");
        try writeUnit(ctx, s, view, .compact);
    }
    try s.objectField("counts");
    try entry.counts.write(s, entry.unit == null);
    try s.endObject();
}

pub fn repoMap(ctx: *Context, s: *Stringify, arguments: ?ObjectMap) Error!void {
    const args = try Args(.semidx_repo_map).init(ctx, arguments);
    const prefix = try args.string("path_prefix");
    const language = try args.choice(model.Language, "language");
    const limit = try args.count("limit");
    const per_file = try args.count("definitions_per_file");
    const detail = try args.choice(DetailArg, "detail");
    const max_bytes = try args.count("max_response_bytes");
    ctx.max_response_bytes = max_bytes;
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
    const position = try cursorPosition(ctx, .semidx_repo_map, args);
    try checkPosition(ctx, position, order.items.len);

    var hints: Hints = .{};
    try beginStructured(ctx, s);
    try s.objectField("files");
    try s.beginArray();
    const page = order.items[position..@min(order.items.len, position + limit)];
    var returned: usize = 0;
    for (page) |i| {
        var definitions_truncated = false;
        if (!try ctx.append(s, writeMapFile, .{ snapshot.units[i], detail, per_file, &definitions_truncated })) break;
        returned += 1;
        if (definitions_truncated) {
            try hints.add(ctx.arena, "definitions", .raise, raisable(.semidx_repo_map, "definitions_per_file", per_file));
        }
    }
    try s.endArray();
    try s.objectField("files_total");
    try s.write(order.items.len);
    try s.objectField("truncated");
    try s.write(returned < order.items.len);
    try writeBudgetOutcome(ctx, s, .{ .files = page.len - returned });
    try writePage(ctx, s, .semidx_repo_map, args, &hints, if (ctx.budget_exhausted) "response" else "files", position, returned, order.items.len);
    const narrow = try args.unset(&.{ "path_prefix", "language" });
    if (position + limit < order.items.len) {
        try hints.add(ctx.arena, "files", .narrow, narrow);
        try hints.add(ctx.arena, "files", .raise, raisable(.semidx_repo_map, "limit", limit));
    }
    if (ctx.budget_exhausted) {
        try hints.add(ctx.arena, "response", .narrow, narrow);
        try hints.add(ctx.arena, "response", .raise, raisable(.semidx_repo_map, "max_response_bytes", max_bytes));
        try hints.add(ctx.arena, "response", .lower, if (per_file > 1) &.{"definitions_per_file"} else &.{});
    }
    try hints.write(s);
    try s.objectField("budget");
    try s.write(.{ .detail = detail, .limit = limit, .definitions_per_file = per_file, .max_response_bytes = max_bytes });
    try s.endObject();
}

/// One repository map file: its unit, diagnostic counts, and top-level
/// definitions. Sets `definitions_truncated` when `per_file` cut them.
fn writeMapFile(ctx: *Context, s: *Stringify, view: semidx.core.graph.SourceUnitView, detail: DetailArg, per_file: u32, definitions_truncated: *bool) Error!void {
    try s.beginObject();
    try s.objectField("unit");
    try writeUnit(ctx, s, view, detail);
    try s.objectField("diagnostics");
    try writeDiagnosticCounts(ctx, s, view.id);

    var top_level: usize = 0;
    var nested: usize = 0;
    try s.objectField("definitions");
    try s.beginArray();
    var found = ctx.snapshot.entitiesMatching(.{ .kind = .definition, .scope = .{ .unit = view.id } });
    while (found.next()) |entity| {
        if (entity.identity.container_path.len != 0) {
            nested += 1;
            continue;
        }
        top_level += 1;
        if (top_level <= per_file) try writeEntity(ctx, s, entity, if (detail == .full) .brief else .listed);
    }
    try s.endArray();
    try s.objectField("top_level_definitions_total");
    try s.write(top_level);
    try s.objectField("definitions_truncated");
    try s.write(top_level > per_file);
    try s.objectField("nested_definitions_total");
    try s.write(nested);
    try s.endObject();
    definitions_truncated.* = top_level > per_file;
}

pub fn findDefinitions(ctx: *Context, s: *Stringify, arguments: ?ObjectMap) Error!void {
    const args = try Args(.semidx_find_definitions).init(ctx, arguments);
    const filter: Snapshot.EntityFilter = .{
        .kind = .definition,
        .name = try args.string("name"),
        .path = try args.string("path"),
        .role = try args.string("role"),
        .language = try args.choice(model.Language, "language"),
        .freshness = freshnessFilter(try args.choice(FreshnessArg, "freshness")),
    };
    const resolution = try args.choice(ResolutionArg, "resolution");
    const limit = try args.count("limit");
    const max_bytes = try args.count("max_response_bytes");
    ctx.max_response_bytes = max_bytes;
    const position = try cursorPosition(ctx, .semidx_find_definitions, args);

    try beginStructured(ctx, s);
    try s.objectField("definitions");
    try s.beginArray();
    var total: usize = 0;
    var returned: usize = 0;
    var omitted: usize = 0;
    var found = ctx.snapshot.entitiesMatching(filter);
    while (found.next()) |entity| {
        if (resolution != .any) {
            const existence = try ctx.existenceOf(entity.id) orelse continue;
            if (!resolutionMatches(resolution, existence.resolution)) continue;
        }
        total += 1;
        if (total <= position or total > position + limit) continue;
        if (try ctx.append(s, writeEntity, .{ entity, EntityShape.full })) returned += 1 else omitted += 1;
    }
    try s.endArray();
    try checkPosition(ctx, position, total);
    try s.objectField("total");
    try s.write(total);
    try s.objectField("truncated");
    try s.write(returned < total);
    try writeBudgetOutcome(ctx, s, .{ .definitions = omitted });
    var hints: Hints = .{};
    try writePage(ctx, s, .semidx_find_definitions, args, &hints, if (ctx.budget_exhausted) "response" else "definitions", position, returned, total);
    const unset = try args.unset(&.{ "name", "path", "language", "role" });
    const narrow = if (resolution == .any) try std.mem.concat(ctx.arena, []const u8, &.{ unset, &.{"resolution"} }) else unset;
    if (position + limit < total) {
        try hints.add(ctx.arena, "definitions", .narrow, narrow);
        try hints.add(ctx.arena, "definitions", .raise, raisable(.semidx_find_definitions, "limit", limit));
    }
    if (ctx.budget_exhausted) {
        try hints.add(ctx.arena, "response", .narrow, narrow);
        try hints.add(ctx.arena, "response", .raise, raisable(.semidx_find_definitions, "max_response_bytes", max_bytes));
    }
    try hints.write(s);
    try s.objectField("budget");
    try s.write(.{ .limit = limit, .max_response_bytes = max_bytes });
    try s.endObject();
}

const max_targets: usize = 50;

/// The entities a references or context call is about.
fn selectTargets(ctx: *Context, args: anytype, freshness: ?model.Freshness, allow_path_only: bool) Error![]model.Entity {
    const id = try args.entityId("entity_id");
    const name = try args.string("name");
    const path = try args.string("path");
    const language = try args.choice(model.Language, "language");

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
    const args = try Args(.semidx_references).init(ctx, arguments);
    const direction = try args.choice(DirectionArg, "direction");
    const freshness = freshnessFilter(try args.choice(FreshnessArg, "freshness"));
    const resolution = try args.choice(ResolutionArg, "resolution");
    const limit = try args.count("limit");
    const detail = try args.choice(DetailArg, "detail");
    const max_bytes = try args.count("max_response_bytes");
    ctx.max_response_bytes = max_bytes;
    const targets = try selectTargets(ctx, args, freshness, false);
    const shown_targets = targets[0..@min(targets.len, max_targets)];
    const position = try cursorPosition(ctx, .semidx_references, args);

    try beginStructured(ctx, s);
    try s.objectField("targets");
    try s.beginArray();
    // Targets are bounded by `max_targets` alone and repeated on every page,
    // so the budget and its first always-admitted item are the
    // relationships'. Compact names a relationship end that is a target by id.
    var in_view: std.ArrayList(model.EntityId) = .empty;
    for (shown_targets) |target| {
        try writeEntity(ctx, s, target, if (detail == .full) .full else .focus);
        if (detail == .compact) try in_view.append(ctx.arena, target.id);
    }
    try s.endArray();
    try s.objectField("targets_total");
    try s.write(targets.len);
    try s.objectField("targets_truncated");
    try s.write(targets.len > max_targets);

    var seen: std.AutoHashMapUnmanaged(model.AssertionId, void) = .empty;
    var total: usize = 0;
    var returned: usize = 0;
    var omitted: usize = 0;
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
                if (total <= position or total > position + limit) continue;
                if (try ctx.append(s, writeRelationship, .{ assertion, @as(?[]const u8, pass.name), detail, @as([]const model.EntityId, in_view.items), @as(?Step, null) })) returned += 1 else omitted += 1;
            }
        }
    }
    try s.endArray();
    try checkPosition(ctx, position, total);
    try s.objectField("relationships_total");
    try s.write(total);
    try s.objectField("truncated");
    try s.write(returned < total);
    try writeBudgetOutcome(ctx, s, .{ .relationships = omitted });
    var hints: Hints = .{};
    try writePage(ctx, s, .semidx_references, args, &hints, if (ctx.budget_exhausted) "response" else "relationships", position, returned, total);
    // `path` and `language` qualify a name; with `entity_id` they are refused.
    const by_name = !args.given("entity_id");
    const narrow_targets = try std.mem.concat(ctx.arena, []const u8, &.{ &.{"entity_id"}, try args.unset(&.{ "path", "language" }) });
    if (targets.len > max_targets and by_name) {
        try hints.add(ctx.arena, "targets", .narrow, narrow_targets);
    }
    var narrow: std.ArrayList([]const u8) = .empty;
    if (by_name) try narrow.appendSlice(ctx.arena, try args.unset(&.{ "path", "language" }));
    if (direction == .both) try narrow.append(ctx.arena, "direction");
    if (resolution == .any) try narrow.append(ctx.arena, "resolution");
    if (position + limit < total) {
        try hints.add(ctx.arena, "relationships", .narrow, narrow.items);
        try hints.add(ctx.arena, "relationships", .raise, raisable(.semidx_references, "limit", limit));
    }
    if (ctx.budget_exhausted) {
        try hints.add(ctx.arena, "response", .narrow, narrow.items);
        try hints.add(ctx.arena, "response", .raise, raisable(.semidx_references, "max_response_bytes", max_bytes));
    }
    try hints.write(s);
    try s.objectField("budget");
    try s.write(.{ .detail = detail, .limit = limit, .target_limit = max_targets, .max_response_bytes = max_bytes });
    try s.endObject();
}

const max_focus: usize = 10;

pub fn context(ctx: *Context, s: *Stringify, arguments: ?ObjectMap) Error!void {
    const args = try Args(.semidx_context).init(ctx, arguments);
    const freshness = freshnessFilter(try args.choice(FreshnessArg, "freshness"));
    const direction = try args.choice(DirectionArg, "direction");
    const depth = try args.count("depth");
    const limit = try args.count("relationship_limit");
    const diagnostic_limit = try args.count("diagnostic_limit");
    const detail = try args.choice(DetailArg, "detail");
    const max_bytes = try args.count("max_response_bytes");
    ctx.max_response_bytes = max_bytes;
    const targets = try selectTargets(ctx, args, freshness, true);
    const snapshot = ctx.snapshot;
    const shown = targets[0..@min(targets.len, max_focus)];
    // Depth 1 renders what it rendered before traversal existed.
    if (depth > 1) ctx.rendered = .empty;

    var hints: Hints = .{};
    var returned_focus: usize = 0;
    var omitted_relationships: usize = 0;
    var omitted_diagnostics: usize = 0;
    // Traversal state: entities reached so far (focus included), relationships
    // already listed, and the entities the next step expands.
    var visited: std.AutoHashMapUnmanaged(model.EntityId, void) = .empty;
    var listed: std.AutoHashMapUnmanaged(model.AssertionId, void) = .empty;
    var frontier: std.ArrayList(model.EntityId) = .empty;
    // Every focus entity has its own focus block, so a traversal never
    // expands one again.
    for (shown) |entity| try visited.put(ctx.arena, entity.id, {});

    try beginStructured(ctx, s);
    try s.objectField("focus");
    try s.beginArray();
    for (shown) |entity| {
        // The focus entity is the item that admits a focus; its lists follow
        // under the same budget.
        const rendered = try ctx.item(s, writeEntity, .{ entity, if (detail == .full) EntityShape.full else EntityShape.focus }) orelse break;
        returned_focus += 1;
        _ = try ctx.renderOnce(entity.id);
        try s.beginObject();
        try s.objectField("entity");
        try writeRaw(s, rendered);

        const unit_id: ?model.SourceUnitId = switch (entity.identity.scope) {
            .unit => |id| id,
            .repository => null,
        };
        try s.objectField("unit");
        if (unit_id) |id| {
            if (snapshot.unit(id)) |view| try writeUnit(ctx, s, view, detail) else try s.write(null);
        } else try s.write(null);

        for (relationshipPasses(entity.id, direction, freshness)) |pass| {
            if (!pass.enabled) continue;
            var n: usize = 0;
            var returned: usize = 0;
            try s.objectField(pass.name);
            try s.beginArray();
            var found = snapshot.relationships(pass.filter);
            while (found.next()) |assertion| {
                n += 1;
                if (n > limit) continue;
                if (!try ctx.append(s, writeRelationship, .{ assertion, @as(?[]const u8, null), detail, @as([]const model.EntityId, &.{entity.id}), @as(?Step, null) })) {
                    omitted_relationships += 1;
                    continue;
                }
                returned += 1;
                if (depth > 1) try reach(ctx, &visited, &listed, &frontier, assertion, pass.incoming);
            }
            try s.endArray();
            try s.objectField(if (pass.incoming) "incoming_total" else "outgoing_total");
            try s.write(n);
            try s.objectField(if (pass.incoming) "incoming_truncated" else "outgoing_truncated");
            try s.write(returned < n);
            if (n > limit) {
                try hints.add(ctx.arena, pass.name, .raise, raisable(.semidx_context, "relationship_limit", limit));
                if (direction == .both) try hints.add(ctx.arena, pass.name, .narrow, &.{"direction"});
            }
        }

        var diagnostics: usize = 0;
        var returned_diagnostics: usize = 0;
        try s.objectField("diagnostics");
        try s.beginArray();
        if (unit_id) |id| {
            for (snapshot.diagnostics) |diagnostic| {
                if (diagnostic.unit != id) continue;
                diagnostics += 1;
                if (diagnostics > diagnostic_limit) continue;
                if (try ctx.append(s, writeDiagnostic, .{ diagnostic, detail })) returned_diagnostics += 1 else omitted_diagnostics += 1;
            }
        }
        try s.endArray();
        try s.objectField("diagnostics_total");
        try s.write(diagnostics);
        try s.objectField("diagnostics_truncated");
        try s.write(returned_diagnostics < diagnostics);
        if (diagnostics > diagnostic_limit) try hints.add(ctx.arena, "diagnostics", .raise, raisable(.semidx_context, "diagnostic_limit", diagnostic_limit));

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
    try s.write(returned_focus < targets.len);

    var omitted_edges: usize = 0;
    if (depth > 1) {
        try s.objectField("traversal");
        try s.beginObject();
        try s.objectField("depth");
        try s.write(depth);
        try s.objectField("direction");
        try s.write(@tagName(direction));
        var edges_total: usize = 0;
        var edges_returned: usize = 0;
        var cut_by_limit = false;
        try s.objectField("edges");
        try s.beginArray();
        var distance: u32 = 2;
        while (distance <= depth and frontier.items.len != 0) : (distance += 1) {
            const expanding = try frontier.toOwnedSlice(ctx.arena);
            for (expanding) |node| {
                for (relationshipPasses(node, direction, freshness)) |pass| {
                    if (!pass.enabled) continue;
                    var n: usize = 0;
                    var found = snapshot.relationships(pass.filter);
                    while (found.next()) |assertion| {
                        // A relationship listed from its other end, or at an
                        // earlier step, is not listed again.
                        if (listed.contains(assertion.id)) continue;
                        n += 1;
                        edges_total += 1;
                        if (n > limit) {
                            cut_by_limit = true;
                            continue;
                        }
                        const step: Step = .{ .distance = distance, .from = node };
                        if (!try ctx.append(s, writeRelationship, .{ assertion, @as(?[]const u8, pass.name), detail, @as([]const model.EntityId, &.{}), @as(?Step, step) })) {
                            omitted_edges += 1;
                            continue;
                        }
                        edges_returned += 1;
                        try reach(ctx, &visited, &listed, &frontier, assertion, pass.incoming);
                    }
                }
            }
        }
        try s.endArray();
        try s.objectField("edges_total");
        try s.write(edges_total);
        try s.objectField("edges_truncated");
        try s.write(edges_returned < edges_total);
        try s.objectField("reached_total");
        try s.write(visited.count() - shown.len);
        try s.endObject();
        if (cut_by_limit) {
            try hints.add(ctx.arena, "edges", .raise, raisable(.semidx_context, "relationship_limit", limit));
            if (direction == .both) try hints.add(ctx.arena, "edges", .narrow, &.{"direction"});
            try hints.add(ctx.arena, "edges", .lower, &.{"depth"});
        }
    }

    try writeBudgetOutcome(ctx, s, .{
        .focus = shown.len - returned_focus,
        .relationships = omitted_relationships,
        .diagnostics = omitted_diagnostics,
        .edges = omitted_edges,
    });
    const narrow_focus = try std.mem.concat(ctx.arena, []const u8, &.{ &.{"entity_id"}, try args.unset(&.{ "path", "language" }) });
    if (targets.len > max_focus) {
        try hints.add(ctx.arena, "focus", .narrow, narrow_focus);
    }
    if (ctx.budget_exhausted) {
        var narrow: std.ArrayList([]const u8) = .empty;
        if (targets.len > 1) try narrow.appendSlice(ctx.arena, narrow_focus);
        if (direction == .both) try narrow.append(ctx.arena, "direction");
        try hints.add(ctx.arena, "response", .narrow, narrow.items);
        var lower: std.ArrayList([]const u8) = .empty;
        if (depth > 1) try lower.append(ctx.arena, "depth");
        if (limit > 1) try lower.append(ctx.arena, "relationship_limit");
        if (diagnostic_limit > 1) try lower.append(ctx.arena, "diagnostic_limit");
        try hints.add(ctx.arena, "response", .lower, lower.items);
        try hints.add(ctx.arena, "response", .raise, raisable(.semidx_context, "max_response_bytes", max_bytes));
    }
    try hints.write(s);
    try s.objectField("budget");
    try s.write(.{
        .detail = detail,
        .direction = direction,
        .depth = depth,
        .relationship_limit = limit,
        .diagnostic_limit = diagnostic_limit,
        .focus_limit = max_focus,
        .max_response_bytes = max_bytes,
    });
    try s.endObject();
}

const RelationshipPass = struct {
    name: []const u8,
    incoming: bool,
    enabled: bool,
    filter: Snapshot.RelationshipFilter,
};

/// The relationships into and out of `id`, each enabled when `direction`
/// includes it.
fn relationshipPasses(id: model.EntityId, direction: DirectionArg, freshness: ?model.Freshness) [2]RelationshipPass {
    return .{
        .{ .name = "incoming", .incoming = true, .enabled = direction != .outgoing, .filter = .{ .target = id, .freshness = freshness } },
        .{ .name = "outgoing", .incoming = false, .enabled = direction != .incoming, .filter = .{ .source = id, .freshness = freshness } },
    };
}

/// Records a listed relationship and queues the entity at its far end for the
/// next traversal step, once. A designator is not an entity and is never
/// followed.
fn reach(
    ctx: *Context,
    visited: *std.AutoHashMapUnmanaged(model.EntityId, void),
    listed: *std.AutoHashMapUnmanaged(model.AssertionId, void),
    frontier: *std.ArrayList(model.EntityId),
    assertion: model.Assertion,
    incoming: bool,
) Allocator.Error!void {
    try listed.put(ctx.arena, assertion.id, {});
    const relationship = assertion.relationship().?;
    const far: model.EntityId = if (incoming) relationship.source else switch (relationship.target) {
        .entity => |id| id,
        .designator => return,
    };
    if ((try visited.getOrPut(ctx.arena, far)).found_existing) return;
    try frontier.append(ctx.arena, far);
}

test "every tool schema is one line of valid JSON naming exactly the declared arguments" {
    for (definitions) |definition| {
        try std.testing.expect(std.mem.indexOfScalar(u8, definition.input_schema, '\n') == null);
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, definition.input_schema, .{});
        defer parsed.deinit();
        const schema = parsed.value.object;
        try std.testing.expectEqualStrings("object", schema.get("type").?.string);
        try std.testing.expect(!schema.get("additionalProperties").?.bool);
        const properties = if (schema.get("properties")) |value| value.object.count() else 0;
        try std.testing.expectEqual(definition.params.len, properties);
        for (definition.params) |param| {
            const property = schema.get("properties").?.object.get(param.name).?.object;
            switch (param.type) {
                .string => try std.testing.expectEqualStrings("string", property.get("type").?.string),
                .entity_id => {
                    try std.testing.expectEqualStrings("integer", property.get("type").?.string);
                    try std.testing.expectEqual(@as(i64, 0), property.get("minimum").?.integer);
                },
                .count => |count| {
                    try std.testing.expectEqualStrings("integer", property.get("type").?.string);
                    try std.testing.expectEqual(@as(i64, 1), property.get("minimum").?.integer);
                    try std.testing.expectEqual(@as(i64, count.maximum), property.get("maximum").?.integer);
                    try std.testing.expectEqual(@as(i64, count.default), property.get("default").?.integer);
                },
                .choice => |choice| {
                    try std.testing.expectEqualStrings("string", property.get("type").?.string);
                    const values = property.get("enum").?.array.items;
                    try std.testing.expectEqual(choice.values.len, values.len);
                    for (choice.values, values) |expected, actual| try std.testing.expectEqualStrings(expected, actual.string);
                    if (choice.default) |default| {
                        try std.testing.expectEqualStrings(default, property.get("default").?.string);
                    } else try std.testing.expect(property.get("default") == null);
                },
            }
        }
    }
    try std.testing.expectEqual(std.enums.values(Tool).len, definitions.len);
    for (definitions, std.enums.values(Tool)) |definition, tool| try std.testing.expectEqual(tool, definition.tool);
}
