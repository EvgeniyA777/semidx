//! The Jev HTTP adapter ([ADR 013](../../docs/adr/013_optional_jev_ranking_projection.md)
//! D4, [Plan 015](../../docs/plans/015_optional_jev_ranking_projection.md)
//! Stage 3). The only part of this integration that knows about TypeSafe's
//! endpoint, HTTP, bearer authentication, JSON request/response shape, or
//! retry and deadline policy. It implements `ranking.Provider`; nothing else
//! in this process performs a Jev HTTP request, and `ranking.decide` still
//! validates every answer this adapter produces exactly as it would any other
//! provider's, including the fake used in tests.
//!
//! Request and response field names come from the live TypeSafe API
//! reference read during Plan 015 Stage 0 and pinned in
//! `fixtures/jev/*.json`; `buildRequestBody` and `parseResponse` are tested
//! directly against those committed fixtures below, so a change to either
//! shape is caught without a network call.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Uri = std.Uri;
const http = std.http;
const Writer = std.Io.Writer;
const Stringify = std.json.Stringify;
const ranking = @import("ranking.zig");

/// The fixed English rubric committed in Plan 015 Stage 0
/// (`fixtures/jev/request_two_candidates.json`). Every `Noul` question uses
/// it verbatim; only the candidate ordinal named by the question id varies.
/// Source-derived state is data to this rubric, never instructions: the
/// question is always "is this specific, already-selected candidate card
/// useful," never anything the state's content could redirect.
const instructions = "Is this candidate useful context for answering the query about the state's \"query\" field?";
const criteria_true = "The candidate directly helps answer the query";
const criteria_false = "The candidate is unrelated or only incidentally connected";

pub const JevProvider = struct {
    allocator: Allocator,
    io: Io,
    /// Read once at construction from the environment; never logged, never
    /// part of any error message, never stored anywhere else.
    api_key: []const u8,
    /// The full consented endpoint URL, e.g.
    /// `https://api.typesafe.ai/v1/systemone`.
    endpoint: []const u8,
    model: []const u8,
    client: http.Client,

    pub fn init(allocator: Allocator, io: Io, endpoint: []const u8, model: []const u8, api_key: []const u8) JevProvider {
        return .{
            .allocator = allocator,
            .io = io,
            .api_key = api_key,
            .endpoint = endpoint,
            .model = model,
            .client = .{ .allocator = allocator, .io = io },
        };
    }

    pub fn deinit(self: *JevProvider) void {
        self.client.deinit();
    }

    pub fn provider(self: *JevProvider) ranking.Provider {
        return .{ .name = "jev", .requested_model = self.model, .ptr = self, .rankFn = rankImpl };
    }

    fn rankImpl(ptr: *anyopaque, arena: Allocator, query: []const u8, cards: []const ranking.Card) anyerror!ranking.RankOutcome {
        const self: *JevProvider = @ptrCast(@alignCast(ptr));
        return self.rank(arena, query, cards);
    }

    fn rank(self: *JevProvider, arena: Allocator, query: []const u8, cards: []const ranking.Card) !ranking.RankOutcome {
        const state = ranking.serializeState(arena, query, cards, ranking.default_state_ceiling_bytes) catch |err| switch (err) {
            error.QueryTooLarge => return unavailable("query and its graph metadata do not fit the outbound state ceiling"),
            else => |e| return e,
        };
        const body = try buildRequestBody(arena, state.json, self.model, cards[0..state.sent]);
        if (body.len > ranking.request_ceiling_bytes) {
            return unavailable("serialized request exceeds the request size ceiling");
        }

        const started = Io.Timestamp.now(self.io, .awake).withClock(.awake);
        var retried = false;
        while (true) {
            const attempt_result = self.attemptOnce(arena, body) catch |err| return unavailable(sanitizeTransportError(err));
            switch (attempt_result) {
                .outcome => |outcome| return outcome,
                .retry_after_seconds => |seconds| {
                    if (retried) return unavailable("provider still overloaded after one retry");
                    const elapsed_ms = started.durationFromNow(self.io).raw.toMilliseconds();
                    const retry_delay_ms = seconds * std.time.ms_per_s;
                    if (elapsed_ms + retry_delay_ms > ranking.provider_deadline_ms) {
                        return unavailable("a retry would exceed the provider deadline");
                    }
                    Io.Timeout.sleep(.{ .duration = .{ .raw = .fromMilliseconds(retry_delay_ms), .clock = .awake } }, self.io) catch {};
                    retried = true;
                },
            }
        }
    }

    const AttemptResult = union(enum) {
        outcome: ranking.RankOutcome,
        /// The official retryable statuses (429, 529) and the delay named by
        /// a numeric `Retry-After`, in seconds. Any other retry-after shape,
        /// or its absence, is treated as "do not retry".
        retry_after_seconds: i64,
    };

    fn attemptOnce(self: *JevProvider, arena: Allocator, body: []const u8) !AttemptResult {
        const uri = Uri.parse(self.endpoint) catch return .{ .outcome = unavailable("consented endpoint failed to parse") };
        const authorization = try std.fmt.allocPrint(arena, "Bearer {s}", .{self.api_key});
        const request_body = try arena.dupe(u8, body);

        var req = self.client.request(.POST, uri, .{
            // The consented endpoint is the only allowed destination; a
            // redirect anywhere, including to the same host, is rejected
            // rather than followed, so the authorization header can never
            // reach a second origin.
            .redirect_behavior = .not_allowed,
            .headers = .{ .content_type = .{ .override = "application/json" } },
            .extra_headers = &.{.{ .name = "authorization", .value = authorization }},
        }) catch |err| return .{ .outcome = unavailable(sanitizeTransportError(err)) };
        defer req.deinit();

        req.sendBodyComplete(request_body) catch |err| return .{ .outcome = unavailable(sanitizeTransportError(err)) };

        var redirect_buffer: [1]u8 = undefined;
        var response = req.receiveHead(&redirect_buffer) catch |err| return .{ .outcome = unavailable(sanitizeTransportError(err)) };

        const status_code = @intFromEnum(response.head.status);
        if (status_code == 429 or status_code == 529) {
            if (parseRetryAfterSeconds(&response)) |seconds| return .{ .retry_after_seconds = seconds };
            return .{ .outcome = unavailable("provider reported overload without a usable Retry-After") };
        }
        if (status_code != 200) {
            return .{ .outcome = unavailable("provider returned a non-success status") };
        }

        var transfer_buffer: [4096]u8 = undefined;
        const reader = response.reader(&transfer_buffer);
        const response_body = reader.allocRemaining(arena, .limited(ranking.response_ceiling_bytes)) catch |err| switch (err) {
            error.StreamTooLong => return .{ .outcome = unavailable("provider response exceeds the response size ceiling") },
            else => |e| return .{ .outcome = unavailable(sanitizeTransportError(e)) },
        };
        return .{ .outcome = try parseResponse(arena, self.model, response_body) };
    }
};

