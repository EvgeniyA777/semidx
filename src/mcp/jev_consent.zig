//! Startup validation for the optional Jev ranking projection's outbound
//! consent ([ADR 013](../../docs/adr/013_optional_jev_ranking_projection.md)
//! D2). Pure: no environment or network access happens here. The caller
//! supplies the raw flag values and whether the secret environment variable
//! was present and non-empty; this module only says whether that is a
//! complete, valid consent or names the first violation, in a fixed order, so
//! the same input always produces the same diagnostic. No message here
//! includes a secret value: there is nothing to redact because the secret's
//! value never reaches this module, only its presence.

const std = @import("std");

pub const Categories = struct {
    query_text: bool = false,
    graph_metadata: bool = false,

    pub fn isComplete(self: Categories) bool {
        return self.query_text and self.graph_metadata;
    }
};

/// A complete, validated consent. Never carries the secret: presence was
/// checked by the caller and is not part of this record.
pub const Consent = struct {
    endpoint: []const u8,
    /// `endpoint` up to and excluding its path: `scheme://host[:port]`. Safe
    /// to log; the consented destination itself, not a query result.
    origin: []const u8,
    model: []const u8,
    categories: Categories,
};

pub const ValidationError = error{
    MissingEndpoint,
    MissingModel,
    MissingSend,
    MissingKey,
    EndpointNotHttps,
    EndpointHasCredentials,
    EndpointHasQueryOrFragment,
    EndpointMalformed,
    ModelIsMovingAlias,
    ModelNotVersioned,
    SendUnknownCategory,
    SendDuplicateCategory,
    SendIncomplete,
};

/// A message naming the offending item, safe to log or print: never a secret
/// value, never the operator's raw input, only which required item was
/// missing or invalid.
pub fn describe(err: ValidationError) []const u8 {
    return switch (err) {
        error.MissingEndpoint => "--jev-endpoint is required when --enable-jev-ranking is set",
        error.MissingModel => "--jev-model is required when --enable-jev-ranking is set",
        error.MissingSend => "--jev-send is required when --enable-jev-ranking is set",
        error.MissingKey => "TYPESAFE_API_KEY must be set when --enable-jev-ranking is set",
        error.EndpointNotHttps => "--jev-endpoint must be an https:// URL",
        error.EndpointHasCredentials => "--jev-endpoint must not contain userinfo credentials",
        error.EndpointHasQueryOrFragment => "--jev-endpoint must not contain a query or fragment",
        error.EndpointMalformed => "--jev-endpoint is not a valid URL",
        error.ModelIsMovingAlias => "--jev-model must be a versioned model id, not a moving alias such as jev-latest or jev-preview",
        error.ModelNotVersioned => "--jev-model must be a versioned id in the form jev-<major>.<minor>.<patch>",
        error.SendUnknownCategory => "--jev-send lists an unknown data category; only query-text and graph-metadata are accepted",
        error.SendDuplicateCategory => "--jev-send lists the same data category more than once",
        error.SendIncomplete => "--jev-send must list exactly both query-text and graph-metadata",
    };
}

fn validateEndpoint(raw: []const u8) ValidationError!void {
    const uri = std.Uri.parse(raw) catch return error.EndpointMalformed;
    if (!std.ascii.eqlIgnoreCase(uri.scheme, "https")) return error.EndpointNotHttps;
    if (uri.user != null or uri.password != null) return error.EndpointHasCredentials;
    if (uri.query != null or uri.fragment != null) return error.EndpointHasQueryOrFragment;
}

/// `endpoint`, which `validateEndpoint` already accepted, up to and excluding
/// its path.
fn originOf(endpoint: []const u8) []const u8 {
    const scheme_sep = "://";
    const scheme_end = std.mem.indexOf(u8, endpoint, scheme_sep).? + scheme_sep.len;
    const rest = endpoint[scheme_end..];
    const path_start = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
    return endpoint[0 .. scheme_end + path_start];
}

fn isVersionedJevModel(raw: []const u8) bool {
    const prefix = "jev-";
    if (!std.mem.startsWith(u8, raw, prefix)) return false;
    var rest = raw[prefix.len..];
    var groups: u8 = 0;
    while (true) {
        const sep = std.mem.indexOfScalar(u8, rest, '.');
        const part = if (sep) |i| rest[0..i] else rest;
        if (part.len == 0) return false;
        for (part) |c| {
            if (!std.ascii.isDigit(c)) return false;
        }
        groups += 1;
        if (sep) |i| rest = rest[i + 1 ..] else break;
    }
    return groups == 3;
}

fn validateModel(raw: []const u8) ValidationError!void {
    if (std.mem.eql(u8, raw, "jev-latest") or std.mem.eql(u8, raw, "jev-preview")) {
        return error.ModelIsMovingAlias;
    }
    if (!isVersionedJevModel(raw)) return error.ModelNotVersioned;
}

