#!/bin/bash
# Common test helper functions for BATS tests

# Get the directory containing the scripts (parent of tests directory)
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPTS_DIR

# Setup function - runs before each test
setup() {
	# Create a temporary directory for test files
	TEST_TEMP_DIR="$(mktemp -d)"
	cd "$TEST_TEMP_DIR" || return 1

	# For venv-now tests: if python3 exists but python doesn't, create a symlink
	if command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
		mkdir -p "$TEST_TEMP_DIR/bin"
		ln -s "$(command -v python3)" "$TEST_TEMP_DIR/bin/python"
		export PATH="$TEST_TEMP_DIR/bin:$PATH"
	fi
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

# Helper to check if a string contains a substring
# Parameters:
#   $1 - expected substring
#   $2 - (optional) string to search; defaults to $output from the most recent Bats run
assert_output_contains() {
	local expected="$1"
	local actual="${2:-$output}" # Use parameter if provided, otherwise fall back to $output
	if [[ "$actual" != *"$expected"* ]]; then
		echo "Expected output to contain: $expected"
		echo "Actual output: $actual"
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
