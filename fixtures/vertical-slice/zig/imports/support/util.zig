//! A provider reached through a normalized relative path. It imports its
//! importer back, so the two units depend on each other.

const session = @import("../session.zig");

pub fn clean() void {
    _ = session.run("");
}
