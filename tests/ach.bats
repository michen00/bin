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
	assert_output_contains "HASH"
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
	run grep -q "# Initial commit" ".git-blame-ignore-revs"
	[ "$status" -ne 0 ]
}

@test "ach: fails with invalid hash" {
	setup_git_repo

	run "$SCRIPTS_DIR/ach" "invalidhash123"
	[ "$status" -ne 0 ]
}

@test "ach: commit is atomic - does not include pre-staged changes" {
	setup_git_repo

	# Create and stage a separate file (simulating user's work in progress)
	echo "unrelated work" >unrelated.txt
	git add unrelated.txt

	# Verify it's staged
	git diff --cached --name-only | grep -q "unrelated.txt"

	# Capture hash before ach runs
	local target_hash
	target_hash=$(git rev-parse HEAD)

	# Run ach - this should ONLY commit the blame file
	run "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]

	# Verify the target hash was added to the ignore file
	grep -q "$target_hash" ".git-blame-ignore-revs"

	# The ach commit should contain ONLY the blame file, not unrelated.txt
	local ach_commit_files
	ach_commit_files=$(git diff-tree --no-commit-id --name-only -r HEAD)
	[ "$ach_commit_files" = ".git-blame-ignore-revs" ]

	# unrelated.txt should still be staged (restored from stash)
	git diff --cached --name-only | grep -q "unrelated.txt"
}
