//! Runtime smoke test for the local MCP stdio preview.
//!
//! It drives the built `semidx-mcp` executable as a client would: over its real
//! stdin and stdout, with stderr captured to a file. It passes only when every
//! stdout line is a JSON-RPC response to the request just sent, nothing else
//! reaches stdout before end of stream, the process exits with status 0, and
//! the whole stderr stream has been read.

const std = @import("std");
const build_options = @import("build_options");

const testing = std.testing;
const io = testing.io;
const Value = std.json.Value;

const stdio_client = @import("mcp_stdio_client.zig");
const Client = stdio_client.Client;
const modern_meta = stdio_client.modern_meta;

/// Text from the fixture's function bodies. The server never reads unit
/// contents into a result, so none of it may appear.
const fixture_body_text = [_][]const u8{ "self.name", "hello" };

test "semidx-mcp --version prints the product version to stdout and exits" {
    const gpa = testing.allocator;
    const result = try std.process.run(gpa, io, .{
        .argv = &.{ build_options.mcp_exe, "--version" },
        .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } },
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    // The release this tree prepares. The version itself is defined once, in
    // build.zig.zon; this pins what the gate expects of it.
    try testing.expectEqualStrings("0.1.0-preview.3", build_options.product_version);
    try testing.expectEqualStrings("semidx-mcp 0.1.0-preview.3\n", result.stdout);
    try testing.expectEqualStrings("", result.stderr);
}

fn errorCode(response: Value) i64 {
    return response.object.get("error").?.object.get("code").?.integer;
}

