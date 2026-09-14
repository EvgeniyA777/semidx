//! The tree-sitter boundary.
//!
//! This is the only module that sees the tree-sitter C ABI. It exposes a small
//! Zig surface over parsing and node traversal and nothing else: no semantic
//! model types, no assertions, no graph. Language frontends sit above it and
//! translate parse nodes into shared-core terms, so a parse node type never
//! reaches the graph.
//!
//! Grammar C sources and the tree-sitter runtime are resolved by `build.zig`
//! from local paths. Nothing here reaches the network.

const std = @import("std");

const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

extern fn tree_sitter_java() callconv(.c) *const c.TSLanguage;
extern fn tree_sitter_clojure() callconv(.c) *const c.TSLanguage;

pub const Error = error{
    /// The grammar could not be assigned, which in practice means the grammar
    /// and the runtime disagree about the parser ABI.
    GrammarUnavailable,
    /// The runtime returned no tree: the parse was cancelled by the byte
    /// budget, or the parser had no grammar.
    ParseFailed,
};

pub const Grammar = enum {
    java,
    clojure,

    fn language(self: Grammar) *const c.TSLanguage {
        return switch (self) {
            .java => tree_sitter_java(),
            .clojure => tree_sitter_clojure(),
        };
    }

    pub fn abiVersion(self: Grammar) u32 {
        return c.ts_language_abi_version(self.language());
    }
};

/// The parser ABI this runtime was built against. Recorded in frontend
/// provenance so an assertion can be traced to the producer that made it.
pub const runtime_abi_version: u32 = c.TREE_SITTER_LANGUAGE_VERSION;

pub const Point = struct { row: u32, column: u32 };

pub const Range = struct {
    start_byte: u32,
    end_byte: u32,
    start_row: u32,
    start_column: u32,
    end_row: u32,
    end_column: u32,
};

/// A simple guard against pathological input. It is a local budget, not a
/// performance feature: exceeding it cancels the parse and is reported as
/// failed analysis rather than as an empty result.
pub const Budget = struct {
    max_bytes: u32,
};

pub const Parser = struct {
    ptr: *c.TSParser,

    pub fn init(grammar: Grammar) Error!Parser {
        const ptr = c.ts_parser_new() orelse return error.GrammarUnavailable;
        errdefer c.ts_parser_delete(ptr);
        if (!c.ts_parser_set_language(ptr, grammar.language())) return error.GrammarUnavailable;
        return .{ .ptr = ptr };
    }

    pub fn deinit(self: *Parser) void {
        c.ts_parser_delete(self.ptr);
        self.* = undefined;
    }

    /// Parses `source` from scratch.
    ///
    /// There is deliberately no previous-tree parameter. tree-sitter can reuse
    /// a tree only if that tree has been told, through `ts_tree_edit`, exactly
    /// which byte ranges changed; handing it an unedited tree makes it conclude
    /// the text is unchanged and return the old parse. Nothing upstream tracks
    /// edit ranges — this pipeline receives replacement contents — so the
    /// parameter could only ever be misused. `contract.PreviousParse` is where
    /// an adapter that does track edits would carry one, and adding it here is
    /// that adapter's job, together with the `ts_tree_edit` calls that make it
    /// correct.
    pub fn parse(self: *Parser, source: []const u8, budget: ?Budget) Error!Tree {
        const tree = blk: {
            if (budget) |limit| {
                var state: ProgressState = .{ .max_bytes = limit.max_bytes };
                break :blk c.ts_parser_parse_with_options(
                    self.ptr,
                    null,
                    sliceInput(&source),
                    .{ .payload = &state, .progress_callback = progressCallback },
                );
            }
            break :blk c.ts_parser_parse_string(
                self.ptr,
                null,
                source.ptr,
                @intCast(source.len),
            );
        } orelse return error.ParseFailed;

        return .{ .ptr = tree };
    }
};

const ProgressState = struct {
    max_bytes: u32,
};

fn progressCallback(state: [*c]c.TSParseState) callconv(.c) bool {
    const payload: *ProgressState = @ptrCast(@alignCast(state.*.payload.?));
    return state.*.current_byte_offset > payload.max_bytes;
}

fn sliceInput(source: *const []const u8) c.TSInput {
    return .{
        .payload = @ptrCast(@constCast(source)),
        .read = readSlice,
        .encoding = c.TSInputEncodingUTF8,
        .decode = null,
    };
}

fn readSlice(
    payload: ?*anyopaque,
    byte_index: u32,
    position: c.TSPoint,
    bytes_read: [*c]u32,
) callconv(.c) [*c]const u8 {
    _ = position;
    const source: *const []const u8 = @ptrCast(@alignCast(payload.?));
    if (byte_index >= source.len) {
        bytes_read.* = 0;
        return "";
    }
    bytes_read.* = @intCast(source.len - byte_index);
    return source.ptr + byte_index;
}

pub const Tree = struct {
    ptr: *c.TSTree,

    pub fn deinit(self: *Tree) void {
        c.ts_tree_delete(self.ptr);
        self.* = undefined;
    }

    pub fn root(self: Tree) Node {
        return .{ .raw = c.ts_tree_root_node(self.ptr) };
    }
};

