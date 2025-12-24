#!/usr/bin/env bats

load 'test_helper'

@test "mergewith: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/mergewith"
}

@test "mergewith: --help displays usage information" {
	run "$SCRIPTS_DIR/mergewith" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "reference_branch"
}

@test "mergewith: -h displays usage information" {
	run "$SCRIPTS_DIR/mergewith" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
}

@test "mergewith: fails when no reference branch specified" {
	setup_git_repo

	run "$SCRIPTS_DIR/mergewith"
	[ "$status" -eq 0 ] # usage exits with 0
	assert_output_contains "reference_branch"
}

@test "mergewith: fails when not in a git repository" {
	# We're in TEST_TEMP_DIR which is not a git repo
	run "$SCRIPTS_DIR/mergewith" main
	[ "$status" -ne 0 ]
	assert_output_contains "Not inside a git repository"
}

@test "mergewith: warns when current and reference branch are the same" {
	setup_git_repo

	# Set up proper tracking so git pull works
	rm -rf ../remote.git
	git clone --bare . ../remote.git
	git remote add origin ../remote.git
	git fetch origin
	git branch --set-upstream-to=origin/main main

	run "$SCRIPTS_DIR/mergewith" main
	[ "$status" -eq 0 ]
	assert_output_contains "same"
}

@test "mergewith: fails with unknown option" {
	run "$SCRIPTS_DIR/mergewith" --unknown
	[ "$status" -eq 0 ] # usage exits with 0
	assert_output_contains "Unknown option"
}