fn validateCategories(raw: []const u8) ValidationError!Categories {
    var categories: Categories = .{};
    var it = std.mem.splitScalar(u8, raw, ',');
    while (it.next()) |token| {
        if (std.mem.eql(u8, token, "query-text")) {
            if (categories.query_text) return error.SendDuplicateCategory;
            categories.query_text = true;
        } else if (std.mem.eql(u8, token, "graph-metadata")) {
            if (categories.graph_metadata) return error.SendDuplicateCategory;
            categories.graph_metadata = true;
        } else {
            return error.SendUnknownCategory;
        }
    }
    if (!categories.isComplete()) return error.SendIncomplete;
    return categories;
}

/// Validates a complete consent given the raw flag strings (empty means the
/// flag was not supplied) and whether the secret environment variable was
/// present and non-empty. Checks in a fixed order: endpoint, model, send,
/// then key, so the same incomplete input always names the same first
/// violation.
pub fn validate(endpoint_raw: []const u8, model_raw: []const u8, send_raw: []const u8, key_present: bool) ValidationError!Consent {
    if (endpoint_raw.len == 0) return error.MissingEndpoint;
    try validateEndpoint(endpoint_raw);
    if (model_raw.len == 0) return error.MissingModel;
    try validateModel(model_raw);
    if (send_raw.len == 0) return error.MissingSend;
    const categories = try validateCategories(send_raw);
    if (!key_present) return error.MissingKey;
    return .{ .endpoint = endpoint_raw, .origin = originOf(endpoint_raw), .model = model_raw, .categories = categories };
}

const testing = std.testing;

test "validate accepts the documented example" {
    const consent = try validate("https://api.typesafe.ai/v1/systemone", "jev-1.13.0", "query-text,graph-metadata", true);
    try testing.expect(consent.categories.isComplete());
    try testing.expectEqualStrings("https://api.typesafe.ai", consent.origin);
}

test "validate normalizes category order" {
    const consent = try validate("https://api.typesafe.ai/v1/systemone", "jev-1.13.0", "graph-metadata,query-text", true);
    try testing.expect(consent.categories.isComplete());
}

test "validate rejects a missing endpoint" {
    try testing.expectError(error.MissingEndpoint, validate("", "jev-1.13.0", "query-text,graph-metadata", true));
}

test "validate rejects a missing model" {
    try testing.expectError(error.MissingModel, validate("https://api.typesafe.ai/v1/systemone", "", "query-text,graph-metadata", true));
}

test "validate rejects a missing send" {
    try testing.expectError(error.MissingSend, validate("https://api.typesafe.ai/v1/systemone", "jev-1.13.0", "", true));
}

test "validate rejects a missing key" {
    try testing.expectError(error.MissingKey, validate("https://api.typesafe.ai/v1/systemone", "jev-1.13.0", "query-text,graph-metadata", false));
}

test "validate rejects http" {
    try testing.expectError(error.EndpointNotHttps, validate("http://api.typesafe.ai/v1/systemone", "jev-1.13.0", "query-text,graph-metadata", true));
}

test "validate rejects a malformed endpoint" {
    try testing.expectError(error.EndpointMalformed, validate(":://not a url", "jev-1.13.0", "query-text,graph-metadata", true));
}

test "validate rejects credentials in the endpoint" {
    try testing.expectError(error.EndpointHasCredentials, validate("https://user:pass@api.typesafe.ai/v1/systemone", "jev-1.13.0", "query-text,graph-metadata", true));
}

test "validate rejects a query in the endpoint" {
    try testing.expectError(error.EndpointHasQueryOrFragment, validate("https://api.typesafe.ai/v1/systemone?x=1", "jev-1.13.0", "query-text,graph-metadata", true));
}

test "validate rejects a fragment in the endpoint" {
    try testing.expectError(error.EndpointHasQueryOrFragment, validate("https://api.typesafe.ai/v1/systemone#frag", "jev-1.13.0", "query-text,graph-metadata", true));
}

test "validate rejects the jev-latest alias" {
    try testing.expectError(error.ModelIsMovingAlias, validate("https://api.typesafe.ai/v1/systemone", "jev-latest", "query-text,graph-metadata", true));
}

test "validate rejects the jev-preview alias" {
    try testing.expectError(error.ModelIsMovingAlias, validate("https://api.typesafe.ai/v1/systemone", "jev-preview", "query-text,graph-metadata", true));
}

test "validate rejects a bare model name" {
    try testing.expectError(error.ModelNotVersioned, validate("https://api.typesafe.ai/v1/systemone", "jev", "query-text,graph-metadata", true));
}

test "validate rejects a two-part version" {
    try testing.expectError(error.ModelNotVersioned, validate("https://api.typesafe.ai/v1/systemone", "jev-1.13", "query-text,graph-metadata", true));
}

test "validate rejects an unknown category" {
    try testing.expectError(error.SendUnknownCategory, validate("https://api.typesafe.ai/v1/systemone", "jev-1.13.0", "query-text,source-text", true));
}

test "validate rejects a duplicated category" {
    try testing.expectError(error.SendDuplicateCategory, validate("https://api.typesafe.ai/v1/systemone", "jev-1.13.0", "query-text,query-text", true));
}

test "validate rejects a partial category set" {
    try testing.expectError(error.SendIncomplete, validate("https://api.typesafe.ai/v1/systemone", "jev-1.13.0", "query-text", true));
}
