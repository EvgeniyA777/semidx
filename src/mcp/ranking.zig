//! The Jev ranking projection's provider-agnostic policy
//! ([ADR 013](../../docs/adr/013_optional_jev_ranking_projection.md),
//! [Plan 015](../../docs/plans/015_optional_jev_ranking_projection.md)).
//!
//! This module knows nothing about the graph, HTTP, or MCP: it only knows how
//! to serialize a closed candidate card, validate and sort a provider's
//! answer, and produce a visible `unavailable` fallback when a provider is
//! absent or its answer cannot be trusted. `src/mcp/tools.zig` owns candidate
//! selection from the snapshot and the result rendering; the eventual Jev HTTP
//! adapter (Plan 015 Stage 3) is the only other implementation of `Provider`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Stringify = std.json.Stringify;
const Writer = std.Io.Writer;

/// The first slice ranks this many candidates by default...
pub const default_candidates: u32 = 20;
/// ...and accepts at most this many.
pub const max_candidates: u32 = 32;
/// The outbound `state` JSON is bounded independently of the MCP response
/// budget (ADR 013 D3). Whole cards are appended until the next one would
/// cross this ceiling.
pub const default_state_ceiling_bytes: usize = 32_000;
/// The complete serialized HTTP request Stage 3 sends is capped here...
pub const request_ceiling_bytes: usize = 64 * 1024;
/// ...and the provider response here. Both are recorded now, as named
/// runtime constants, even though no HTTP implementation exists until Stage 3.
pub const response_ceiling_bytes: usize = 256 * 1024;
/// The adapter's one overall deadline (ADR 013 D5), used from Stage 3 on.
pub const provider_deadline_ms: u64 = 2_000;

/// A closed, minimal candidate card (ADR 013 D3). Every field here is either
/// present or explicitly `null`; nothing else may be added without a revised
/// decision. Absent on purpose: process-local entity/unit ids, byte ranges,
/// evidence text, source bodies, the absolute repository root, VCS metadata,
/// and environment values.
pub const Card = struct {
    /// The request-local key this card is filed under in the outbound state,
    /// e.g. `"candidate_3"`. Never a process-local graph id.
    ordinal: []const u8,
    language: ?[]const u8 = null,
    role: []const u8,
    name: ?[]const u8 = null,
    container_path: []const []const u8 = &.{},
    source_unit_path: ?[]const u8 = null,
    relationship_kind: ?[]const u8 = null,
    relationship_direction: ?[]const u8 = null,
    /// The recorded resolution category alone ("fact", "unresolved",
    /// "approximate"), never the producer's explanation or confidence.
    resolution: ?[]const u8 = null,
    freshness: ?[]const u8 = null,
    /// The producer's name alone, never its version.
    producer: ?[]const u8 = null,
    /// Diagnostic categories relevant to the candidate's unit, deduplicated.
    /// Never a diagnostic's message.
    diagnostics: []const []const u8 = &.{},
};

/// The exact, closed field set `writeCard` may ever emit. A test compares a
/// serialized card's key set against this list directly, so an accidental new
/// field fails the test even if no one wrote a check for that field's name.
pub const card_fields = [_][]const u8{
    "language",         "role",         "name",       "container_path",
    "source_unit_path", "relationship", "resolution", "freshness",
    "producer",         "diagnostics",
};

pub fn writeCard(s: *Stringify, card: Card) Writer.Error!void {
    try s.beginObject();
    try s.objectField("language");
    if (card.language) |value| try s.write(value) else try s.write(null);
    try s.objectField("role");
    try s.write(card.role);
    try s.objectField("name");
    if (card.name) |value| try s.write(value) else try s.write(null);
    try s.objectField("container_path");
    try s.write(card.container_path);
    try s.objectField("source_unit_path");
    if (card.source_unit_path) |value| try s.write(value) else try s.write(null);
    try s.objectField("relationship");
    if (card.relationship_kind) |kind| {
        try s.beginObject();
        try s.objectField("kind");
        try s.write(kind);
        try s.objectField("direction");
        try s.write(card.relationship_direction.?);
        try s.endObject();
    } else try s.write(null);
    try s.objectField("resolution");
    if (card.resolution) |value| try s.write(value) else try s.write(null);
    try s.objectField("freshness");
    if (card.freshness) |value| try s.write(value) else try s.write(null);
    try s.objectField("producer");
    if (card.producer) |value| try s.write(value) else try s.write(null);
    try s.objectField("diagnostics");
    try s.write(card.diagnostics);
    try s.endObject();
}

