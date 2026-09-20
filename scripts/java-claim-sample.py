#!/usr/bin/env python3
"""Sample Java definitions from a semidx index and classify their outgoing claims.

This is a developer measurement tool, not a build lane and not a conformance
check. No `zig build` step depends on it. It exists so that an external Java
measurement can be repeated by someone who has only this repository and a clone
of the measured project — the gap
`docs/followups/017_plan_012_external_evidence_reproducibility.md` records.

It drives the real MCP stdio server over the `2026-07-28` protocol, one request
and response per line, and asks it only what a consumer could ask.

The sample is reproducible from the seed alone, without this script:

    key  = "<unit path>\\n<start line>\\n<role>\\n<name>"    for every definition
    rank = sha256(seed + "\\n" + key)                       as lowercase hex
    the sample is the first `size` definitions ordered by (rank, key)

Nothing about that depends on a language runtime's random number generator, so
a reimplementation in any language draws the same definitions. The seed is a
string, compared as bytes.

Every unresolved claim is put in exactly one reason family, and a claim that
matches none is counted under `unclassified` and printed. A decomposition whose
parts do not sum to its whole is a decomposition with a family missing from it,
which is the failure this tool is meant to make impossible rather than
unlikely.

Usage:

    scripts/java-claim-sample.py --root /path/to/clone
    scripts/java-claim-sample.py --root /path/to/clone --seed 20260918 --size 1200
    scripts/java-claim-sample.py --root . --language zig --json report.json

Build the server first: `zig build -Doptimize=ReleaseFast`.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys

PROTOCOL = "2026-07-28"

# Ordered most specific first. A claim takes the first family whose fragment it
# contains, so a fragment that is a substring of another must come after it.
#
# The fragments are the frontend's own words. When a reason is reworded in
# `src/frontends/java.zig`, its family stops matching and the claim lands in
# `unclassified`, which is visible rather than silent.
CALL_FAMILIES = [
    # Qualified by something that is not a simple name.
    ("receiver_not_simple_name", "qualified by a receiver this frontend does not resolve"),
    ("nested_class_body", "class body declared in the method"),
    # A simple name something else claims.
    ("receiver_bound", "is declared here as a binding, so it is read as a value"),
    ("on_demand_static_import", "imports static members on demand"),
    ("enclosing_supertypes", "a field it may inherit"),
    ("receiver_reaches_no_class", "the receiver is not read as a class"),
    # The receiver is a class; the target is not established.
    ("target_supertypes", "declares supertypes, so a method of this name it may inherit"),
    ("target_supertypes_unknown", "carries no record of whether it declares supertypes"),
    ("target_shape_not_read", "whose current shape this analysis did not read"),
    ("target_no_method", "declares no method of this name"),
    ("target_overloaded", "methods of this name, and overloads are not resolved"),
    ("target_not_static", "is not static, so naming it through the class"),
    ("target_static_unrecorded", "carries no record of whether it is `static`"),
    ("target_inaccessible", "outside the access this frontend resolves across classes"),
    # Unqualified invocations, which this rule never touched.
    ("unqualified_no_method", "no method of this name is declared in the enclosing class"),
    ("unqualified_overloaded", "methods of this name are declared in the enclosing class"),
    ("unqualified_supertypes", "a method of this name it may inherit could be the target"),
]


class Server:
    """One `semidx-mcp` process, spoken to over stdio."""

    def __init__(self, binary, root, max_response_bytes):
        self.max_response_bytes = max_response_bytes
        self.next_id = 0
        self.process = subprocess.Popen(
            [binary, "--root", root],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

    def close(self):
        if self.process.stdin:
            self.process.stdin.close()
        self.process.wait(timeout=30)

    def call(self, tool, arguments, budgeted=True):
        """One `tools/call`. `budgeted` is false for tools that take no budget."""
        self.next_id += 1
        arguments = dict(arguments)
        if budgeted:
            arguments.setdefault("max_response_bytes", self.max_response_bytes)
        request = {
            "jsonrpc": "2.0",
            "id": self.next_id,
            "method": "tools/call",
            "params": {
                "_meta": {
                    "io.modelcontextprotocol/protocolVersion": PROTOCOL,
                    "io.modelcontextprotocol/clientCapabilities": {},
                },
                "name": tool,
                "arguments": arguments,
            },
        }
        self.process.stdin.write(json.dumps(request) + "\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline()
        if not line:
            raise SystemExit(
                "semidx-mcp closed the stream; stderr:\n" + self.process.stderr.read()
            )
        response = json.loads(line)
        if "error" in response:
            raise SystemExit("%s failed: %s" % (tool, json.dumps(response["error"])))
        result = response["result"]
        if result.get("isError"):
            raise SystemExit("%s returned an error result: %s" % (tool, json.dumps(result)))
        return result["structuredContent"]


def enumerate_definitions(server, language, roles):
    """Every current definition of `language` in one of `roles`, in index order."""
    found = []
    for role in roles:
        cursor = None
        while True:
            arguments = {"language": language, "role": role, "limit": 500}
            if cursor is not None:
                arguments["cursor"] = cursor
            page = server.call("semidx_find_definitions", arguments)
            for definition in page.get("definitions", []):
                evidence = definition.get("evidence") or {}
                unit = evidence.get("unit") or {}
                found.append(
                    {
                        "id": definition["id"],
                        "path": unit.get("path", ""),
                        "line": (evidence.get("range") or {}).get("start_line", 0),
                        "role": definition.get("role", ""),
                        "name": definition.get("name", ""),
                    }
                )
            cursor = page.get("next_cursor")
            if not cursor:
                break
    return found


def sample(definitions, seed, size):
    """The reproducible sample this file's docstring specifies."""
    ranked = []
    for definition in definitions:
        key = "%s\n%d\n%s\n%s" % (
            definition["path"],
            definition["line"],
            definition["role"],
            definition["name"],
        )
        rank = hashlib.sha256(("%s\n%s" % (seed, key)).encode("utf-8")).hexdigest()
        ranked.append((rank, key, definition))
    ranked.sort(key=lambda entry: (entry[0], entry[1]))
    return [entry[2] for entry in ranked[:size]]


