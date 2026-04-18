#!/usr/bin/env bash
# Run all executable integration test scripts in this directory
# Exits non-zero if any test fails
set -e

for test_script in *.sh; do
    if [[ -x "$test_script" ]]; then
        echo "Running $test_script"
        ./$test_script || {
            echo "Test $test_script failed" >&2
            exit 1
        }
    fi
done

echo "All integration tests passed."