pub const SerializedState = struct {
    /// `{"query": <query>, "candidates": {"candidate_0": <card>, ...}}`.
    json: []const u8,
    sent: usize,
    omitted: usize,
    truncated: bool,
};

pub const SerializeError = error{
    /// The state does not fit `ceiling_bytes` even with zero candidates: the
    /// query itself is too large. ADR 013 D3: reject locally, do not truncate
    /// the query, and never attempt to send it.
    QueryTooLarge,
} || Allocator.Error || Writer.Error;

/// Builds the outbound `state` JSON, appending whole cards from `cards[0..]`
/// in order until the next one would cross `ceiling_bytes`, then stopping.
/// `cards` is usually the full candidate list; only the first `sent` of them
/// were actually included.
pub fn serializeState(arena: Allocator, query: []const u8, cards: []const Card, ceiling_bytes: usize) SerializeError!SerializedState {
    var query_buf: Writer.Allocating = .init(arena);
    var query_s: Stringify = .{ .writer = &query_buf.writer };
    try query_s.write(query);
    const query_json = query_buf.written();

    const header = try std.fmt.allocPrint(arena, "{{\"query\":{s},\"candidates\":{{", .{query_json});
    const footer = "}}";
    if (header.len + footer.len > ceiling_bytes) return error.QueryTooLarge;

    var out: Writer.Allocating = .init(arena);
    try out.writer.writeAll(header);
    var running: usize = header.len + footer.len;
    var sent: usize = 0;
    for (cards, 0..) |card, i| {
        var card_buf: Writer.Allocating = .init(arena);
        var card_s: Stringify = .{ .writer = &card_buf.writer };
        try writeCard(&card_s, card);
        const prefix = if (i == 0) "" else ",";
        const fragment = try std.fmt.allocPrint(arena, "{s}\"{s}\":{s}", .{ prefix, card.ordinal, card_buf.written() });
        if (running + fragment.len > ceiling_bytes) break;
        try out.writer.writeAll(fragment);
        running += fragment.len;
        sent += 1;
    }
    try out.writer.writeAll(footer);
    return .{
        .json = out.written(),
        .sent = sent,
        .omitted = cards.len - sent,
        .truncated = sent < cards.len,
    };
}

pub const RankAnswer = struct {
    /// Must equal one `Card.ordinal` this request sent.
    ordinal: []const u8,
    probability: f64,
};

pub const RankOutcome = union(enum) {
    ranked: struct {
        answers: []const RankAnswer,
        response_model: ?[]const u8 = null,
        input_tokens: ?u64 = null,
        output_tokens: ?u64 = null,
    },
    /// A sanitized reason, safe to render: never a raw provider body, header,
    /// or secret.
    unavailable: struct { reason: []const u8 },
};

/// The narrow, provider-neutral contract (ADR 013 D4). `JevProvider` (Plan 015
/// Stage 3) and `FakeProvider` below are its only implementations.
pub const Provider = struct {
    /// Provenance recorded on every result, ranked or not.
    name: []const u8,
    requested_model: []const u8,
    ptr: *anyopaque,
    rankFn: *const fn (ptr: *anyopaque, arena: Allocator, query: []const u8, cards: []const Card) anyerror!RankOutcome,

    pub fn rank(self: Provider, arena: Allocator, query: []const u8, cards: []const Card) anyerror!RankOutcome {
        return self.rankFn(self.ptr, arena, query, cards);
    }
};

