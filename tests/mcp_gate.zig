//! The habit loop gate runner shared by every gate profile.
//!
//! A profile drives a `Client` through `Gate.call`, which checks the result
//! shape, the envelope, and budgets of every tool result, records the call's
//! place in the required habit-loop sequence, and times and sizes it. Named
//! hard gates fail with `gate: FAIL [<profile>] <gate>: <detail>`; a profile
//! that passes prints its evidence summary. `docs/mcp/habit_loop_gate.md`
//! specifies the gates, the sequence, and the summary.

const std = @import("std");

const stdio_client = @import("mcp_stdio_client.zig");
const Client = stdio_client.Client;

const testing = std.testing;
const io = testing.io;
const Value = std.json.Value;
pub const ObjectMap = std.json.ObjectMap;

/// A step of the habit loop, in the order a profile must make them.
pub const Step = enum { health, outline, repo_map, find_definitions, references, context, edit, refresh, after_refresh };

const required_sequence = [_]Step{ .health, .outline, .repo_map, .find_definitions, .references, .context, .edit, .refresh, .after_refresh };

/// Tools whose results are lists and must report the budget they applied.
const list_tools = [_][]const u8{ "semidx_outline", "semidx_repo_map", "semidx_find_definitions", "semidx_references", "semidx_context" };

