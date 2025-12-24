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
	git checkout -b feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git checkout main
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