/// A deterministic, in-process stand-in for `JevProvider`, for tests that must
/// prove ordering, ties, truncation, and fallback without a network call.
pub const FakeProvider = struct {
    behavior: Behavior,

    pub const Behavior = union(enum) {
        /// One probability per card, in the same order as the cards the
        /// caller sends. Its length must equal the sent card count or the
        /// fake reports a mismatch as an ordinary invalid response, the same
        /// way a real malformed reply would.
        scores: []const f64,
        /// Simulates timeout, rate limiting, or any other provider failure.
        unavailable: []const u8,
        /// Simulates a response naming an unexpected candidate ordinal.
        unknown_ordinal: void,
        /// Simulates a response missing one answer.
        missing_answer: void,
        /// Simulates a response with an out-of-range probability.
        out_of_range: void,
        /// Simulates a response whose model does not match what was
        /// requested; carried in `response_model` for the caller to check,
        /// since model-identity validation is Stage 3's HTTP adapter concern,
        /// not this policy's. Included here only so Stage 2 tests can prove
        /// the field is threaded through untouched.
        model_mismatch: []const u8,
    };

    pub fn provider(self: *FakeProvider) Provider {
        return .{ .name = "fake", .requested_model = "fake-1.0.0", .ptr = self, .rankFn = rankImpl };
    }

    fn rankImpl(ptr: *anyopaque, arena: Allocator, query: []const u8, cards: []const Card) anyerror!RankOutcome {
        _ = query;
        const self: *FakeProvider = @ptrCast(@alignCast(ptr));
        switch (self.behavior) {
            .unavailable => |reason| return .{ .unavailable = .{ .reason = reason } },
            .scores => |scores| {
                var answers = try arena.alloc(RankAnswer, cards.len);
                const n = @min(scores.len, cards.len);
                for (cards[0..n], scores[0..n], 0..) |card, score, i| {
                    answers[i] = .{ .ordinal = card.ordinal, .probability = score };
                }
                return .{ .ranked = .{ .answers = answers[0..n] } };
            },
            .unknown_ordinal => {
                var answers = try arena.alloc(RankAnswer, cards.len);
                for (cards, 0..) |card, i| answers[i] = .{ .ordinal = card.ordinal, .probability = 0.5 };
                if (answers.len != 0) answers[0].ordinal = "candidate_does_not_exist";
                return .{ .ranked = .{ .answers = answers } };
            },
            .missing_answer => {
                const n = if (cards.len == 0) 0 else cards.len - 1;
                var answers = try arena.alloc(RankAnswer, n);
                for (cards[0..n], 0..) |card, i| answers[i] = .{ .ordinal = card.ordinal, .probability = 0.5 };
                return .{ .ranked = .{ .answers = answers } };
            },
            .out_of_range => {
                var answers = try arena.alloc(RankAnswer, cards.len);
                for (cards, 0..) |card, i| answers[i] = .{ .ordinal = card.ordinal, .probability = 1.4 };
                return .{ .ranked = .{ .answers = answers } };
            },
            .model_mismatch => |model| {
                var answers = try arena.alloc(RankAnswer, cards.len);
                for (cards, 0..) |card, i| answers[i] = .{ .ordinal = card.ordinal, .probability = 0.5 };
                return .{ .ranked = .{ .answers = answers, .response_model = model } };
            },
        }
    }
};

/// The outcome of running a provider (or not having one) over exactly the
/// cards that were actually sent (`SerializedState.sent`), sized to that same
/// length. `tools.rankContext` merges this back onto the full candidate list,
/// which may be longer when the state ceiling truncated the outbound cards.
pub const Decision = struct {
    status: enum { ranked, unavailable },
    provider: ?[]const u8 = null,
    requested_model: ?[]const u8 = null,
    response_model: ?[]const u8 = null,
    input_tokens: ?u64 = null,
    output_tokens: ?u64 = null,
    reason: ?[]const u8 = null,
    /// Present only when `status == .ranked`; parallel to the sent cards.
    probabilities: []const f64 = &.{},
    /// Present only when `status == .ranked`; a permutation of
    /// `0..sent_cards.len`, descending by probability, ties broken by the
    /// original (ascending) index.
    order: []const usize = &.{},
};

fn unavailableDecision(reason: []const u8) Decision {
    return .{ .status = .unavailable, .reason = reason };
}

