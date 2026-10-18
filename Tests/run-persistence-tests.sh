#!/bin/bash
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_build_directory="$(mktemp -d "${TMPDIR:-/tmp}/dns-persistence-tests.XXXXXX")"
trap 'rm -rf -- "$test_build_directory"' EXIT

xcrun swiftc -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  "$repository_root/DNS Easy Switcher/DNSSettings.swift" \
  "$repository_root/DNS Easy Switcher/DNSPersistence.swift" \
  "$repository_root/Tests/PersistenceRegression.swift" \
  -framework CoreData -lsqlite3 \
  -o "$test_build_directory/persistence-regression"

"$test_build_directory/persistence-regression"