fn unavailable(reason: []const u8) ranking.RankOutcome {
    return .{ .unavailable = .{ .reason = reason } };
}

/// Never includes the raw error's dynamic detail (a header value, a body
/// fragment, a URL) — only the fixed name of what kind of transport failure
/// happened, safe to surface in a tool result or a log line.
fn sanitizeTransportError(err: anyerror) []const u8 {
    return switch (err) {
        error.ConnectionRefused, error.ConnectionResetByPeer, error.NetworkUnreachable, error.HostUnreachable => "could not reach the provider",
        error.CertificateBundleLoadFailure, error.TlsInitializationFailed, error.TlsFailure, error.TlsAlert => "TLS to the provider failed",
        error.TooManyHttpRedirects => "provider attempted a redirect, which is rejected by policy",
        error.HttpHeadersOversize, error.HttpHeadersInvalid, error.HttpHeadersUnreadable => "provider sent a malformed response head",
        error.Canceled => "the request deadline elapsed",
        else => "provider request failed",
    };
}

fn parseRetryAfterSeconds(response: *http.Client.Response) ?i64 {
    var headers = response.head.iterateHeaders();
    while (headers.next()) |header| {
        if (!std.ascii.eqlIgnoreCase(header.name, "retry-after")) continue;
        return std.fmt.parseInt(i64, header.value, 10) catch return null;
    }
    return null;
}

/// `{"state": <state_json verbatim>, "model": <model>, "questions": {"candidate_0": {"type":"noul","instructions":...,"criteria":{"true":...,"false":...}}, ...}}`,
/// matching `fixtures/jev/request_two_candidates.json` exactly for the same
/// input.
fn buildRequestBody(arena: Allocator, state_json: []const u8, model: []const u8, sent_cards: []const ranking.Card) (Allocator.Error || Writer.Error)![]const u8 {
    var out: Writer.Allocating = .init(arena);
    var s: Stringify = .{ .writer = &out.writer };
    try s.beginObject();
    try s.objectField("state");
    try s.beginWriteRaw();
    try s.writer.writeAll(state_json);
    s.endWriteRaw();
    try s.objectField("model");
    try s.write(model);
    try s.objectField("questions");
    try s.beginObject();
    for (sent_cards) |card| {
        try s.objectField(card.ordinal);
        try s.beginObject();
        try s.objectField("type");
        try s.write("noul");
        try s.objectField("instructions");
        try s.write(instructions);
        try s.objectField("criteria");
        try s.beginObject();
        try s.objectField("true");
        try s.write(criteria_true);
        try s.objectField("false");
        try s.write(criteria_false);
        try s.endObject();
        try s.endObject();
    }
    try s.endObject();
    try s.endObject();
    return out.written();
}