/// Runs `provider` (when present) over exactly `sent_cards` and validates its
/// answer against ADR 013 D4: one answer per sent ordinal, no unexpected
/// ordinal, no duplicate, every value finite in `[0, 1]`. Any violation, a
/// missing provider, or a provider error all collapse to the same visible
/// `unavailable` outcome; none of them ever fabricates a plausible-looking
/// ranking.
pub fn decide(arena: Allocator, provider: ?Provider, query: []const u8, sent_cards: []const Card) Allocator.Error!Decision {
    const active = provider orelse return unavailableDecision("no ranking provider is configured");
    const outcome = active.rank(arena, query, sent_cards) catch |err| {
        return unavailableDecision(try std.fmt.allocPrint(arena, "provider error: {t}", .{err}));
    };
    switch (outcome) {
        .unavailable => |u| return unavailableDecision(u.reason),
        .ranked => |ranked| {
            var probabilities = try arena.alloc(f64, sent_cards.len);
            var seen = try arena.alloc(bool, sent_cards.len);
            @memset(seen, false);
            for (ranked.answers) |answer| {
                const idx = indexOfOrdinal(sent_cards, answer.ordinal) orelse
                    return unavailableDecision("provider answered a candidate this request never sent");
                if (seen[idx]) return unavailableDecision("provider answered the same candidate twice");
                if (!std.math.isFinite(answer.probability) or answer.probability < 0.0 or answer.probability > 1.0) {
                    return unavailableDecision("provider returned a non-finite or out-of-range probability");
                }
                seen[idx] = true;
                probabilities[idx] = answer.probability;
            }
            for (seen) |was_seen| {
                if (!was_seen) return unavailableDecision("provider did not answer every candidate it was sent");
            }
            const order = try stableOrderByProbabilityDesc(arena, probabilities);
            return .{
                .status = .ranked,
                .provider = active.name,
                .requested_model = active.requested_model,
                .response_model = ranked.response_model,
                .input_tokens = ranked.input_tokens,
                .output_tokens = ranked.output_tokens,
                .probabilities = probabilities,
                .order = order,
            };
        },
    }
}

fn indexOfOrdinal(cards: []const Card, ordinal: []const u8) ?usize {
    for (cards, 0..) |card, i| {
        if (std.mem.eql(u8, card.ordinal, ordinal)) return i;
    }
    return null;
}

/// A permutation of `0..probabilities.len`, descending by probability, ties
/// broken by ascending original index. `probabilities.len` is at most
/// `max_candidates`, so a simple stable insertion sort is exact and fast
/// enough; no need for a general-purpose unstable sort here.
fn stableOrderByProbabilityDesc(arena: Allocator, probabilities: []const f64) Allocator.Error![]const usize {
    var order = try arena.alloc(usize, probabilities.len);
    for (order, 0..) |*slot, i| slot.* = i;
    var i: usize = 1;
    while (i < order.len) : (i += 1) {
        const key = order[i];
        var j = i;
        while (j > 0 and probabilities[order[j - 1]] < probabilities[key]) : (j -= 1) {
            order[j] = order[j - 1];
        }
        order[j] = key;
    }
    return order;
}

const testing = std.testing;

fn testCard(ordinal: []const u8) Card {
    return .{ .ordinal = ordinal, .role = "class" };
}

test "writeCard emits exactly the closed field set, nothing more or less" {
    var buf: Writer.Allocating = .init(testing.allocator);
    defer buf.deinit();
    var s: Stringify = .{ .writer = &buf.writer };
    try writeCard(&s, .{
        .ordinal = "candidate_0",
        .language = "java",
        .role = "class",
        .name = "Order",
        .container_path = &.{"com.storefront"},
        .source_unit_path = "src/Order.java",
        .relationship_kind = "calls",
        .relationship_direction = "incoming",
        .resolution = "fact",
        .freshness = "current",
        .producer = "frontend.java",
        .diagnostics = &.{"unsupported_construct"},
    });
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, buf.written(), .{});
    defer parsed.deinit();
    const object = parsed.value.object;
    try testing.expectEqual(card_fields.len, object.count());
    for (card_fields) |field| try testing.expect(object.contains(field));
    try testing.expect(object.get("relationship").?.object.contains("kind"));
    try testing.expect(object.get("relationship").?.object.contains("direction"));
    try testing.expectEqual(@as(usize, 2), object.get("relationship").?.object.count());
}

test "writeCard renders null for every absent optional field, including relationship" {
    var buf: Writer.Allocating = .init(testing.allocator);
    defer buf.deinit();
    var s: Stringify = .{ .writer = &buf.writer };
    try writeCard(&s, testCard("candidate_0"));
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, buf.written(), .{});
    defer parsed.deinit();
    const object = parsed.value.object;
    try testing.expect(object.get("language").? == .null);
    try testing.expect(object.get("name").? == .null);
    try testing.expect(object.get("source_unit_path").? == .null);
    try testing.expect(object.get("relationship").? == .null);
    try testing.expect(object.get("resolution").? == .null);
    try testing.expect(object.get("freshness").? == .null);
    try testing.expect(object.get("producer").? == .null);
    try testing.expectEqual(@as(usize, 0), object.get("container_path").?.array.items.len);
    try testing.expectEqual(@as(usize, 0), object.get("diagnostics").?.array.items.len);
}

