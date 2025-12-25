#!/usr/bin/env bats

load 'test_helper'

@test "venv-now: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/venv-now"
}

@test "venv-now: --help displays usage information" {
	run "$SCRIPTS_DIR/venv-now" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "DIRECTORY"
}

@test "venv-now: -h displays usage information" {
	run "$SCRIPTS_DIR/venv-now" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "DIRECTORY"
}

@test "venv-now: creates .venv directory by default" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	run "$SCRIPTS_DIR/venv-now"
	[ "$status" -eq 0 ]
	assert_dir_exists ".venv"
	assert_file_exists ".venv/bin/activate"
}

@test "venv-now: creates custom-named venv directory" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	run "$SCRIPTS_DIR/venv-now" myenv
	[ "$status" -eq 0 ]
	assert_dir_exists "myenv"
	assert_file_exists "myenv/bin/activate"
}

@test "venv-now: --no-remove preserves existing venv" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	# Create initial venv with a marker file
	python3 -m venv .venv
	echo "marker" >.venv/marker.txt

	run "$SCRIPTS_DIR/venv-now" --no-remove
	[ "$status" -eq 0 ]
	# Marker file should still exist
	assert_file_exists ".venv/marker.txt"
}

@test "venv-now: removes existing venv by default" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	# Create initial venv with a marker file
	python3 -m venv .venv
	echo "marker" >.venv/marker.txt

	run "$SCRIPTS_DIR/venv-now"
	[ "$status" -eq 0 ]
	# Marker file should be gone (venv was recreated)
	[ ! -f ".venv/marker.txt" ]
}

@test "venv-now: -n is alias for --no-remove" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	python3 -m venv .venv
	echo "marker" >.venv/marker.txt

	run "$SCRIPTS_DIR/venv-now" -n
	[ "$status" -eq 0 ]
	assert_file_exists ".venv/marker.txt"
}

@test "venv-now: fails with unknown option" {
	run "$SCRIPTS_DIR/venv-now" --unknown
	[ "$status" -ne 0 ] # unknown option should exit with non-zero status
	assert_output_contains "Unknown option"
}

# Unit tests for is_dangerous_venv_path() - completely safe, no file operations
# These test the validation logic directly without invoking any dangerous ops

@test "is_dangerous_venv_path: rejects empty path" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "" "/some/path" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects dot" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "." "/current" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects double-dot" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path ".." "/parent" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects root path" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "/" "/" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects tilde" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "~" "$HOME" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects path resolving to HOME" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "some/path" "$HOME" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects path resolving to root" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "some/path" "/" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects path resolving to current dir" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "foo/.." "/current" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: accepts safe path" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path ".venv" "/project/.venv" "/project"
	[ "$status" -eq 1 ] # 1 = safe
}

@test "is_dangerous_venv_path: accepts custom venv name" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "myenv" "/project/myenv" "/project"
	[ "$status" -eq 1 ] # 1 = safe
}

# Integration test for dangerous path rejection (uses safe test directory)
@test "venv-now: integration test rejects path resolving to current dir" {
	mkdir -p testdir
	# testdir/.. resolves to TEST_TEMP_DIR (current dir) - safe to test
	run "$SCRIPTS_DIR/venv-now" "testdir/.."
	[ "$status" -ne 0 ]
	assert_output_contains "dangerous path"
}
