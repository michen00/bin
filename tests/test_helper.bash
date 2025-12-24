#!/bin/bash
# Common test helper functions for BATS tests

# Get the directory containing the scripts (parent of tests directory)
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPTS_DIR

# Ensure a "python" executable is available on PATH for tests that expect it.
# If python3 exists but python does not, create a persistent shim directory
# containing a python -> python3 symlink and prepend it to PATH if needed.
# Tests that modify PATH should either preserve $PYTHON_SHIM_DIR on PATH or
# call this helper again after changing PATH.
ensure_python_symlink() {
	# If "python" is already available, nothing to do.
	if command -v python &>/dev/null; then
		return 0
	fi

	# If python3 is not available either, we cannot provide a shim.
	if ! command -v python3 &>/dev/null; then
		return 0
	fi

	# Lazily create a persistent shim directory once per test run.
	if [[ -z "${PYTHON_SHIM_DIR:-}" ]]; then
		PYTHON_SHIM_DIR="$(mktemp -d)"
		export PYTHON_SHIM_DIR
	fi

	mkdir -p "$PYTHON_SHIM_DIR"
	ln -sf "$(command -v python3)" "$PYTHON_SHIM_DIR/python"

	# Prepend the shim directory to PATH if it's not already present.
	case ":$PATH:" in
	*":$PYTHON_SHIM_DIR:"*) ;;
	*) export PATH="$PYTHON_SHIM_DIR:$PATH" ;;
	esac
}

# Setup function - runs before each test
setup() {
	# Create a temporary directory for test files
	TEST_TEMP_DIR="$(mktemp -d)"
	cd "$TEST_TEMP_DIR" || return 1

	# Ensure a "python" command is available on PATH for tests that expect it.
	ensure_python_symlink
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
