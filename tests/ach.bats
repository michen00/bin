#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'test_helper'

@test "ach: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/ach"
}

@test "ach: --help displays usage information" {
	run "$SCRIPTS_DIR/ach" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "HASH"
}

@test "ach: -h displays usage information" {
	run "$SCRIPTS_DIR/ach" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
}

@test "ach: adds last commit hash to default file" {
	setup_git_repo

	# Capture the hash BEFORE running ach (since ach creates a new commit)
	local last_hash
	last_hash=$(git rev-parse HEAD)

	run "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	assert_file_exists ".git-blame-ignore-revs"

	# Verify the original commit hash is in the file
	grep -q "$last_hash" ".git-blame-ignore-revs"
}

@test "ach: adds specified hash to custom file" {
	setup_git_repo
	local hash
	hash=$(git rev-parse HEAD)

	run "$SCRIPTS_DIR/ach" "$hash" "custom-ignore.txt"
	[ "$status" -eq 0 ]
	assert_file_exists "custom-ignore.txt"
	grep -q "$hash" "custom-ignore.txt"
}

@test "ach: --no-summary omits commit summary" {
	setup_git_repo

	run "$SCRIPTS_DIR/ach" --no-summary
	[ "$status" -eq 0 ]
	assert_file_exists ".git-blame-ignore-revs"

	# File should only contain the hash line, not "# Initial commit"
	run ! grep -q "# Initial commit" ".git-blame-ignore-revs"
}

@test "ach: fails with invalid hash" {
	setup_git_repo

	run "$SCRIPTS_DIR/ach" "invalidhash123"
	[ "$status" -ne 0 ]
}
