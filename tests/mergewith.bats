#!/usr/bin/env bats

load 'test_helper'

# Helper to create a repository in $TEST_TEMP_DIR/work whose main branch
# tracks origin/main in a bare repository at $TEST_TEMP_DIR/remote.git.
# The remote sits outside the working tree so that merges never see it as
# an untracked directory.
setup_repo_with_origin() {
	mkdir "$TEST_TEMP_DIR/work"
	cd "$TEST_TEMP_DIR/work" || return 1
	setup_git_repo
	git clone --bare . "$TEST_TEMP_DIR/remote.git"
	git remote add origin "$TEST_TEMP_DIR/remote.git"
	git fetch origin
	git branch --set-upstream-to=origin/main main
}

@test "mergewith: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/mergewith"
}

@test "mergewith: --help displays usage information on stdout" {
	run --separate-stderr "$SCRIPTS_DIR/mergewith" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "reference_branch"
	[ -z "$stderr" ]
}

@test "mergewith: -h displays usage information on stdout" {
	run --separate-stderr "$SCRIPTS_DIR/mergewith" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "reference_branch"
	[ -z "$stderr" ]
}

@test "mergewith: help describes the steps before its labeled sections" {
	run "$SCRIPTS_DIR/mergewith" --help
	[ "$status" -eq 0 ]
	# Only the text before the first labeled section is the description.
	output="${output%%Arguments:*}"
	assert_output_contains "performs the following steps:"
}

@test "mergewith: fails with usage error when no reference branch specified" {
	setup_git_repo

	run --separate-stderr "$SCRIPTS_DIR/mergewith"
	[ "$status" -eq 2 ]
	assert_stderr_contains "Error: No reference branch specified."
	assert_stderr_contains "Usage:"
	[ -z "$output" ]
}

@test "mergewith: fails with usage error when given an extra argument" {
	run --separate-stderr "$SCRIPTS_DIR/mergewith" main develop
	[ "$status" -eq 2 ]
	assert_stderr_contains "Error: Multiple reference branches provided: 'main' and 'develop'"
	assert_stderr_contains "Usage:"
	[ -z "$output" ]
}

@test "mergewith: fails with usage error when an empty argument precedes a branch" {
	run --separate-stderr "$SCRIPTS_DIR/mergewith" '' main
	[ "$status" -eq 2 ]
	assert_stderr_contains "Error: Multiple reference branches provided: '' and 'main'"
	assert_stderr_contains "Usage:"
	[ -z "$output" ]
}

@test "mergewith: fails with exit 1 when the reference branch is empty" {
	run --separate-stderr "$SCRIPTS_DIR/mergewith" ''
	[ "$status" -eq 1 ]
	[ "$stderr" = "Error: The reference branch name is empty." ]
	[ -z "$output" ]
}

@test "mergewith: fails with unknown option" {
	run --separate-stderr "$SCRIPTS_DIR/mergewith" --unknown
	[ "$status" -eq 2 ]
	assert_stderr_contains "Error: Unknown option '--unknown'"
	assert_stderr_contains "Usage:"
	[ -z "$output" ]
}

@test "mergewith: fails when git is not installed" {
	run --separate-stderr env PATH="$(restricted_path bash basename)" "$SCRIPTS_DIR/mergewith" main
	[ "$status" -eq 1 ]
	assert_stderr_contains "'git' is required"
	assert_stderr_contains "https://git-scm.com/downloads"
	[ -z "$output" ]
}

@test "mergewith: shows help when git is not installed" {
	run --separate-stderr env PATH="$(restricted_path bash basename cat)" "$SCRIPTS_DIR/mergewith" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	[ -z "$stderr" ]
}

@test "mergewith: fails when not in a git repository" {
	# We're in TEST_TEMP_DIR which is not a git repo
	run --separate-stderr "$SCRIPTS_DIR/mergewith" main
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: Not inside a Git repository."
	[ -z "$output" ]
}

@test "mergewith: fails in detached HEAD state" {
	setup_git_repo

	# Enter detached HEAD state
	git checkout --detach HEAD

	run --separate-stderr "$SCRIPTS_DIR/mergewith" main
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: You are in detached HEAD state. Please check out a branch first."
	[ -z "$output" ]
}

@test "mergewith: warns and skips the merge when current and reference branch are the same" {
	setup_repo_with_origin

	run --separate-stderr "$SCRIPTS_DIR/mergewith" main
	[ "$status" -eq 0 ]
	assert_output_contains "Pulling latest changes for main"
	assert_output_not_contains "Fetching latest changes"
	assert_stderr_contains "Warning: The current branch and reference branch are the same: 'main'. Skipping the merge."
}

@test "mergewith: merges the reference branch into the current branch" {
	setup_repo_with_origin
	git checkout -b feature
	git checkout main
	echo "update" >update.txt
	git add update.txt
	git commit -m "Add update.txt on main"
	git push origin main
	git checkout feature

	run --separate-stderr "$SCRIPTS_DIR/mergewith" main
	[ "$status" -eq 0 ]
	assert_output_contains "No upstream configured for feature, skipping pull."
	assert_output_contains "Successfully updated feature with changes from main."
	[ "$(cat update.txt)" = "update" ]
}

@test "mergewith: fails when the pull fails" {
	setup_repo_with_origin
	# The remote-tracking ref survives, so the upstream still resolves and
	# only the pull itself fails.
	rm -rf "$TEST_TEMP_DIR/remote.git"

	run --separate-stderr "$SCRIPTS_DIR/mergewith" develop
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: Failed to pull the latest changes for branch 'main'."
	assert_output_not_contains "Error:"
}

@test "mergewith: fails when the reference branch cannot be fetched" {
	setup_repo_with_origin

	run --separate-stderr "$SCRIPTS_DIR/mergewith" no-such-branch
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: Failed to fetch latest changes for 'no-such-branch'."
	assert_output_not_contains "Error:"
}

@test "mergewith: fails when the merge has conflicts" {
	setup_repo_with_origin
	git checkout -b conflicting
	echo "conflicting" >README.md
	git commit -am "Change README.md on conflicting"
	git checkout main
	echo "main" >README.md
	git commit -am "Change README.md on main"
	git push origin main
	git checkout conflicting

	run --separate-stderr "$SCRIPTS_DIR/mergewith" main
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: Failed to merge branch 'main' into 'conflicting'."
	assert_stderr_contains "run 'git merge --abort' to cancel it."
	assert_output_not_contains "Error:"
}
