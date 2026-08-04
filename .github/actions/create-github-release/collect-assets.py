#!/usr/bin/env python3
"""Expand newline-separated release asset patterns into NUL-delimited paths."""

from __future__ import annotations

import argparse
import glob
import os
import sys


def parse_bool(value: str) -> bool:
    if value == "true":
        return True
    if value == "false":
        return False
    raise argparse.ArgumentTypeError("expected 'true' or 'false'")


def patterns_from(value: str) -> list[str]:
    # YAML block scalars already remove their common indentation. Trimming each
    # remaining line makes indented/blank entries unsurprising while preserving
    # spaces inside paths.
    return [line.strip() for line in value.splitlines() if line.strip()]


def matching_files(pattern: str) -> list[str]:
    matches = glob.glob(pattern, recursive=True)
    files = [os.path.normpath(path) for path in matches if os.path.isfile(path)]
    return sorted(files, key=os.fsencode)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--patterns", required=True)
    parser.add_argument(
        "--fail-on-unmatched-files", required=True, type=parse_bool
    )
    args = parser.parse_args()

    assets: list[str] = []
    seen: set[str] = set()
    unmatched: list[str] = []

    for pattern in patterns_from(args.patterns):
        matches = matching_files(pattern)
        if not matches:
            unmatched.append(pattern)
            continue

        for path in matches:
            identity = os.path.abspath(path)
            if identity not in seen:
                seen.add(identity)
                assets.append(path)

    if unmatched and args.fail_on_unmatched_files:
        for pattern in unmatched:
            print(
                f"Error: release asset pattern matched no files: {pattern!r}",
                file=sys.stderr,
            )
        return 1

    for pattern in unmatched:
        print(
            f"Warning: release asset pattern matched no files: {pattern!r}",
            file=sys.stderr,
        )

    for asset in assets:
        sys.stdout.buffer.write(os.fsencode(asset) + b"\0")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
