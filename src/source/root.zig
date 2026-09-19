//! Source ingestion: finding the units a graph is built over.
//!
//! This module owns the only filesystem access in the ingestion path and the
//! only place a file name decides a language. It depends on `core/model` for
//! value vocabulary — `Language`, `DiagnosticKind` — and on nothing else in the
//! core. Nothing in the core depends on it.

pub const languages = @import("languages.zig");
pub const scan = @import("scan.zig");
pub const discovery = @import("discovery.zig");
pub const registry = @import("registry.zig");

pub const SourceScan = scan.SourceScan;
pub const ScannedUnit = scan.ScannedUnit;
pub const ScanDiagnostic = scan.ScanDiagnostic;
pub const Budgets = scan.Budgets;
pub const Options = scan.Options;
pub const ContentId = scan.ContentId;
pub const contentId = scan.contentId;
pub const languageForPath = languages.forPath;

test {
    _ = languages;
    _ = scan;
    _ = discovery;
    _ = registry;
}
