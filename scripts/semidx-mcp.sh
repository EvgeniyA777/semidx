#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
semidx_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
binary="$semidx_root/zig-out/bin/semidx-mcp"

if [ ! -x "$binary" ]; then
    echo "semidx-mcp binary not found at $binary" >&2
    echo "Build it first: cd $semidx_root && zig build" >&2
    exit 1
fi

has_root=0
passthrough=0
for arg in "$@"; do
    case "$arg" in
        --root|--root=*) has_root=1 ;;
        --help|-h|--version) passthrough=1 ;;
    esac
done

if [ "$passthrough" -eq 1 ] || [ "$has_root" -eq 1 ]; then
    exec "$binary" "$@"
fi

if [ "${SEMIDX_ROOT:-}" ]; then
    root=$SEMIDX_ROOT
elif git_root=$(git -C "${PWD:-.}" rev-parse --show-toplevel 2>/dev/null); then
    root=$git_root
else
    echo "semidx root is not configured and current directory is not inside a Git repository" >&2
    echo "Pass --root /path/to/repository or set SEMIDX_ROOT=/path/to/repository" >&2
    exit 2
fi

exec "$binary" --root "$root" "$@"