test "semidx-mcp serves both protocol eras over stdio with nothing but protocol on stdout" {
    const gpa = testing.allocator;

    var root_dir = testing.tmpDir(.{});
    defer root_dir.cleanup();
    var log_dir = testing.tmpDir(.{});
    defer log_dir.cleanup();

    const fixture_path = try std.fs.path.join(gpa, &.{ build_options.fixtures_dir, "zig", "greeter.zig" });
    defer gpa.free(fixture_path);
    const fixture = try std.Io.Dir.cwd().readFileAlloc(io, fixture_path, gpa, .limited(1 << 20));
    defer gpa.free(fixture);
    try root_dir.dir.writeFile(io, .{ .sub_path = "greeter.zig", .data = fixture });
    const root = try root_dir.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(root);

    const stderr_file = try log_dir.dir.createFile(io, "stderr.log", .{});
    const client = client: {
        defer stderr_file.close(io);
        break :client try Client.start(gpa, build_options.mcp_exe, root, &.{}, log_dir.dir, stderr_file);
    };
    defer client.destroy();

    // -- 2026-07-28: stateless, per-request _meta ---------------------------
    const discover = try client.request(1, "server/discover", "{" ++ modern_meta ++ "}");
    const discovered = discover.object.get("result").?.object;
    try testing.expectEqualStrings("complete", discovered.get("resultType").?.string);
    try testing.expectEqualStrings("2026-07-28", discovered.get("supportedVersions").?.array.items[0].string);
    try testing.expect(discovered.get("capabilities").?.object.get("tools") != null);

    const list = try client.request(2, "tools/list", "{" ++ modern_meta ++ "}");
    const listed = list.object.get("result").?.object.get("tools").?.array.items;
    const expected_tools = [_][]const u8{ "semidx_health", "semidx_outline", "semidx_repo_map", "semidx_find_definitions", "semidx_references", "semidx_context", "semidx_refresh" };
    try testing.expectEqual(expected_tools.len, listed.len);
    for (expected_tools, listed) |name, tool| try testing.expectEqualStrings(name, tool.object.get("name").?.string);

    const health = try client.callTool(3, "semidx_health", "{}");
    const first_revision = health.get("snapshot").?.object.get("revision").?.integer;
    try testing.expect(first_revision > 0);
    try testing.expectEqual(@as(i64, 1), health.get("units").?.object.get("current").?.integer);
    try testing.expect(!health.get("evidence_text").?.object.get("enabled").?.bool);
    try testing.expectEqualStrings(build_options.product_version, health.get("product_version").?.string);
    try testing.expect(health.get("semantic_contract_version").? == .null);
    for (health.get("languages").?.array.items) |language| {
        try testing.expect(language.object.get("parser").?.object.get("available").?.bool);
    }

    // The top-level `greet` and the `greet` member of `Greeter`, told apart by
    // their container path.
    const definitions = try client.callTool(4, "semidx_find_definitions", "{\"name\":\"greet\",\"language\":\"zig\"}");
    try testing.expectEqual(@as(i64, 2), definitions.get("total").?.integer);
    var members: usize = 0;
    for (definitions.get("definitions").?.array.items) |item| {
        const greet = item.object;
        try testing.expectEqualStrings("greeter.zig", greet.get("evidence").?.object.get("unit").?.object.get("path").?.string);
        try testing.expectEqualStrings("fact", greet.get("existence").?.object.get("resolution").?.object.get("category").?.string);
        const container_path = greet.get("container_path").?.array.items;
        if (container_path.len == 1 and std.mem.eql(u8, "Greeter", container_path[0].string)) members += 1;
    }
    try testing.expectEqual(@as(usize, 1), members);

    const context = try client.callTool(5, "semidx_context", "{\"name\":\"announce\"}");
    const focus = context.get("focus").?.array.items[0].object;
    var saw_unresolved = false;
    var saw_fact = false;
    for (focus.get("outgoing").?.array.items) |relationship| {
        const category = relationship.object.get("resolution").?.object.get("category").?.string;
        const target = relationship.object.get("target").?.object;
        if (std.mem.eql(u8, category, "unresolved")) {
            saw_unresolved = true;
            // An unresolved claim keeps its designator and names no entity.
            try testing.expect(target.get("designator") != null and target.get("entity") == null);
        }
        if (std.mem.eql(u8, category, "fact")) saw_fact = true;
        try testing.expectEqualStrings("frontend.zig", relationship.object.get("producer").?.object.get("name").?.string);
        try testing.expectEqualStrings("current", relationship.object.get("freshness").?.string);
    }
    try testing.expect(saw_unresolved and saw_fact);
    try testing.expect(focus.get("diagnostics").?.array.items.len > 0);

    const unsupported = try client.request(6, "tools/list", "{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"1900-01-01\",\"io.modelcontextprotocol/clientCapabilities\":{}}}");
    try testing.expectEqual(@as(i64, -32022), errorCode(unsupported));
    const no_capabilities = try client.request(7, "tools/list", "{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\"}}");
    try testing.expectEqual(@as(i64, -32602), errorCode(no_capabilities));

    // A notification gets no response; the next line answers the next request.
    try client.sendLine("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":5}}");
    try client.sendLine("{not json");
    const parse_error_line = try client.readLine("a parse error response");
    try testing.expect(std.mem.indexOf(u8, parse_error_line, "-32700") != null);

    // -- 2025-06-18: initialize, then requests without _meta -----------------
    const early = try client.request(8, "tools/list", "{}");
    try testing.expectEqual(@as(i64, -32602), errorCode(early));
    const initialize = try client.request(9, "initialize", "{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{},\"clientInfo\":{\"name\":\"smoke\",\"version\":\"1\"}}");
    const initialized = initialize.object.get("result").?.object;
    try testing.expectEqualStrings("2025-06-18", initialized.get("protocolVersion").?.string);
    try testing.expectEqualStrings("semidx", initialized.get("serverInfo").?.object.get("name").?.string);
    try client.sendLine("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}");
    const legacy_list = try client.request(10, "tools/list", "{}");
    try testing.expectEqual(expected_tools.len, legacy_list.object.get("result").?.object.get("tools").?.array.items.len);
    const legacy_call = try client.request(11, "tools/call", "{\"name\":\"semidx_repo_map\",\"arguments\":{}}");
    const legacy_result = legacy_call.object.get("result").?.object;
    try testing.expect(!legacy_result.get("isError").?.bool);
    try testing.expectEqual(@as(i64, 1), legacy_result.get("structuredContent").?.object.get("files_total").?.integer);

    // -- refresh observes an edit through a new snapshot ---------------------
    try root_dir.dir.writeFile(io, .{ .sub_path = "farewell.zig", .data = "pub fn farewell() void {}\n" });
    const refreshed = try client.callTool(12, "semidx_refresh", "{}");
    const second_revision = refreshed.get("snapshot").?.object.get("revision").?.integer;
    try testing.expect(second_revision > first_revision);
    try testing.expectEqual(first_revision, refreshed.get("previous_revision").?.integer);
    const farewell = try client.callTool(13, "semidx_find_definitions", "{\"name\":\"farewell\"}");
    try testing.expectEqual(second_revision, farewell.get("snapshot").?.object.get("revision").?.integer);
    try testing.expectEqual(@as(i64, 1), farewell.get("total").?.integer);

    // -- shutdown: close stdin, drain both streams, check the exit status ----
    const ended = try client.shutdown();
    try testing.expectEqualStrings("", ended.trailing);
    try testing.expectEqual(@as(u8, 0), ended.exit_code);

    const stderr_text = try log_dir.dir.readFileAlloc(io, "stderr.log", gpa, .limited(1 << 20));
    defer gpa.free(stderr_text);
    try testing.expect(std.unicode.utf8ValidateSlice(stderr_text));
    try testing.expect(std.mem.indexOf(u8, stderr_text, "semidx-mcp: indexed 1 source units") != null);
    try testing.expect(std.mem.indexOf(u8, stderr_text, "semidx-mcp: input closed; exiting") != null);

    // Default output carried locations and graph context, never body text.
    for (fixture_body_text) |text| {
        try testing.expect(std.mem.indexOf(u8, client.transcript.items, text) == null);
    }
    try testing.expect(std.unicode.utf8ValidateSlice(client.transcript.items));
}