pub const Gate = struct {
    arena: std.mem.Allocator,
    profile: []const u8,
    client: *Client,
    started: std.Io.Timestamp,
    first_response_ms: ?i64 = null,
    steps: std.ArrayList(Step) = .empty,
    /// The revision `semidx_refresh` published, once it has been called.
    refreshed_revision: ?i64 = null,
    passed: std.ArrayList([]const u8) = .empty,
    observations: std.ArrayList([]const u8) = .empty,

    /// `started` is when the server process was started.
    pub fn init(arena: std.mem.Allocator, profile: []const u8, client: *Client, started: std.Io.Timestamp) Gate {
        return .{ .arena = arena, .profile = profile, .client = client, .started = started };
    }

    /// Fails the named hard gate unless `ok`, saying why.
    pub fn require(self: *Gate, ok: bool, gate: []const u8, comptime fmt: []const u8, args: anytype) error{GateFailed}!void {
        if (ok) return;
        std.debug.print("gate: FAIL [{s}] {s}: " ++ fmt ++ "\n", .{ self.profile, gate } ++ args);
        return error.GateFailed;
    }

    /// Records that a named hard gate passed, for the evidence summary.
    pub fn pass(self: *Gate, gate: []const u8, comptime fmt: []const u8, args: anytype) !void {
        try self.passed.append(self.arena, try std.fmt.allocPrint(self.arena, "{s}: " ++ fmt, .{gate} ++ args));
    }

    /// Records an observation for the evidence summary. It never fails the gate.
    pub fn observe(self: *Gate, comptime fmt: []const u8, args: anytype) !void {
        try self.observations.append(self.arena, try std.fmt.allocPrint(self.arena, fmt, args));
    }

    /// Calls a tool and returns its structured result after checking the
    /// `result_shape`, `semantic_contract_null`, `bounded_lists`, and
    /// `new_snapshot_observed` gates for this one call.
    pub fn call(self: *Gate, id: i64, name: []const u8, arguments: []const u8) !ObjectMap {
        var bytes: usize = undefined;
        return self.sizedCall(id, name, arguments, &bytes);
    }

    /// `call`, also returning the transcript bytes of the response.
    pub fn sizedCall(self: *Gate, id: i64, name: []const u8, arguments: []const u8, bytes: *usize) !ObjectMap {
        const line = try std.fmt.allocPrint(
            self.arena,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"tools/call\",\"params\":{{{s},\"name\":\"{s}\",\"arguments\":{s}}}}}",
            .{ id, stdio_client.modern_meta, name, arguments },
        );
        const called = std.Io.Timestamp.now(io, .awake);
        const before = self.client.transcript.items.len;
        try self.client.sendLine(line);
        const response_line = try self.client.readLine(try std.fmt.allocPrint(self.arena, "a response to {s} (request {d})", .{ name, id }));
        const elapsed = called.untilNow(io, .awake).toMilliseconds();
        bytes.* = self.client.transcript.items.len - before;
        if (self.first_response_ms == null) self.first_response_ms = self.started.untilNow(io, .awake).toMilliseconds();
        try self.observe("{s} {s}: {d} ms, {d} bytes", .{ name, arguments, elapsed, bytes.* });

        const result = try self.resultOf(response_line, id, name);
        try self.require(result.get("semantic_contract_version") != null and result.get("semantic_contract_version").? == .null, "semantic_contract_null", "{s} (request {d}) does not report semantic_contract_version null", .{ name, id });
        const revision = snapshotRevision(result) orelse {
            try self.require(false, "result_shape", "{s} (request {d}) has no integer snapshot.revision", .{ name, id });
            unreachable;
        };
        for (list_tools) |list_tool| {
            if (!std.mem.eql(u8, list_tool, name)) continue;
            const budget = result.get("budget");
            try self.require(budget != null and budget.? == .object, "bounded_lists", "{s} (request {d}) reports no budget object", .{ name, id });
        }

        const step: ?Step = if (std.mem.eql(u8, name, "semidx_health"))
            .health
        else if (std.mem.eql(u8, name, "semidx_refresh"))
            .refresh
        else if (self.refreshed_revision != null)
            .after_refresh
        else if (std.mem.eql(u8, name, "semidx_outline"))
            .outline
        else if (std.mem.eql(u8, name, "semidx_repo_map"))
            (if (isCompact(result)) .repo_map else null)
        else if (std.mem.eql(u8, name, "semidx_find_definitions"))
            .find_definitions
        else if (std.mem.eql(u8, name, "semidx_references"))
            .references
        else if (std.mem.eql(u8, name, "semidx_context"))
            .context
        else
            null;
        if (step) |s| {
            if (s == .after_refresh) try self.require(revision == self.refreshed_revision.?, "new_snapshot_observed", "{s} (request {d}) after the refresh read revision {d}, not the refreshed revision {d}", .{ name, id, revision, self.refreshed_revision.? });
            try self.steps.append(self.arena, s);
        }
        return result;
    }

    /// Parses one response line and checks it is a complete, non-error tool
    /// result to request `id` with a structured object.
    fn resultOf(self: *Gate, line: []const u8, id: i64, name: []const u8) !ObjectMap {
        const value = std.json.parseFromSliceLeaky(Value, self.arena, line, .{}) catch {
            try self.require(false, "result_shape", "the response to {s} (request {d}) is not JSON: {s}", .{ name, id, line });
            unreachable;
        };
        const ok = value == .object and
            isString(value.object.get("jsonrpc"), "2.0") and
            value.object.get("id") != null and value.object.get("id").? == .integer and value.object.get("id").?.integer == id;
        try self.require(ok, "result_shape", "the response to {s} (request {d}) is not a JSON-RPC response to it: {s}", .{ name, id, line });
        const result = value.object.get("result") orelse {
            try self.require(false, "result_shape", "{s} (request {d}) returned no result: {s}", .{ name, id, line });
            unreachable;
        };
        try self.require(result == .object, "result_shape", "{s} (request {d}) returned a non-object result", .{ name, id });
        try self.require(isString(result.object.get("resultType"), "complete"), "result_shape", "{s} (request {d}) is not a complete result", .{ name, id });
        const is_error = result.object.get("isError");
        try self.require(is_error != null and is_error.? == .bool and !is_error.?.bool, "result_shape", "{s} (request {d}) is an error result: {s}", .{ name, id, line });
        const structured = result.object.get("structuredContent");
        try self.require(structured != null and structured.? == .object, "result_shape", "{s} (request {d}) has no structuredContent object", .{ name, id });
        return structured.?.object;
    }

    /// Records the edit of a file in the temporary root.
    pub fn edited(self: *Gate, what: []const u8) !void {
        try self.steps.append(self.arena, .edit);
        try self.observe("edit: {s}", .{what});
    }

    /// Calls `semidx_refresh` and checks the `refresh_revision` gate against
    /// the revision published before the edit.
    pub fn refresh(self: *Gate, id: i64, before: i64) !ObjectMap {
        const refreshed = try self.call(id, "semidx_refresh", "{}");
        const revision = snapshotRevision(refreshed).?;
        try self.require(revision > before, "refresh_revision", "refresh published revision {d}, not later than {d}", .{ revision, before });
        const previous = refreshed.get("previous_revision");
        try self.require(previous != null and previous.? == .integer and previous.?.integer == before, "refresh_revision", "refresh reports a previous revision other than {d}", .{before});
        self.refreshed_revision = revision;
        try self.pass("refresh_revision", "{d} -> {d}", .{ before, revision });
        const scan = refreshed.get("scan").?.object;
        try self.observe("refresh: revision {d} -> {d}, changed {d}, added {d}, removed {d}, analyzed {d}, entity ids preserved {}", .{
            before,
            revision,
            scan.get("changed").?.integer,
            scan.get("added").?.integer,
            scan.get("removed").?.integer,
            scan.get("analyzed").?.integer,
            refreshed.get("entity_ids_preserved").?.bool,
        });
        return refreshed;
    }

    /// Checks the health gates every profile shares: `product_version`,
    /// `parsers_available`, the evidence-text part of `no_source_text`, and
    /// that diagnostic counts are reported. Returns the diagnostic counts.
    pub fn checkHealth(self: *Gate, health: ObjectMap, product_version: []const u8) !ObjectMap {
        const reported = health.get("product_version");
        try self.require(reported != null and isString(reported, product_version), "product_version", "health does not report product version {s}", .{product_version});
        try self.pass("product_version", "{s}", .{product_version});
        try self.pass("semantic_contract_null", "every result", .{});

        const languages = health.get("languages").?.array.items;
        try self.require(languages.len > 0, "parsers_available", "health lists no languages", .{});
        for (languages) |language| {
            const name = language.object.get("language").?.string;
            try self.require(language.object.get("parser").?.object.get("available").?.bool, "parsers_available", "no parser is available for {s}", .{name});
        }
        try self.pass("parsers_available", "{d} languages", .{languages.len});

        const evidence_text = health.get("evidence_text").?.object;
        try self.require(!evidence_text.get("enabled").?.bool, "no_source_text", "health reports evidence text enabled without --allow-evidence-text", .{});

        const diagnostics = health.get("diagnostics");
        try self.require(diagnostics != null and diagnostics.? == .object, "diagnostics_visible", "health reports no diagnostic counts", .{});
        const units = health.get("units").?.object;
        const current = health.get("graph").?.object.get("assertions").?.object.get("current").?.object;
        try self.observe("health: units total {d}, current {d}, pending {d}, stale {d}; current facts {d}, unresolved {d}", .{
            units.get("total").?.integer,
            units.get("current").?.integer,
            units.get("pending").?.integer,
            units.get("stale").?.integer,
            current.get("fact").?.integer,
            current.get("unresolved").?.integer,
        });
        try self.observe("health: diagnostics analysis_unavailable {d}, analysis_failed {d}, unsupported_construct {d}, confirmed_absence {d}", .{
            diagnostics.?.object.get("analysis_unavailable").?.integer,
            diagnostics.?.object.get("analysis_failed").?.integer,
            diagnostics.?.object.get("unsupported_construct").?.integer,
            diagnostics.?.object.get("confirmed_absence").?.integer,
        });
        return diagnostics.?.object;
    }

    /// Checks that a diagnostic kind the profile knows to exist is counted.
    pub fn requireDiagnostic(self: *Gate, diagnostics: ObjectMap, kind: []const u8) !void {
        const count = diagnostics.get(kind).?.integer;
        try self.require(count > 0, "diagnostics_visible", "health counts no {s} diagnostics", .{kind});
        try self.pass("diagnostics_visible", "{s} {d}", .{ kind, count });
    }

    /// Checks the truncation part of `bounded_lists`: a call that hit its
    /// limit says so and reports a total larger than what it returned.
    pub fn requireTruncated(self: *Gate, what: []const u8, result: ObjectMap, list: []const u8, total: []const u8, truncated: []const u8) !void {
        const returned = result.get(list).?.array.items.len;
        const reported_total = result.get(total).?.integer;
        try self.require(result.get(truncated).?.bool and reported_total > returned, "bounded_lists", "{s} returned {d} of {d} {s} without reporting truncation", .{ what, returned, reported_total, list });
        try self.pass("bounded_lists", "every list result has budget; {s} returned {d} of {d} {s}, truncated", .{ what, returned, reported_total, list });
    }

    /// Closes the server's input and checks `call_sequence`,
    /// `stream_discipline`, and the transcript part of `no_source_text`, then
    /// prints the evidence summary. `source_texts` is body text of the indexed
    /// source that no result may contain.
    pub fn finish(self: *Gate, log_dir: std.Io.Dir, source_texts: []const []const u8) !void {
        var next: usize = 0;
        for (self.steps.items) |step| {
            if (next < required_sequence.len and step == required_sequence[next]) next += 1;
        }
        try self.require(next == required_sequence.len, "call_sequence", "the habit loop never reached `{t}`", .{if (next < required_sequence.len) required_sequence[next] else Step.after_refresh});
        try self.pass("call_sequence", "health, outline, repo_map, find_definitions, references, context, edit, refresh, after_refresh", .{});

        const ended = try self.client.shutdown();
        try self.require(ended.trailing.len == 0, "stream_discipline", "stdout carried {d} bytes after the last response: {s}", .{ ended.trailing.len, ended.trailing });
        try self.require(ended.exit_code == 0, "stream_discipline", "semidx-mcp exited with status {d}", .{ended.exit_code});
        const transcript = self.client.transcript.items;
        try self.require(std.unicode.utf8ValidateSlice(transcript), "stream_discipline", "stdout is not valid UTF-8", .{});
        const stderr_text = try log_dir.readFileAlloc(io, "stderr.log", self.arena, .limited(1 << 20));
        try self.require(std.mem.indexOf(u8, stderr_text, "semidx-mcp: input closed; exiting") != null, "stream_discipline", "stderr has no exit line:\n{s}", .{stderr_text});
        try self.pass("stream_discipline", "exit 0, no trailing stdout, {d} stdout bytes, {d} stderr bytes", .{ transcript.len, stderr_text.len });

        try self.require(std.mem.indexOf(u8, transcript, "source_text") == null, "no_source_text", "a result contains source_text", .{});
        for (source_texts) |text| {
            try self.require(std.mem.indexOf(u8, transcript, text) == null, "no_source_text", "the transcript contains source text `{s}`", .{text});
        }
        try self.pass("no_source_text", "evidence text disabled; no source_text; {d} body texts absent", .{source_texts.len});

        std.debug.print("gate: profile {s}: first response {d} ms after start\n", .{ self.profile, self.first_response_ms.? });
        for (self.passed.items) |line| std.debug.print("gate: hard pass {s}\n", .{line});
        for (self.observations.items) |line| std.debug.print("gate: observation {s}\n", .{line});
    }
};

pub fn snapshotRevision(result: ObjectMap) ?i64 {
    const snapshot = result.get("snapshot") orelse return null;
    if (snapshot != .object) return null;
    const revision = snapshot.object.get("revision") orelse return null;
    return if (revision == .integer) revision.integer else null;
}

fn isCompact(result: ObjectMap) bool {
    const budget = result.get("budget") orelse return false;
    return budget == .object and isString(budget.object.get("detail"), "compact");
}

fn isString(value: ?Value, expected: []const u8) bool {
    const v = value orelse return false;
    return v == .string and std.mem.eql(u8, v.string, expected);
}

/// Starts the server with its stderr captured to `stderr.log` in `log_dir`.
pub fn startServer(gpa: std.mem.Allocator, exe: []const u8, root: []const u8, extra_args: []const []const u8, log_dir: std.Io.Dir) !*Client {
    const stderr_file = try log_dir.createFile(io, "stderr.log", .{});
    defer stderr_file.close(io);
    return Client.start(gpa, exe, root, extra_args, log_dir, stderr_file);
}
