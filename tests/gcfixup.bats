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

	# Get the initial commit hash
	local initial_hash
	initial_hash=$(git rev-parse HEAD)

	# Make a new change to fixup
	echo "change" >>README.md
	git add README.md

	# Run gcfixup (will fail on rebase since we're in non-interactive mode, but commit should work)
	# We use GIT_SEQUENCE_EDITOR to auto-proceed with rebase
	GIT_SEQUENCE_EDITOR=true run "$SCRIPTS_DIR/gcfixup" "$initial_hash"

	# Verify the fixup commit was created (check git log for fixup! prefix)
	run git log --oneline -2
	assert_output_contains "fixup!"
}
