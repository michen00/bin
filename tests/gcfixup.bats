#!/usr/bin/env bats

load 'test_helper'

@test "gcfixup: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/gcfixup"
}

@test "gcfixup: --help displays usage information" {
	run "$SCRIPTS_DIR/gcfixup" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "target commit hash"
}

@test "gcfixup: -h displays usage information" {
	run "$SCRIPTS_DIR/gcfixup" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
}

@test "gcfixup: shows help when no arguments provided" {
	run "$SCRIPTS_DIR/gcfixup"
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
}

@test "gcfixup: fails with invalid commit hash" {
	setup_git_repo

	run "$SCRIPTS_DIR/gcfixup" invalidhash123
	[ "$status" -ne 0 ]
}

@test "gcfixup: creates fixup commit for valid hash" {
	setup_git_repo

	# Create a second commit so we're not fixing up the root commit
	echo "second content" >second.txt
	git add second.txt
	git commit -m "Second commit"

	# Get the second commit hash
	local second_hash
	second_hash=$(git rev-parse HEAD)

	# Make a new change to fixup
	echo "fixup content" >>second.txt
	git add second.txt

	# Run gcfixup.
	# We use GIT_SEQUENCE_EDITOR=true to auto-proceed with the rebase plan.
	# The rebase should squash the fixup commit into the "Second commit".
	GIT_SEQUENCE_EDITOR=true GIT_EDITOR=true run "$SCRIPTS_DIR/gcfixup" "$second_hash"
	[ "$status" -eq 0 ]

	# Verify the commit count is still 2 (fixup was squashed)
	local commit_count
	commit_count=$(git rev-list --count HEAD)
	[ "$commit_count" -eq 2 ]

	# Verify the content of second.txt contains both original and fixup content
	grep -q "second content" second.txt
	grep -q "fixup content" second.txt

	# Verify the commit message of HEAD is still "Second commit"
	run git log -1 --format=%s
	[ "$output" = "Second commit" ]
}
