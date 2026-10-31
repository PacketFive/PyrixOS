# SPDX-License-Identifier: GPL-2.0
"""Print the crates of a Cargo.lock as a PyBonsai list for ``cargo_vendor``.

Usage: python3 scripts/cargo-crates.py NAME Cargo.lock [Cargo.lock ...]

Every package from crates.io becomes a ``(name, version, sha256)`` entry;
the checksum Cargo.lock records is the SHA-256 of the ``.crate`` file,
which is what ``fetch_url`` checks. Packages from any other source stop
the script, since the package set fetches only from crates.io.
"""

import sys
import tomllib

CRATES_IO = "registry+https://github.com/rust-lang/crates.io-index"


def crates(paths: list[str]) -> list[tuple[str, str, str]]:
    found: dict[tuple[str, str], str] = {}
    for path in paths:
        with open(path, "rb") as file:
            lock = tomllib.load(file)
        for package in lock.get("package", []):
            source = package.get("source")
            if source is None:
                continue
            if source != CRATES_IO:
                sys.exit(f"{path}: {package['name']} {package['version']} comes from {source}")
            found[(package["name"], package["version"])] = package["checksum"]
    return [(name, version, found[(name, version)]) for name, version in sorted(found)]


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    print(f"{sys.argv[1]} = [")
    for name, version, checksum in crates(sys.argv[2:]):
        print(f'    ("{name}", "{version}", "{checksum}"),')
    print("]")


if __name__ == "__main__":
    main()
