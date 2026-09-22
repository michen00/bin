#!/usr/bin/env bash
# Common test helper functions for BATS tests

# Get the directory containing the scripts (parent of tests directory)
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPTS_DIR

# `run --separate-stderr` requires bats 1.5.0.
bats_require_minimum_version 1.5.0

# Setup function - runs before each test
setup() {
	# Create a temporary directory for test files
	TEST_TEMP_DIR="$(mktemp -d)"
	cd "$TEST_TEMP_DIR" || return 1
}

# Teardown function - runs after each test
teardown() {
	# Clean up temporary directory
	if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
		rm -rf "$TEST_TEMP_DIR"
	fi
}

# Helper to create a minimal git repo for git-related tests
setup_git_repo() {
	git init --initial-branch=main
	git config user.email "test@example.com"
	git config user.name "Test User"
	echo "initial" >README.md
	git add README.md
	git commit -m "Initial commit"
}

# Helper to build a PATH that contains only the named commands, so that a
# test can run a script as if every other command were not installed
# Parameters:
#   $@ - commands to make available
# Outputs: the directory to use as PATH
restricted_path() {
	local dir="$TEST_TEMP_DIR/restricted-bin"
	local cmd
	mkdir -p "$dir"
	for cmd in "$@"; do
		ln -sf "$(command -v "$cmd")" "$dir/$cmd"
	done
	echo "$dir"
}

# Helper to check if output contains a substring
# Parameters:
#   $1 - expected substring
# Note: $output is set by BATS 'run' command
assert_output_contains() {
	local expected="$1"
	# shellcheck disable=SC2154  # $output is set by BATS
	if [[ "$output" != *"$expected"* ]]; then
		echo "Expected output to contain: $expected"
		echo "Actual output: $output"
		return 1
	fi
}

# Helper to check if output does NOT contain a substring
# Parameters:
#   $1 - unexpected substring
# Note: $output is set by BATS 'run' command
assert_output_not_contains() {
	local unexpected="$1"
	# shellcheck disable=SC2154  # $output is set by BATS
	if [[ "$output" == *"$unexpected"* ]]; then
		echo "Expected output NOT to contain: $unexpected"
		echo "Actual output: $output"
		return 1
	fi
}

# Helper to assert file is executable
assert_executable() {
	local file="$1"
	if [[ ! -x "$file" ]]; then
		echo "Expected '$file' to be executable"
		return 1
	fi
}

# Helper to assert file exists
assert_file_exists() {
	local file="$1"
	if [[ ! -f "$file" ]]; then
		echo "Expected file '$file' to exist"
		return 1
	fi
}

# Helper to assert directory exists
assert_dir_exists() {
	local dir="$1"
	if [[ ! -d "$dir" ]]; then
		echo "Expected directory '$dir' to exist"
		return 1
	fi
}