fn malformed(reason: []const u8) ranking.RankOutcome {
    return unavailable(reason);
}

/// Accepts a response only when: it is a JSON object naming `model` and
/// `answers`; `model` equals `requested_model` exactly; every `answers` entry
/// is an object with `"type": "noul"` and a numeric `noul` value. Anything
/// else, including a well-formed response about the wrong model, is a
/// sanitized `unavailable`, never a partial or guessed ranking.
/// `ranking.decide` separately re-validates every ordinal, duplicate, and
/// numeric range rule; this function only turns JSON into the generic
/// `RankAnswer` shape that check operates on.
fn parseResponse(arena: Allocator, requested_model: []const u8, body: []const u8) Allocator.Error!ranking.RankOutcome {
    const parsed = std.json.parseFromSlice(std.json.Value, arena, body, .{}) catch return malformed("response is not valid JSON");
    const root = switch (parsed.value) {
        .object => |object| object,
        else => return malformed("response is not a JSON object"),
    };
    const response_model = switch (root.get("model") orelse return malformed("response is missing \"model\"")) {
        .string => |value| value,
        else => return malformed("response \"model\" is not a string"),
    };
    if (!std.mem.eql(u8, response_model, requested_model)) {
        return unavailable("provider response model does not match the requested model");
    }
    const answers_object = switch (root.get("answers") orelse return malformed("response is missing \"answers\"")) {
        .object => |object| object,
        else => return malformed("response \"answers\" is not an object"),
    };

    var answers: std.ArrayList(ranking.RankAnswer) = .empty;
    var it = answers_object.iterator();
    while (it.next()) |entry| {
        const answer_object = switch (entry.value_ptr.*) {
            .object => |object| object,
            else => return malformed("an answer is not an object"),
        };
        const kind = switch (answer_object.get("type") orelse return malformed("an answer is missing \"type\"")) {
            .string => |value| value,
            else => return malformed("an answer \"type\" is not a string"),
        };
        if (!std.mem.eql(u8, kind, "noul")) return malformed("an answer's type is not \"noul\"");
        const probability: f64 = switch (answer_object.get("noul") orelse return malformed("a noul answer is missing \"noul\"")) {
            .float => |value| value,
            .integer => |value| @floatFromInt(value),
            else => return malformed("a \"noul\" value is not a number"),
        };
        try answers.append(arena, .{ .ordinal = entry.key_ptr.*, .probability = probability });
    }

    var input_tokens: ?u64 = null;
    var output_tokens: ?u64 = null;
    if (root.get("usage")) |usage_value| {
        if (usage_value == .object) {
            if (usage_value.object.get("input_tokens")) |v| {
                if (v == .integer and v.integer >= 0) input_tokens = @intCast(v.integer);
            }
            if (usage_value.object.get("output_tokens")) |v| {
                if (v == .integer and v.integer >= 0) output_tokens = @intCast(v.integer);
            }
        }
    }

    return .{ .ranked = .{
        .answers = answers.items,
        .response_model = response_model,
        .input_tokens = input_tokens,
        .output_tokens = output_tokens,
    } };
}

const testing = std.testing;
const test_io = std.testing.io;
const jev_fixtures = @import("semidx_jev_fixtures");

/// The Stage 0 fixtures under `fixtures/jev/` live outside this module's
/// package path, so they are read at runtime through a build option instead
/// of `@embedFile`.
fn readFixture(arena: Allocator, comptime name: []const u8) ![]const u8 {
    const path = try std.fs.path.join(arena, &.{ jev_fixtures.dir, name });
    return std.Io.Dir.cwd().readFileAlloc(test_io, path, arena, .limited(1 << 20));
}

fn twoSentCards() [2]ranking.Card {
    return .{
        .{ .ordinal = "candidate_0", .role = "method" },
        .{ .ordinal = "candidate_1", .role = "class" },
    };
}

