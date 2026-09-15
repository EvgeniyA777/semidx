#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
expected=$(tr -d '[:space:]' < "$repo_root/.zigversion")

if ! command -v zig >/dev/null 2>&1; then
    echo "expected Zig $expected, but zig is not on PATH" >&2
    echo "Install or select Zig $expected before building semidx." >&2
    exit 1
fi

actual=$(zig version)

if [ "$actual" != "$expected" ]; then
    echo "expected Zig $expected, found $actual" >&2
    echo "Install or select Zig $expected before building semidx." >&2
    exit 1
fi

if ! grep -F ".minimum_zig_version = \"$expected\"" "$repo_root/build.zig.zon" >/dev/null; then
    echo "build.zig.zon minimum_zig_version does not match .zigversion ($expected)" >&2
    exit 1
fi

echo "Zig version $actual matches semidx target"
