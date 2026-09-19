//! The one place a file's name decides which language it is presented as.
//!
//! Discovery and any consumer asking "what language is this path" read the same
//! table. A second table would drift from this one, and the first symptom would
//! be a file that is a source unit to one caller and invisible to another.

const std = @import("std");
const core = @import("semidx_core");

const model = core.model;

pub const Mapping = struct {
    extension: []const u8,
    language: model.Language,
};

/// Fixture coverage, not a supported-language roster. A language appears here
/// when a frontend in this build can be asked to analyze it at all.
pub const mappings = [_]Mapping{
    .{ .extension = ".java", .language = .java },
    .{ .extension = ".clj", .language = .clojure },
    .{ .extension = ".cljc", .language = .clojure },
    .{ .extension = ".zig", .language = .zig },
};

/// The language a path is presented to analysis as, or null when no frontend in
/// this build covers it. Null is "not a source unit here", never "empty".
pub fn forPath(path: []const u8) ?model.Language {
    for (mappings) |mapping| {
        if (std.mem.endsWith(u8, path, mapping.extension)) return mapping.language;
    }
    return null;
}

const testing = std.testing;

test "a path maps to the language its frontend covers" {
    try testing.expectEqual(model.Language.java, forPath("src/demo/Greeter.java").?);
    try testing.expectEqual(model.Language.clojure, forPath("src/demo/greeter.clj").?);
    try testing.expectEqual(model.Language.clojure, forPath("src/demo/greeter.cljc").?);
    try testing.expectEqual(model.Language.zig, forPath("src/core/graph.zig").?);
    try testing.expectEqual(model.Language.zig, forPath("build.zig").?);
}

test "an uncovered path is not a source unit" {
    try testing.expect(forPath("README.md") == null);
    try testing.expect(forPath("build.zig.zon") == null);
    try testing.expect(forPath("Greeter.java.bak") == null);
    try testing.expect(forPath("noextension") == null);
}