test "buildRequestBody embeds the state JSON verbatim and needs no candidates for an empty request" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const body = try buildRequestBody(arena, "{}", "jev-1.13.0", &.{});
    var parsed = try std.json.parseFromSlice(std.json.Value, arena, body, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("jev-1.13.0", parsed.value.object.get("model").?.string);
    try testing.expectEqual(@as(usize, 0), parsed.value.object.get("questions").?.object.count());
}

test "buildRequestBody emits one noul question per sent candidate with the fixed rubric" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cards = twoSentCards();

    const body = try buildRequestBody(arena, "{\"query\":\"q\",\"candidates\":{}}", "jev-1.13.0", &cards);
    var parsed = try std.json.parseFromSlice(std.json.Value, arena, body, .{});
    defer parsed.deinit();
    const questions = parsed.value.object.get("questions").?.object;
    try testing.expectEqual(@as(usize, 2), questions.count());
    const q0 = questions.get("candidate_0").?.object;
    try testing.expectEqualStrings("noul", q0.get("type").?.string);
    try testing.expectEqualStrings(instructions, q0.get("instructions").?.string);
    try testing.expectEqualStrings(criteria_true, q0.get("criteria").?.object.get("true").?.string);
    try testing.expectEqualStrings(criteria_false, q0.get("criteria").?.object.get("false").?.string);
}

test "parseResponse accepts the committed valid response fixture" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const body = try readFixture(arena, "response_valid.json");

    const outcome = try parseResponse(arena, "jev-1.13.0", body);
    const ranked = outcome.ranked;
    try testing.expectEqualStrings("jev-1.13.0", ranked.response_model.?);
    try testing.expectEqual(@as(usize, 2), ranked.answers.len);
    try testing.expectEqual(@as(u64, 341), ranked.input_tokens.?);
    try testing.expectEqual(@as(u64, 24), ranked.output_tokens.?);
}

test "parseResponse passes an incomplete answer set through unchanged; decide catches the gap" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const body = try readFixture(arena, "response_missing_answer.json");

    // The fixture answers only candidate_0; parseResponse does not know how
    // many candidates were sent, so it faithfully reports one answer. The
    // "every sent candidate answered" rule lives in ranking.decide, tested
    // against exactly this case in ranking.zig.
    const outcome = try parseResponse(arena, "jev-1.13.0", body);
    try testing.expectEqual(@as(usize, 1), outcome.ranked.answers.len);
}

test "parseResponse passes an extra answer through unchanged; decide catches the unknown ordinal" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const body = try readFixture(arena, "response_duplicate_or_unknown_answer.json");
    const outcome = try parseResponse(arena, "jev-1.13.0", body);
    try testing.expectEqual(@as(usize, 3), outcome.ranked.answers.len);
}

test "parseResponse rejects the wrong-type fixture" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const body = try readFixture(arena, "response_wrong_type.json");
    const outcome = try parseResponse(arena, "jev-1.13.0", body);
    try testing.expect(outcome == .unavailable);
}

test "parseResponse leaves range/finiteness checks to ranking.decide for the out-of-range fixture" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const body = try readFixture(arena, "response_out_of_range.json");
    const outcome = try parseResponse(arena, "jev-1.13.0", body);
    try testing.expectEqual(@as(usize, 2), outcome.ranked.answers.len);
}

test "parseResponse rejects the non-finite fixture itself, before ranking.decide ever sees it" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const body = try readFixture(arena, "response_non_finite.json");
    // `1e400` overflows f64 range, so Zig's own JSON parser represents it as
    // `.number_string` rather than `.float`; this function only trusts
    // `.float`/`.integer`, so the whole response is rejected here rather than
    // reaching ranking.decide's separate finite/range check. Both layers
    // guard the same rule; this fixture happens to be caught by this one.
    const outcome = try parseResponse(arena, "jev-1.13.0", body);
    try testing.expect(outcome == .unavailable);
}

test "parseResponse rejects the model-mismatch fixture even though every answer is otherwise valid" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const body = try readFixture(arena, "response_model_mismatch.json");
    const outcome = try parseResponse(arena, "jev-1.13.0", body);
    try testing.expect(outcome == .unavailable);
    try testing.expectEqualStrings("provider response model does not match the requested model", outcome.unavailable.reason);
}

test "sanitizeTransportError never echoes the underlying error's dynamic detail" {
    try testing.expectEqualStrings("could not reach the provider", sanitizeTransportError(error.ConnectionRefused));
    try testing.expectEqualStrings("provider request failed", sanitizeTransportError(error.SomethingUnexpected));
}
