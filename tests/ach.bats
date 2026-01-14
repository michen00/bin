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
	run bash -c 'git diff --cached --name-only | grep -q "unrelated.txt"'
	[ "$status" -eq 0 ]

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

	# unrelated.txt should STILL be staged (git commit <file> preserves unrelated index changes)
	run bash -c 'git diff --cached --name-only | grep -q "unrelated.txt"'
	[ "$status" -eq 0 ]
}

@test "ach: succeeds with unstaged changes to other files" {
	setup_git_repo

	# Create a tracked file with unstaged modifications
	echo "tracked content" >tracked.txt
	git add tracked.txt
	git commit -m "Add tracked file"
	echo "modified content" >tracked.txt

	# Also create an untracked file
	echo "untracked content" >untracked.txt

	# Verify we have unstaged changes
	run git status --porcelain
	[[ "$output" == *" M tracked.txt"* ]] || [[ "$output" == *"M  tracked.txt"* ]] || [[ "$output" == *"?? untracked.txt"* ]]

	# Capture hash before ach runs
	local target_hash
	target_hash=$(git rev-parse HEAD)

	# Run ach - should succeed despite unstaged changes to other files
	run "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]

	# Verify the commit was created correctly
	grep -q "$target_hash" ".git-blame-ignore-revs"

	# Unstaged changes should still be present
	run git status --porcelain tracked.txt
	[[ "$output" == *"M"* ]]
}

@test "ach: fails when not in a git repository" {
	# We're in TEST_TEMP_DIR which is not a git repo
	run "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_output_contains "Must be run from the root of a git repository"
}

@test "ach: idempotent - skips when hash already exists in file" {
	setup_git_repo

	local target_hash
	target_hash=$(git rev-parse HEAD)

	# Run ach first time
	run "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]

	# Count commits before second run
	local commit_count_before
	commit_count_before=$(git rev-list --count HEAD)

	# Run ach again with the same hash (now the previous commit)
	run "$SCRIPTS_DIR/ach" "$target_hash"
	[ "$status" -eq 0 ]
	assert_output_contains "already exists"
	assert_output_contains "Skipping"

	# No new commit should have been created
	local commit_count_after
	commit_count_after=$(git rev-list --count HEAD)
	[ "$commit_count_before" -eq "$commit_count_after" ]
}

@test "ach: stashes uncommitted changes to target file" {
	setup_git_repo

	# Create the blame file with initial content (leave room for appending)
	echo "# Initial content" >.git-blame-ignore-revs
	echo "" >>.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"

	# Make uncommitted changes to the BEGINNING of the target file (to avoid merge conflict)
	{
		echo "# My uncommitted header"
		cat .git-blame-ignore-revs
	} >tmp && mv tmp .git-blame-ignore-revs

	# Verify we have uncommitted changes
	run git diff --name-only .git-blame-ignore-revs
	[ "$output" = ".git-blame-ignore-revs" ]

	# Capture hash to add
	local target_hash
	target_hash=$(git rev-parse HEAD)

	# Run ach
	run "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	assert_output_contains "Stashing uncommitted changes"

	# Verify the hash was added
	grep -q "$target_hash" ".git-blame-ignore-revs"

	# Verify our uncommitted changes are still present (restored cleanly or in stash)
	if grep -q "My uncommitted header" ".git-blame-ignore-revs"; then
		# Changes were restored cleanly
		assert_output_contains "Restored your uncommitted changes"
	else
		# Conflict - changes are in stash
		assert_output_contains "Could not cleanly restore"
	fi
}

@test "ach: fails when file is staged with different content" {
	setup_git_repo

	# Create and stage the blame file with content that doesn't include the target hash
	echo "# Some other content" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs

	# Now run ach - should fail because file is staged with different content
	run "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_output_contains "has staged changes"
	assert_output_contains "Unstage with"
}

@test "ach: commits when file is pre-staged with target hash" {
	setup_git_repo

	# First, create and commit the blame file (so it exists in HEAD)
	echo "# Blame ignore file" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"

	# Create another commit to have a hash to add
	echo "more content" >>README.md
	git add README.md
	git commit -m "Update readme"

	local target_hash
	target_hash=$(git rev-parse HEAD)

	# Stage the blame file with the target hash already added
	echo "$target_hash  # Update readme" >>.git-blame-ignore-revs
	git add .git-blame-ignore-revs

	# Run ach - should detect file is staged with hash and commit it
	run "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]

	# When file is staged with hash and no working tree changes, it hits idempotency
	# check first (since working tree == staged), so it just skips
	assert_output_contains "already exists"
}

@test "ach: re-stages other files after completion" {
	setup_git_repo

	# Create and stage multiple files
	echo "file1 content" >file1.txt
	echo "file2 content" >file2.txt
	git add file1.txt file2.txt

	# Verify both are staged
	run git diff --cached --name-only
	[[ "$output" == *"file1.txt"* ]]
	[[ "$output" == *"file2.txt"* ]]

	# Run ach
	run "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]

	# Both files should still be staged
	run git diff --cached --name-only
	[[ "$output" == *"file1.txt"* ]]
	[[ "$output" == *"file2.txt"* ]]
}
