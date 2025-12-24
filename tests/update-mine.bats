#!/usr/bin/env bats

load 'test_helper'

@test "update-mine: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/update-mine"
}

@test "update-mine: --help displays usage information" {
	run "$SCRIPTS_DIR/update-mine" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "reference_branch"
}

@test "update-mine: fails when no reference branch specified" {
	run "$SCRIPTS_DIR/update-mine"
	[ "$status" -ne 0 ]
	assert_output_contains "Missing"
}

@test "update-mine: fails when not in a git repository" {
	# We're in TEST_TEMP_DIR which is not a git repo
	run "$SCRIPTS_DIR/update-mine" main
	[ "$status" -ne 0 ]
	assert_output_contains "Not inside a Git repository"
}

@test "update-mine: accepts --debug flag" {
	setup_git_repo

	# This will fail because gh is not configured, but it should accept the flag
	run "$SCRIPTS_DIR/update-mine" --debug main
	# Should not fail due to unknown option
	[[ "$output" != *"Unknown option"* ]]
}

@test "update-mine: accepts --all flag" {
	setup_git_repo

	# This will fail because gh is not configured, but it should accept the flag
	run "$SCRIPTS_DIR/update-mine" --all main
	# Should not fail due to unknown option
	[[ "$output" != *"Unknown option"* ]]
}

@test "update-mine: fails with unknown option" {
	run "$SCRIPTS_DIR/update-mine" --unknown main
	[ "$status" -eq 0 ] # usage exits with 0
	assert_output_contains "Usage"
}
