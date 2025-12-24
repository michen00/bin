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

@test "venv-now: rejects dangerous path resolving to ." {
	mkdir -p testdir
	# Use a path that resolves to the current directory, but is not literally "."
	run "$SCRIPTS_DIR/venv-now" "testdir/.."
	[ "$status" -ne 0 ]
	assert_output_contains "dangerous path"
}

@test "venv-now: rejects dangerous path /" {
	run "$SCRIPTS_DIR/venv-now" /
	[ "$status" -ne 0 ]
	assert_output_contains "dangerous path"
}

@test "venv-now: rejects path resolving to HOME" {
	# $HOME/. resolves to $HOME
	run "$SCRIPTS_DIR/venv-now" "$HOME/."
	[ "$status" -ne 0 ]
	assert_output_contains "dangerous path"
}