test "serializeState fits every card under a generous ceiling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const cards = [_]Card{ testCard("candidate_0"), testCard("candidate_1"), testCard("candidate_2") };
    const state = try serializeState(arena.allocator(), "who calls X?", &cards, default_state_ceiling_bytes);
    try testing.expectEqual(@as(usize, 3), state.sent);
    try testing.expectEqual(@as(usize, 0), state.omitted);
    try testing.expect(!state.truncated);
    var parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), state.json, .{});
    try testing.expectEqualStrings("who calls X?", parsed.value.object.get("query").?.string);
    try testing.expectEqual(@as(usize, 3), parsed.value.object.get("candidates").?.object.count());
}

test "serializeState stops appending once the next whole card would cross the ceiling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const cards = [_]Card{ testCard("candidate_0"), testCard("candidate_1"), testCard("candidate_2") };
    // Big enough for the header/footer and exactly one small card, not two.
    var probe = try serializeState(arena.allocator(), "q", cards[0..1], 1_000_000);
    const one_card_len = probe.json.len;
    probe = try serializeState(arena.allocator(), "q", &cards, one_card_len + 5);
    try testing.expectEqual(@as(usize, 1), probe.sent);
    try testing.expectEqual(@as(usize, 2), probe.omitted);
    try testing.expect(probe.truncated);
}

test "serializeState rejects a query that alone does not fit, without an outbound attempt" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.QueryTooLarge, serializeState(arena.allocator(), "x" ** 100, &.{}, 10));
}

test "decide falls back to unavailable when no provider is configured" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const decision = try decide(arena.allocator(), null, "q", &.{});
    try testing.expect(decision.status == .unavailable);
    try testing.expect(decision.reason != null);
}

test "decide sorts validated probabilities descending, tying by original order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const cards = [_]Card{ testCard("candidate_0"), testCard("candidate_1"), testCard("candidate_2"), testCard("candidate_3") };
    var fake: FakeProvider = .{ .behavior = .{ .scores = &.{ 0.2, 0.9, 0.9, 0.1 } } };
    const decision = try decide(arena.allocator(), fake.provider(), "q", &cards);
    try testing.expect(decision.status == .ranked);
    // candidate_1 and candidate_2 tie at 0.9; candidate_1 (index 1) keeps the
    // earlier position over candidate_2 (index 2).
    try testing.expectEqualSlices(usize, &.{ 1, 2, 0, 3 }, decision.order);
}

test "decide rejects an answer naming a candidate that was never sent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const cards = [_]Card{testCard("candidate_0")};
    var fake: FakeProvider = .{ .behavior = .unknown_ordinal };
    const decision = try decide(arena.allocator(), fake.provider(), "q", &cards);
    try testing.expect(decision.status == .unavailable);
}

test "decide rejects a response missing an answer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const cards = [_]Card{ testCard("candidate_0"), testCard("candidate_1") };
    var fake: FakeProvider = .{ .behavior = .missing_answer };
    const decision = try decide(arena.allocator(), fake.provider(), "q", &cards);
    try testing.expect(decision.status == .unavailable);
}

test "decide rejects an out-of-range probability" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const cards = [_]Card{testCard("candidate_0")};
    var fake: FakeProvider = .{ .behavior = .out_of_range };
    const decision = try decide(arena.allocator(), fake.provider(), "q", &cards);
    try testing.expect(decision.status == .unavailable);
}

test "decide surfaces a simulated provider failure as unavailable with its reason" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const cards = [_]Card{testCard("candidate_0")};
    var fake: FakeProvider = .{ .behavior = .{ .unavailable = "simulated timeout" } };
    const decision = try decide(arena.allocator(), fake.provider(), "q", &cards);
    try testing.expect(decision.status == .unavailable);
    try testing.expectEqualStrings("simulated timeout", decision.reason.?);
}
