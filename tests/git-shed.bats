#!/usr/bin/env bats

load 'test_helper'

@test "git-shed: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/git-shed"
}

@test "git-shed: --help displays usage information" {
	run "$SCRIPTS_DIR/git-shed" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "TARGET_BRANCH"
}

@test "git-shed: -h displays usage information" {
	run "$SCRIPTS_DIR/git-shed" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "TARGET_BRANCH"
}

@test "git-shed: fails when target branch does not exist" {
	setup_git_repo

	run "$SCRIPTS_DIR/git-shed" nonexistent-branch
	[ "$status" -ne 0 ]
	assert_output_contains "does not exist"
}

@test "git-shed: --dry-run shows what would be deleted without deleting" {
	setup_git_repo
	git switch -c feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git switch main
	git merge feature-branch

	run "$SCRIPTS_DIR/git-shed" --dry-run -y main
	[ "$status" -eq 0 ]
	assert_output_contains "DRY-RUN"
	# Branch should still exist after dry-run
	git show-ref --verify --quiet refs/heads/feature-branch
}

@test "git-shed: defaults to main branch" {
	setup_git_repo

	run "$SCRIPTS_DIR/git-shed" --dry-run -y
	[ "$status" -eq 0 ]
	assert_output_contains "Fetching"
}

@test "git-shed: --help mentions --gone-only" {
	run "$SCRIPTS_DIR/git-shed" --help
	[ "$status" -eq 0 ]
	assert_output_contains "--gone-only"
}

@test "git-shed: --gone-only skips merged branch pass" {
	setup_git_repo
	git switch -c feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git switch main
	git merge feature-branch

	run "$SCRIPTS_DIR/git-shed" --gone-only --dry-run -y
	[ "$status" -eq 0 ]
	assert_output_not_contains "merged into"
	git show-ref --verify --quiet refs/heads/feature-branch
}

@test "git-shed: -- accepts dash-prefixed target branch" {
	setup_git_repo
	# `git branch` / `git switch -c` refuse dash-prefixed names; use
	# update-ref directly so we can exercise the parser path for branches
	# named like '-wip'.
	git update-ref refs/heads/-wip HEAD

	run "$SCRIPTS_DIR/git-shed" --dry-run -y -- -wip
	[ "$status" -eq 0 ]
	assert_output_not_contains "Unknown option"
}

@test "git-shed: rejects dash-prefixed target without --" {
	setup_git_repo

	run "$SCRIPTS_DIR/git-shed" --dry-run -y -wip
	[ "$status" -eq 2 ]
	assert_output_contains "Unknown option: -wip"
}

@test "git-shed: bare repo does not hard-fail" {
	# Build a non-bare source, create a merged feature branch, then clone
	# bare so the bare clone has refs/heads/main and refs/heads/feature
	# but no working tree. `remove_linked_worktree_for_branch` must
	# tolerate this rather than aborting under `set -e`.
	setup_git_repo
	git switch -c feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git switch main
	git merge feature-branch
	source_dir="$PWD"

	cd "$TEST_TEMP_DIR"
	git clone --bare "$source_dir" bare.git
	cd bare.git

	run "$SCRIPTS_DIR/git-shed" --dry-run -y main
	[ "$status" -eq 0 ]
	assert_output_not_contains "must be run in a work tree"
}
