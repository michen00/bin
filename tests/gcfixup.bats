#!/usr/bin/env bats

load 'test_helper'

# A failing [[ ]] that is not the last command of a test does not fail the
# test under bash 3.2, so each [[ ]] check below ends with "|| false".

# This helper adds a second commit and prints its hash. Unlike the root
# commit, the second commit has a parent for gcfixup to rebase onto.
make_second_commit() {
	echo "second content" >second.txt
	git add second.txt
	git commit -q -m "Second commit"
	git rev-parse HEAD
}

@test "gcfixup: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/gcfixup"
}

@test "gcfixup: --help displays usage information on stdout" {
	run --separate-stderr "$SCRIPTS_DIR/gcfixup" --help
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "Usage: gcfixup [OPTIONS] <commit> [<git-commit-option>...]" ]
	assert_output_contains "<git-commit-option>"
	assert_output_contains "-h, --help"
	assert_output_contains "Show this help message and exit."
	[ -z "$stderr" ]
}

@test "gcfixup: -h displays usage information on stdout" {
	run --separate-stderr "$SCRIPTS_DIR/gcfixup" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	[ -z "$stderr" ]
}

@test "gcfixup: -h works without git installed" {
	run --separate-stderr env PATH="$(restricted_path bash basename cat)" "$SCRIPTS_DIR/gcfixup" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
}

@test "gcfixup: no arguments is a usage error" {
	run --separate-stderr "$SCRIPTS_DIR/gcfixup"
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: No commit specified."* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "gcfixup: -- without a commit is a usage error" {
	run --separate-stderr "$SCRIPTS_DIR/gcfixup" --
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: No commit specified."* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "gcfixup: rejects an unknown option" {
	run --separate-stderr "$SCRIPTS_DIR/gcfixup" --bogus abc123
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unknown option '--bogus'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "gcfixup: fails when git is not installed" {
	run --separate-stderr env PATH="$(restricted_path bash basename)" "$SCRIPTS_DIR/gcfixup" abc123
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"'git' is required"* ]] || false
	[[ "$stderr" == *"https://git-scm.com/downloads"* ]] || false
	[ -z "$output" ]
}

@test "gcfixup: fails when not in a git repository" {
	# The test runs in TEST_TEMP_DIR, which is not inside a git repository.
	run --separate-stderr "$SCRIPTS_DIR/gcfixup" HEAD
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Not inside a git repository."* ]] || false
	[[ "$stderr" != *"Invalid commit"* ]] || false
	[ -z "$output" ]
}

@test "gcfixup: fails with an invalid commit" {
	setup_git_repo

	run --separate-stderr "$SCRIPTS_DIR/gcfixup" invalidhash123
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Invalid commit 'invalidhash123'."* ]] || false
	[ -z "$output" ]
}

@test "gcfixup: -- ends the options, so a dash-prefixed commit is not an option" {
	setup_git_repo

	run --separate-stderr "$SCRIPTS_DIR/gcfixup" -- --bogus
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Invalid commit '--bogus'."* ]] || false
	[[ "$stderr" != *"Unknown option"* ]] || false
	[ -z "$output" ]
}

@test "gcfixup: fails on root commit with helpful workaround" {
	setup_git_repo

	# The initial commit from setup_git_repo is the root commit
	local root_hash
	root_hash=$(git rev-parse HEAD)

	run --separate-stderr "$SCRIPTS_DIR/gcfixup" "$root_hash"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Cannot fix up the root commit"* ]] || false
	[[ "$stderr" == *"Workaround"* ]] || false
	[[ "$stderr" == *"--root"* ]] || false
	[ -z "$output" ]
}

@test "gcfixup: fails when git commit fails" {
	setup_git_repo
	local second_hash
	second_hash=$(make_second_commit)

	# Nothing is staged, so git commit has nothing to commit.
	run --separate-stderr "$SCRIPTS_DIR/gcfixup" "$second_hash"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Failed to create a fixup commit for '$second_hash'."* ]] || false

	local commit_count
	commit_count=$(git rev-list --count HEAD)
	[ "$commit_count" -eq 2 ]
}

@test "gcfixup: creates fixup commit for valid hash" {
	setup_git_repo
	local second_hash
	second_hash=$(make_second_commit)

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

@test "gcfixup: accepts the commit after --" {
	setup_git_repo
	local second_hash
	second_hash=$(make_second_commit)

	echo "fixup content" >>second.txt
	git add second.txt

	GIT_SEQUENCE_EDITOR=true GIT_EDITOR=true run "$SCRIPTS_DIR/gcfixup" -- "$second_hash"
	[ "$status" -eq 0 ]

	local commit_count
	commit_count=$(git rev-list --count HEAD)
	[ "$commit_count" -eq 2 ]
	git show HEAD:second.txt | grep -q "fixup content"
}

@test "gcfixup: passes arguments after the commit to git commit" {
	setup_git_repo
	local second_hash
	second_hash=$(make_second_commit)

	# The change is not staged; only the -a passed through to git commit
	# includes it in the fixup commit.
	echo "fixup content" >>second.txt

	GIT_SEQUENCE_EDITOR=true GIT_EDITOR=true run "$SCRIPTS_DIR/gcfixup" "$second_hash" -a
	[ "$status" -eq 0 ]

	local commit_count
	commit_count=$(git rev-list --count HEAD)
	[ "$commit_count" -eq 2 ]
	git show HEAD:second.txt | grep -q "fixup content"
	git diff --quiet HEAD
}

@test "gcfixup: fixes up a commit named relative to HEAD" {
	setup_git_repo
	make_second_commit >/dev/null
	echo "third content" >third.txt
	git add third.txt
	git commit -q -m "Third commit"

	echo "fixup content" >>second.txt
	git add second.txt

	# The fixup commit moves HEAD, so the rebase must not resolve HEAD~1 again.
	GIT_SEQUENCE_EDITOR=true GIT_EDITOR=true run "$SCRIPTS_DIR/gcfixup" HEAD~1
	[ "$status" -eq 0 ]

	local commit_count
	commit_count=$(git rev-list --count HEAD)
	[ "$commit_count" -eq 3 ]
	[ "$(git log -1 --format=%s HEAD~1)" = "Second commit" ]
	git show HEAD~1:second.txt | grep -q "fixup content"
}