def outgoing_claims(server, entity_id):
    """Every outgoing relationship of one definition, following the cursor."""
    claims = []
    cursor = None
    while True:
        arguments = {
            "entity_id": entity_id,
            "direction": "outgoing",
            "detail": "full",
            "limit": 200,
        }
        if cursor is not None:
            arguments["cursor"] = cursor
        page = server.call("semidx_references", arguments)
        claims.extend(page.get("relationships", []))
        cursor = page.get("next_cursor")
        if not cursor:
            break
    return claims


def classify(explanation):
    for family, fragment in CALL_FAMILIES:
        if fragment in explanation:
            return family
    return "unclassified"


def measure(server, definitions):
    totals = {}
    families = {}
    unclassified = {}
    for definition in definitions:
        for claim in outgoing_claims(server, definition["id"]):
            kind = claim.get("kind", "?")
            resolution = (claim.get("resolution") or {}).get("category", "?")
            totals[(kind, resolution)] = totals.get((kind, resolution), 0) + 1
            if kind != "calls" or resolution != "unresolved":
                continue
            explanation = (claim.get("resolution") or {}).get("explanation", "")
            family = classify(explanation)
            families[family] = families.get(family, 0) + 1
            if family == "unclassified":
                unclassified[explanation] = unclassified.get(explanation, 0) + 1
    return totals, families, unclassified


def report(args, health, population, sampled, totals, families, unclassified):
    lines = []
    lines.append("root:        %s" % args.root)
    lines.append("language:    %s" % args.language)
    lines.append("seed:        %s" % args.seed)
    lines.append("population:  %d definitions" % population)
    lines.append("sample:      %d definitions" % len(sampled))
    lines.append("revision:    %s" % (health.get("snapshot") or {}).get("revision", "?"))
    lines.append("")

    claims = sum(totals.values())
    lines.append("Sampled outgoing claims: %d" % claims)
    lines.append("")
    lines.append("%-14s %-12s %8s" % ("kind", "resolution", "count"))
    for (kind, resolution), count in sorted(totals.items()):
        lines.append("%-14s %-12s %8d" % (kind, resolution, count))
    lines.append("")

    unresolved_calls = totals.get(("calls", "unresolved"), 0)
    lines.append("Unresolved `calls` by reason family: %d" % unresolved_calls)
    lines.append("")
    lines.append("%-28s %8s" % ("family", "count"))
    for family, _ in CALL_FAMILIES:
        lines.append("%-28s %8d" % (family, families.get(family, 0)))
    lines.append("%-28s %8d" % ("unclassified", families.get("unclassified", 0)))
    lines.append("")

    counted = sum(families.values())
    if counted == unresolved_calls:
        lines.append("The families sum to the whole: %d = %d." % (counted, unresolved_calls))
    else:
        lines.append(
            "MISMATCH: families sum to %d, unresolved calls are %d."
            % (counted, unresolved_calls)
        )
    if unclassified:
        lines.append("")
        lines.append("Explanations no family matched:")
        for explanation, count in sorted(unclassified.items(), key=lambda e: -e[1]):
            lines.append("  %6d  %s" % (count, explanation))
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", required=True, help="repository to index")
    parser.add_argument("--seed", default="20260918", help="sample seed (a string)")
    parser.add_argument("--size", type=int, default=1200, help="definitions to sample")
    parser.add_argument("--language", default="java", help="language to sample")
    parser.add_argument(
        "--roles",
        default="",
        help="comma-separated roles; defaults to the language's own set",
    )
    parser.add_argument(
        "--binary",
        default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "zig-out", "bin", "semidx-mcp"),
        help="semidx-mcp binary",
    )
    parser.add_argument("--max-response-bytes", type=int, default=400000)
    parser.add_argument("--json", help="also write the raw report to this file")
    args = parser.parse_args()

    if not os.path.isfile(args.binary) or not os.access(args.binary, os.X_OK):
        raise SystemExit(
            "semidx-mcp not found at %s; build it with `zig build -Doptimize=ReleaseFast`"
            % args.binary
        )

    defaults = {"java": "class,method", "zig": "function,container", "clojure": "function"}
    roles = args.roles or defaults.get(args.language, "")
    if not roles:
        raise SystemExit("no default roles for language %s; pass --roles" % args.language)

    server = Server(args.binary, args.root, args.max_response_bytes)
    try:
        health = server.call("semidx_health", {}, budgeted=False)
        population = enumerate_definitions(server, args.language, roles.split(","))
        if not population:
            raise SystemExit("no %s definitions under %s" % (args.language, args.root))
        sampled = sample(population, args.seed, args.size)
        totals, families, unclassified = measure(server, sampled)
    finally:
        server.close()

    text = report(args, health, len(population), sampled, totals, families, unclassified)
    print(text)
    if args.json:
        with open(args.json, "w") as handle:
            json.dump(
                {
                    "root": args.root,
                    "language": args.language,
                    "seed": args.seed,
                    "population": len(population),
                    "sample": len(sampled),
                    "totals": {"%s/%s" % key: value for key, value in totals.items()},
                    "families": families,
                    "unclassified": unclassified,
                },
                handle,
                indent=2,
                sort_keys=True,
            )
    return 0 if sum(families.values()) == totals.get(("calls", "unresolved"), 0) else 1


if __name__ == "__main__":
    sys.exit(main())