pub const Node = struct {
    raw: c.TSNode,

    pub fn isNull(self: Node) bool {
        return c.ts_node_is_null(self.raw);
    }

    pub fn isNamed(self: Node) bool {
        return c.ts_node_is_named(self.raw);
    }

    pub fn kind(self: Node) []const u8 {
        return std.mem.span(c.ts_node_type(self.raw));
    }

    pub fn hasError(self: Node) bool {
        return c.ts_node_has_error(self.raw);
    }

    pub fn namedChildCount(self: Node) u32 {
        return c.ts_node_named_child_count(self.raw);
    }

    pub fn namedChild(self: Node, index: u32) ?Node {
        const child: Node = .{ .raw = c.ts_node_named_child(self.raw, index) };
        return if (child.isNull()) null else child;
    }

    pub fn childByFieldName(self: Node, name: []const u8) ?Node {
        const child: Node = .{
            .raw = c.ts_node_child_by_field_name(self.raw, name.ptr, @intCast(name.len)),
        };
        return if (child.isNull()) null else child;
    }

    pub fn startByte(self: Node) u32 {
        return c.ts_node_start_byte(self.raw);
    }

    pub fn endByte(self: Node) u32 {
        return c.ts_node_end_byte(self.raw);
    }

    pub fn range(self: Node) Range {
        const start = c.ts_node_start_point(self.raw);
        const end = c.ts_node_end_point(self.raw);
        return .{
            .start_byte = self.startByte(),
            .end_byte = self.endByte(),
            .start_row = start.row,
            .start_column = start.column,
            .end_row = end.row,
            .end_column = end.column,
        };
    }

    pub fn text(self: Node, source: []const u8) []const u8 {
        const start = self.startByte();
        const end = self.endByte();
        if (start > source.len or end > source.len or start > end) return "";
        return source[start..end];
    }

    pub const NamedChildIterator = struct {
        parent: Node,
        index: u32,
        count: u32,

        pub fn next(self: *NamedChildIterator) ?Node {
            while (self.index < self.count) {
                const child = self.parent.namedChild(self.index);
                self.index += 1;
                if (child) |found| return found;
            }
            return null;
        }
    };

    pub fn namedChildren(self: Node) NamedChildIterator {
        return .{ .parent = self, .index = 0, .count = self.namedChildCount() };
    }
};

const testing = std.testing;

test "the local java grammar parses through the adapter" {
    var parser = try Parser.init(.java);
    defer parser.deinit();

    const source = "class Greeter { String greet() { return greeting(); } }";
    var tree = try parser.parse(source, null);
    defer tree.deinit();

    const root = tree.root();
    try testing.expect(!root.hasError());
    try testing.expectEqualStrings("program", root.kind());

    const class = root.namedChild(0).?;
    try testing.expectEqualStrings("class_declaration", class.kind());
    try testing.expectEqualStrings("Greeter", class.childByFieldName("name").?.text(source));
}

test "the local clojure grammar parses through the adapter" {
    var parser = try Parser.init(.clojure);
    defer parser.deinit();

    const source = "(ns demo.greeter)\n(defn greet [] (str \"hi\"))\n";
    var tree = try parser.parse(source, null);
    defer tree.deinit();

    const root = tree.root();
    try testing.expect(!root.hasError());
    try testing.expectEqualStrings("source", root.kind());

    const first = root.namedChild(0).?;
    try testing.expectEqualStrings("list_lit", first.kind());
    try testing.expectEqualStrings("(ns demo.greeter)", first.text(source));
}

test "a syntax error is visible on the tree rather than silently dropped" {
    var parser = try Parser.init(.java);
    defer parser.deinit();

    var tree = try parser.parse("class Greeter { String greet( ", null);
    defer tree.deinit();
    try testing.expect(tree.root().hasError());
}

test "an exceeded byte budget fails the parse instead of returning a short tree" {
    var parser = try Parser.init(.java);
    defer parser.deinit();

    // The runtime reports progress periodically rather than per byte, so the
    // budget is only observable on input large enough to be reported on.
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(testing.allocator);
    try source.appendSlice(testing.allocator, "class Greeter {\n");
    for (0..4000) |index| {
        try source.print(testing.allocator, "  String m{d}() {{ return \"x\"; }}\n", .{index});
    }
    try source.appendSlice(testing.allocator, "}\n");

    try testing.expectError(
        error.ParseFailed,
        parser.parse(source.items, .{ .max_bytes = 0 }),
    );

    // The same parser still works once the budget is large enough, so the
    // failure is the budget and not a broken parser.
    var tree = try parser.parse(source.items, .{ .max_bytes = 1 << 30 });
    defer tree.deinit();
    try testing.expect(!tree.root().hasError());
}

test "one parser parses successive contents of the same unit independently" {
    var parser = try Parser.init(.java);
    defer parser.deinit();

    var first = try parser.parse("class Greeter { String greet() { return \"a\"; } }", null);
    defer first.deinit();
    var second = try parser.parse("class Greeter { String salute() { return \"b\"; } }", null);
    defer second.deinit();

    // The second parse reflects the second source, not the first. This is the
    // property that reusing an unedited tree would quietly break.
    const first_name = first.root().namedChild(0).?
        .childByFieldName("body").?.namedChild(0).?
        .childByFieldName("name").?;
    const second_name = second.root().namedChild(0).?
        .childByFieldName("body").?.namedChild(0).?
        .childByFieldName("name").?;
    try testing.expectEqualStrings(
        "greet",
        first_name.text("class Greeter { String greet() { return \"a\"; } }"),
    );
    try testing.expectEqualStrings(
        "salute",
        second_name.text("class Greeter { String salute() { return \"b\"; } }"),
    );
}

test "the grammars and the runtime agree on the parser ABI" {
    try testing.expect(Grammar.java.abiVersion() <= runtime_abi_version);
    try testing.expect(Grammar.clojure.abiVersion() <= runtime_abi_version);
}
