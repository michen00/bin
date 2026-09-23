#!/usr/bin/env bats

load 'test_helper'

# Helper to build a PATH whose git fails each command whose arguments begin
# with one of the given prefixes and passes every other command to the real
# git. The wrapper goes in BATS_TEST_TMPDIR, because TEST_TEMP_DIR is the test
# repository, and a file there would change the output of git status.
# Parameters:
#   $@ - prefixes of the git arguments to fail, such as "commit" or "stash pop"
# Outputs: the value to use as PATH
failing_git_path() {
	local dir="$BATS_TEST_TMPDIR/failing-git-bin"
	local real_git prefix
	real_git=$(command -v git)
	mkdir -p "$dir"
	{
		echo '#!/bin/sh'
		for prefix in "$@"; do
			echo "case \"\$*\" in '$prefix'*) exit 1 ;; esac"
		done
		echo "exec '$real_git' \"\$@\""
	} >"$dir/git"
	chmod +x "$dir/git"
	echo "$dir:$PATH"
}

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

@test "ach: --help prints to stdout and nothing to stderr" {
	run --separate-stderr "$SCRIPTS_DIR/ach" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	[ -z "$stderr" ]
}

@test "ach: --help describes HASH and FILE under Arguments:, before Options:" {
	run "$SCRIPTS_DIR/ach" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Arguments:"*"Options:"* ]] || false

	local arguments_section=${output#*Arguments:}
	arguments_section=${arguments_section%%Options:*}
	[[ "$arguments_section" == *"HASH"* ]] || false
	[[ "$arguments_section" == *"FILE"* ]] || false
}

@test "ach: -h works when git is not installed" {
	run env PATH="$(restricted_path bash basename cat)" "$SCRIPTS_DIR/ach" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
}

@test "ach: unknown option exits 2 with an error on stderr" {
	run --separate-stderr "$SCRIPTS_DIR/ach" -x
	[ "$status" -eq 2 ]
	assert_stderr_contains "Error: Unknown option '-x'"
	assert_stderr_contains "Usage:"
	[ -z "$output" ]
}

@test "ach: unknown option after a HASH exits 2" {
	setup_git_repo
	local hash
	hash=$(git rev-parse HEAD)

	run --separate-stderr "$SCRIPTS_DIR/ach" "$hash" --bogus
	[ "$status" -eq 2 ]
	assert_stderr_contains "Error: Unknown option '--bogus'"
	[ -z "$output" ]
	[ ! -e ".git-blame-ignore-revs" ]
}

@test "ach: a third positional argument exits 2 without committing" {
	setup_git_repo
	local hash commit_count_before
	hash=$(git rev-parse HEAD)
	commit_count_before=$(git rev-list --count HEAD)

	run --separate-stderr "$SCRIPTS_DIR/ach" "$hash" custom-ignore.txt extra
	[ "$status" -eq 2 ]
	assert_stderr_contains "Error: Unexpected argument 'extra'"
	assert_stderr_contains "Usage:"
	[ -z "$output" ]
	[ ! -e "custom-ignore.txt" ]
	[ "$(git rev-list --count HEAD)" -eq "$commit_count_before" ]
}

@test "ach: fails with a clear error when git is not installed" {
	run --separate-stderr env PATH="$(restricted_path bash basename cat)" "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_stderr_contains "'git' is required"
	assert_stderr_contains "https://git-scm.com/downloads"
	[ -z "$output" ]
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

	run --separate-stderr "$SCRIPTS_DIR/ach" "invalidhash123"
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: Invalid commit hash: invalidhash123"
}

@test "ach: -- accepts a FILE that begins with a dash" {
	setup_git_repo
	local target_hash
	target_hash=$(git rev-parse HEAD)

	run "$SCRIPTS_DIR/ach" -- "$target_hash" -ignore.txt
	[ "$status" -eq 0 ]
	assert_file_exists "-ignore.txt"
	grep -q -- "$target_hash" ./-ignore.txt

	# The ach commit should contain only the dash-prefixed file.
	local ach_commit_files
	ach_commit_files=$(git diff-tree --no-commit-id --name-only -r HEAD)
	[ "$ach_commit_files" = "-ignore.txt" ]
}

@test "ach: -- appends to an existing FILE that begins with a dash" {
	setup_git_repo
	local first_hash second_hash
	first_hash=$(git rev-parse HEAD)

	run "$SCRIPTS_DIR/ach" -- "$first_hash" -ignore.txt
	[ "$status" -eq 0 ]

	echo "more content" >>README.md
	git add README.md
	git commit -m "Update readme"
	second_hash=$(git rev-parse HEAD)

	run "$SCRIPTS_DIR/ach" -- "$second_hash" -ignore.txt
	[ "$status" -eq 0 ]
	# git diff must read the file as a path. If git read it as an option, git
	# diff would fail, and ach would try to stash a file that has no changes.
	assert_output_not_contains "Stashing"
	grep -q -- "$first_hash" ./-ignore.txt
	grep -q -- "$second_hash" ./-ignore.txt
}

@test "ach: -- skips a HASH already in a FILE that begins with a dash" {
	setup_git_repo
	local target_hash
	target_hash=$(git rev-parse HEAD)

	run "$SCRIPTS_DIR/ach" -- "$target_hash" -ignore.txt
	[ "$status" -eq 0 ]

	run "$SCRIPTS_DIR/ach" -- "$target_hash" -ignore.txt
	[ "$status" -eq 0 ]
	assert_output_contains "already exists"
	[ "$(grep -c -- "$target_hash" ./-ignore.txt)" -eq 1 ]
}

@test "ach: -- stashes uncommitted changes to a FILE that begins with a dash" {
	setup_git_repo

	echo "# Initial content" >./-ignore.txt
	echo "" >>./-ignore.txt
	git add -- -ignore.txt
	git commit -m "Add blame file"
	{
		echo "# My uncommitted header"
		cat -- -ignore.txt
	} >tmp && mv -- tmp -ignore.txt

	local target_hash
	target_hash=$(git rev-parse HEAD)

	run "$SCRIPTS_DIR/ach" -- "$target_hash" -ignore.txt
	[ "$status" -eq 0 ]
	assert_output_contains "Stashing uncommitted changes"
	grep -q -- "$target_hash" ./-ignore.txt
}

@test "ach: -- makes a later -h an argument, not the help option" {
	setup_git_repo

	run --separate-stderr "$SCRIPTS_DIR/ach" -- -h
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: Invalid commit hash: -h"
	assert_output_not_contains "usage:"
	assert_output_not_contains "Usage:"
}

@test "ach: -- with no arguments after it uses the last commit" {
	setup_git_repo
	local last_hash
	last_hash=$(git rev-parse HEAD)

	run "$SCRIPTS_DIR/ach" --
	[ "$status" -eq 0 ]
	grep -q "$last_hash" ".git-blame-ignore-revs"
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
	[[ "$output" == *" M tracked.txt"* ]] || [[ "$output" == *"M  tracked.txt"* ]] || [[ "$output" == *"?? untracked.txt"* ]] || false

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
	assert_output_contains "M"
}

@test "ach: fails when not in a git repository" {
	# We're in TEST_TEMP_DIR which is not a git repo
	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: Must be run from the root of a git repository"
}

@test "ach: works from a git worktree checkout" {
	setup_git_repo

	local target_hash
	target_hash=$(git rev-parse HEAD)

	git worktree add "$TEST_TEMP_DIR/worktree" -b worktree-branch
	cd "$TEST_TEMP_DIR/worktree" || return 1

	# Linked worktrees use a .git file (gitdir pointer), not a .git directory
	[ -f .git ]
	[ ! -d .git ]

	run "$SCRIPTS_DIR/ach" "$target_hash"
	[ "$status" -eq 0 ]
	assert_file_exists ".git-blame-ignore-revs"
	grep -q "$target_hash" ".git-blame-ignore-revs"
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
	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: .git-blame-ignore-revs has staged changes"
	assert_stderr_contains "Unstage with: git restore --staged -- .git-blame-ignore-revs"
}

@test "ach: keeps staged and unstaged changes to FILE when the staged content lacks the hash" {
	setup_git_repo
	echo "# Blame ignore file" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"

	echo "staged-line" >>.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	echo "unstaged-line" >>.git-blame-ignore-revs
	echo "unrelated work" >unrelated.txt
	git add unrelated.txt

	local content_before staged_before stash_before status_before
	content_before=$(cat .git-blame-ignore-revs)
	staged_before=$(git show :.git-blame-ignore-revs)
	stash_before=$(git stash list)
	# The status also records that unrelated.txt is staged, which ach undoes
	# before the check and must redo when the check fails.
	status_before=$(git status --porcelain)

	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: .git-blame-ignore-revs has staged changes"
	# The check must come before the stash, which would reset the staged content.
	assert_output_not_contains "Stashing"
	[ "$(cat .git-blame-ignore-revs)" = "$content_before" ]
	[ "$(git show :.git-blame-ignore-revs)" = "$staged_before" ]
	[ "$(git stash list)" = "$stash_before" ]
	[ "$(git status --porcelain)" = "$status_before" ]
}

@test "ach: commits the staged FILE and keeps its unstaged changes when the staged content has the hash" {
	setup_git_repo
	echo "# Blame ignore file" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"

	# The staged content includes the hash and the working tree does not.
	local target_hash
	target_hash=$(git rev-parse HEAD)
	echo "$target_hash  # Add blame file" >>.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	printf '%s\n' "# Blame ignore file" "unstaged-line" >.git-blame-ignore-revs
	echo "unrelated work" >unrelated.txt
	git add unrelated.txt

	local content_before staged_before stash_before
	content_before=$(cat .git-blame-ignore-revs)
	staged_before=$(git show :.git-blame-ignore-revs)
	stash_before=$(git stash list)

	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	assert_output_contains "Hash ${target_hash:0:7} already in staged .git-blame-ignore-revs."
	assert_output_not_contains "Stashing"
	[ -z "$stderr" ]
	# One new commit holds the staged content of FILE and nothing else.
	[ "$(git rev-parse HEAD~1)" = "$target_hash" ]
	[ "$(git log -1 --format=%s)" = "docs(blame): ignore ${target_hash:0:7}" ]
	[ "$(git diff-tree --no-commit-id --name-only -r HEAD)" = ".git-blame-ignore-revs" ]
	[ "$(git show HEAD:.git-blame-ignore-revs)" = "$staged_before" ]
	# The unstaged changes to FILE stay unstaged, and unrelated.txt is staged
	# again.
	[ "$(cat .git-blame-ignore-revs)" = "$content_before" ]
	[ "$(git show :.git-blame-ignore-revs)" = "$staged_before" ]
	[ "$(git diff --cached --name-only)" = "unrelated.txt" ]
	[ "$(git stash list)" = "$stash_before" ]
}

@test "ach: commits the staged FILE alone and keeps a staged rename staged" {
	setup_git_repo
	echo "# Blame ignore file" >.git-blame-ignore-revs
	echo "old content" >old.txt
	git add .git-blame-ignore-revs old.txt
	git commit -m "Add blame file"

	local target_hash
	target_hash=$(git rev-parse HEAD)
	echo "$target_hash  # Add blame file" >>.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	printf '%s\n' "# Blame ignore file" "unstaged-line" >.git-blame-ignore-revs
	# With rename detection on, git diff names a rename by its new path only.
	# ach must unstage the deletion of old.txt too, or its commit, which has no
	# pathspec, would include the deletion.
	git config diff.renames true
	git mv old.txt new.txt

	local content_before staged_before stash_before
	content_before=$(cat .git-blame-ignore-revs)
	staged_before=$(git show :.git-blame-ignore-revs)
	stash_before=$(git stash list)

	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ "$(git rev-parse HEAD~1)" = "$target_hash" ]
	[ "$(git diff-tree --no-commit-id --name-only -r HEAD)" = ".git-blame-ignore-revs" ]
	[ "$(git show HEAD:.git-blame-ignore-revs)" = "$staged_before" ]
	[ "$(cat .git-blame-ignore-revs)" = "$content_before" ]
	[ "$(git stash list)" = "$stash_before" ]
	# The rename is staged again as a rename, and FILE keeps its unstaged
	# change.
	[ "$(git status --porcelain)" = "$(printf '%s\n' " M .git-blame-ignore-revs" "R  old.txt -> new.txt")" ]
}

@test "ach: commits the staged FILE alone when git diff hides a staged submodule change" {
	setup_git_repo
	echo "# Blame ignore file" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	# A gitlink entry records a submodule commit without a submodule
	# repository. The empty directory stands for a submodule that is not
	# checked out, which git does not report as changed.
	mkdir sm
	git update-index --add --cacheinfo "160000,$(git rev-parse HEAD),sm"
	git commit -m "Add blame file"

	local target_hash
	target_hash=$(git rev-parse HEAD)
	echo "$target_hash  # Add blame file" >>.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	printf '%s\n' "# Blame ignore file" "unstaged-line" >.git-blame-ignore-revs
	git update-index --cacheinfo "160000,$target_hash,sm"
	# With this setting, git diff does not name the staged submodule change,
	# and the commit of a staged FILE, which has no pathspec, would include it.
	git config diff.ignoreSubmodules all

	local content_before staged_before sm_before
	content_before=$(cat .git-blame-ignore-revs)
	staged_before=$(git show :.git-blame-ignore-revs)
	sm_before=$(git ls-files -s -- sm)

	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ "$(git rev-parse HEAD~1)" = "$target_hash" ]
	[ "$(git diff-tree --no-commit-id --name-only -r HEAD)" = ".git-blame-ignore-revs" ]
	[ "$(git show HEAD:.git-blame-ignore-revs)" = "$staged_before" ]
	[ "$(cat .git-blame-ignore-revs)" = "$content_before" ]
	# The submodule change is staged again.
	[ "$(git ls-files -s -- sm)" = "$sm_before" ]
	[ "$(git diff-index --cached --name-only HEAD)" = "sm" ]
}

@test "ach: finds the hash at the top of a staged FILE that is larger than a pipe holds" {
	setup_git_repo
	# grep -q stops reading at the first match. A command that writes the
	# content to grep through a pipe would then end with SIGPIPE, because more
	# content is left than the pipe holds.
	{
		echo "# Blame ignore file"
		printf '# %0200000d\n' 0
	} >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"

	local target_hash
	target_hash=$(git rev-parse HEAD)
	{
		echo "$target_hash  # Add blame file"
		cat .git-blame-ignore-revs
	} >tmp && mv tmp .git-blame-ignore-revs
	git add .git-blame-ignore-revs
	# The working tree lacks the hash, so ach checks the staged content.
	git show HEAD:.git-blame-ignore-revs >.git-blame-ignore-revs

	local staged_before
	staged_before=$(git rev-parse :.git-blame-ignore-revs)

	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	assert_output_contains "Hash ${target_hash:0:7} already in staged .git-blame-ignore-revs."
	[ "$(git rev-parse HEAD:.git-blame-ignore-revs)" = "$staged_before" ]
}

@test "ach: keeps staged changes to paths whose names contain glob characters" {
	setup_git_repo
	echo "# Blame ignore file" >.git-blame-ignore-revs
	echo "page" >'[id].tsx'
	echo "doc" >d.tsx
	git add .git-blame-ignore-revs '[id].tsx' d.tsx
	git commit -m "Add files"

	# As a glob, [id].tsx also matches d.tsx.
	echo "page change" >>'[id].tsx'
	echo "doc change" >>d.tsx
	git add '[id].tsx' d.tsx

	local status_before
	status_before=$(git status --porcelain)

	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ "$(git status --porcelain)" = "$status_before" ]
}

@test "ach: keeps new staged files whose names contain glob characters" {
	setup_git_repo
	echo "# Blame ignore file" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"

	# As a glob, [id].tsx also matches d.tsx.
	echo "page" >'[id].tsx'
	echo "doc" >d.tsx
	git add '[id].tsx' d.tsx

	local status_before
	status_before=$(git status --porcelain)

	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ "$(git status --porcelain)" = "$status_before" ]
}

@test "ach: restores FILE, its index entry and the stash when the commit fails after the append" {
	setup_git_repo
	# The blank line at the end of the file is lost by a restore that drops
	# trailing newlines.
	printf '%s\n' "# Blame ignore file" "" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"
	# The unstaged change to FILE makes ach stash it before the append.
	{
		echo "# My uncommitted header"
		cat .git-blame-ignore-revs
	} >tmp && mv tmp .git-blame-ignore-revs
	echo "unrelated work" >unrelated.txt
	git add unrelated.txt

	# Blob ids compare exact bytes, including the trailing newlines that $(cat)
	# strips.
	local content_before staged_before stash_before status_before
	content_before=$(git hash-object .git-blame-ignore-revs)
	staged_before=$(git rev-parse :.git-blame-ignore-revs)
	stash_before=$(git stash list)
	status_before=$(git status --porcelain)

	run --separate-stderr env PATH="$(failing_git_path commit)" "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_output_contains "Stashing uncommitted changes"
	assert_output_contains "Restoring stashed changes"
	assert_stderr_not_contains "Error:"
	[ "$(git hash-object .git-blame-ignore-revs)" = "$content_before" ]
	[ "$(git rev-parse :.git-blame-ignore-revs)" = "$staged_before" ]
	[ "$(git stash list)" = "$stash_before" ]
	[ "$(git status --porcelain)" = "$status_before" ]
}

@test "ach: restores FILE exactly and unstages the added line when the commit fails" {
	setup_git_repo
	printf '%s\n' "# Blame ignore file" "" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"

	local content_before staged_before
	content_before=$(git hash-object .git-blame-ignore-revs)
	staged_before=$(git rev-parse :.git-blame-ignore-revs)

	run --separate-stderr env PATH="$(failing_git_path commit)" "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_output_not_contains "Stashing"
	assert_output_contains "Restoring original .git-blame-ignore-revs"
	[ "$(git hash-object .git-blame-ignore-revs)" = "$content_before" ]
	[ "$(git rev-parse :.git-blame-ignore-revs)" = "$staged_before" ]
}

@test "ach: removes the FILE it created when the commit fails" {
	setup_git_repo

	run --separate-stderr env PATH="$(failing_git_path commit)" "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_output_contains "Creating .git-blame-ignore-revs"
	assert_output_contains "Removing .git-blame-ignore-revs"
	[ ! -e .git-blame-ignore-revs ]
	[ -z "$(git status --porcelain)" ]
}

@test "ach: removes the FILE it created when git add fails" {
	setup_git_repo

	run --separate-stderr env PATH="$(failing_git_path add)" "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_output_contains "Removing .git-blame-ignore-revs"
	[ ! -e .git-blame-ignore-revs ]
	[ -z "$(git status --porcelain)" ]
}

@test "ach: names the stash and the command that restores it when cleanup cannot pop it" {
	setup_git_repo
	printf '%s\n' "# Blame ignore file" "" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"
	{
		echo "# My uncommitted header"
		cat .git-blame-ignore-revs
	} >tmp && mv tmp .git-blame-ignore-revs

	local content_before
	content_before=$(git hash-object .git-blame-ignore-revs)

	run --separate-stderr env PATH="$(failing_git_path commit "stash pop")" "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: Could not restore your uncommitted changes to .git-blame-ignore-revs."
	assert_stderr_contains "Your changes are in stash@{0}. Restore them with: git stash pop"
	assert_stderr_not_contains "--index"
	[ "$(git stash list)" = "stash@{0}: On main: ach: auto-stash .git-blame-ignore-revs" ]

	# The command that the error names brings the changes back.
	git stash pop
	[ "$(git hash-object .git-blame-ignore-revs)" = "$content_before" ]
}

@test "ach: skips a FILE whose working tree and staged content both have the hash" {
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
	assert_output_contains "file1.txt"
	assert_output_contains "file2.txt"

	# Run ach
	run "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]

	# Both files should still be staged
	run git diff --cached --name-only
	assert_output_contains "file1.txt"
	assert_output_contains "file2.txt"
}

@test "ach: adds a newline before the hash when FILE does not end in one" {
	setup_git_repo
	printf '%s' "# Blame ignore file" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"
	local target_hash
	target_hash=$(git rev-parse HEAD)

	run "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	local expected_blob
	expected_blob=$(printf '%s\n' "# Blame ignore file" "$target_hash  # Add blame file" | git hash-object --stdin)
	[ "$(git rev-parse HEAD:.git-blame-ignore-revs)" = "$expected_blob" ]
	# git blame accepts the committed file, and a second run finds the hash.
	git blame --ignore-revs-file .git-blame-ignore-revs README.md
	run "$SCRIPTS_DIR/ach" "$target_hash"
	[ "$status" -eq 0 ]
	assert_output_contains "already exists"
}

@test "ach: restores the stash after a failed commit when older stash entries are long" {
	setup_git_repo
	printf '%s\n' "# Blame ignore file" "" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"
	# The older entries make git stash list print more than a pipe holds, so
	# a reader that stops after the first line ends git stash list with
	# SIGPIPE.
	local long_message
	long_message=$(printf '%0100000d' 0)
	echo "first" >>README.md
	git stash push -m "$long_message"
	echo "second" >>README.md
	git stash push -m "$long_message"
	{
		echo "# My uncommitted header"
		cat .git-blame-ignore-revs
	} >tmp && mv tmp .git-blame-ignore-revs

	local content_before stash_before
	content_before=$(git hash-object .git-blame-ignore-revs)
	stash_before=$(git stash list)

	run --separate-stderr env PATH="$(failing_git_path commit)" "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_output_contains "Restoring stashed changes"
	[ "$(git hash-object .git-blame-ignore-revs)" = "$content_before" ]
	[ "$(git stash list)" = "$stash_before" ]
}

@test "ach: keeps the staged content of other files that also have unstaged changes" {
	setup_git_repo
	echo "notes" >notes.txt
	echo "gone" >gone.txt
	git add notes.txt gone.txt
	git commit -m "Add files"
	echo "staged-only-version" >notes.txt
	git add notes.txt
	echo "working-version" >notes.txt
	git rm --quiet gone.txt
	# A staged new file that is no longer in the working tree cannot be
	# staged again from the working tree.
	echo "added" >added.txt
	git add added.txt
	rm added.txt

	local notes_before added_before status_before
	notes_before=$(git rev-parse :notes.txt)
	added_before=$(git rev-parse :added.txt)
	status_before=$(git status --porcelain)

	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ "$(git diff-tree --no-commit-id --name-only -r HEAD)" = ".git-blame-ignore-revs" ]
	[ "$(git rev-parse :notes.txt)" = "$notes_before" ]
	[ "$(git rev-parse :added.txt)" = "$added_before" ]
	[ "$(cat notes.txt)" = "working-version" ]
	[ "$(git status --porcelain)" = "$status_before" ]
}

@test "ach: keeps the staged content of other files when the commit fails" {
	setup_git_repo
	echo "staged-only-version" >notes.txt
	git add notes.txt
	echo "working-version" >notes.txt

	local notes_before status_before
	notes_before=$(git rev-parse :notes.txt)
	status_before=$(git status --porcelain)

	run --separate-stderr env PATH="$(failing_git_path commit)" "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	[ "$(git rev-parse :notes.txt)" = "$notes_before" ]
	[ "$(cat notes.txt)" = "working-version" ]
	[ "$(git status --porcelain)" = "$status_before" ]
}

@test "ach: keeps the conflict of another file that is unmerged" {
	setup_git_repo
	echo "base" >conflict.txt
	git add conflict.txt
	git commit -m "Add conflict file"
	echo "stashed" >conflict.txt
	git stash push
	echo "committed" >conflict.txt
	git commit -am "Change conflict file"
	run git stash pop
	[ "$status" -ne 0 ]
	git stash drop

	local entries_before
	entries_before=$(git ls-files -s -- conflict.txt)
	[ "$(git ls-files -u -- conflict.txt)" = "$entries_before" ]

	run "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	[ "$(git diff-tree --no-commit-id --name-only -r HEAD)" = ".git-blame-ignore-revs" ]
	[ "$(git ls-files -s -- conflict.txt)" = "$entries_before" ]
}

@test "ach: restores the unstaged changes to FILE when a rename is staged" {
	setup_git_repo
	printf '%s\n' "# Blame ignore file" "" >.git-blame-ignore-revs
	echo "old content" >old.txt
	git add .git-blame-ignore-revs old.txt
	git commit -m "Add blame file"
	git config diff.renames true
	git mv old.txt new.txt
	{
		echo "# My uncommitted header"
		cat .git-blame-ignore-revs
	} >tmp && mv tmp .git-blame-ignore-revs
	local target_hash
	target_hash=$(git rev-parse HEAD)

	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	assert_output_contains "Restored your uncommitted changes"
	[ "$(git diff-tree --no-commit-id --name-only -r HEAD)" = ".git-blame-ignore-revs" ]
	grep -q "My uncommitted header" .git-blame-ignore-revs
	grep -q "$target_hash" .git-blame-ignore-revs
	[ -z "$(git stash list)" ]
	[ "$(git status --porcelain)" = "$(printf '%s\n' " M .git-blame-ignore-revs" "R  old.txt -> new.txt")" ]
}

@test "ach: rejects a FILE that git names another way" {
	setup_git_repo
	echo "# Blame ignore file" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"
	echo "staged-line" >>.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	echo "unstaged-line" >>.git-blame-ignore-revs

	local status_before head_before file_arg
	status_before=$(git status --porcelain)
	head_before=$(git rev-parse HEAD)

	for file_arg in ./.git-blame-ignore-revs "$PWD/.git-blame-ignore-revs" dir//file dir/../file; do
		run --separate-stderr "$SCRIPTS_DIR/ach" HEAD "$file_arg"
		[ "$status" -eq 1 ]
		assert_stderr_contains "Error: Cannot use '$file_arg' as FILE"
		[ -z "$output" ]
	done
	[ "$(git rev-parse HEAD)" = "$head_before" ]
	[ -z "$(git stash list)" ]
	[ "$(git status --porcelain)" = "$status_before" ]
}

@test "ach: treats a staged file whose name matches FILE as a pattern as another file" {
	setup_git_repo
	# As a regular expression, .git-blame-ignore-revs also matches this name.
	echo "unrelated work" >xgit-blame-ignore-revs
	git add xgit-blame-ignore-revs

	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	[ "$(git diff-tree --no-commit-id --name-only -r HEAD)" = ".git-blame-ignore-revs" ]
	[ "$(git diff --cached --name-only)" = "xgit-blame-ignore-revs" ]
}

@test "ach: names the conflict and how to finish when the unstaged changes to FILE conflict" {
	setup_git_repo
	echo "# Blame ignore file" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"
	# A line at the end of FILE conflicts with the line that ach adds there.
	echo "my manual line" >>.git-blame-ignore-revs

	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	assert_stderr_contains "Warning: Could not cleanly restore your uncommitted changes to .git-blame-ignore-revs."
	assert_stderr_contains ".git-blame-ignore-revs now has conflict markers."
	assert_stderr_contains "run 'git restore --staged -- .git-blame-ignore-revs', and then run 'git stash drop'"
	grep -q "^<<<<<<<" .git-blame-ignore-revs

	# The steps that the warning names leave the resolved content unstaged
	# and no stash entry.
	local committed resolved
	committed=$(git show HEAD:.git-blame-ignore-revs)
	resolved=$(printf '%s\n' "$committed" "my manual line")
	echo "$resolved" >.git-blame-ignore-revs
	git restore --staged -- .git-blame-ignore-revs
	git stash drop
	[ "$(git status --porcelain)" = " M .git-blame-ignore-revs" ]
	[ "$(cat .git-blame-ignore-revs)" = "$resolved" ]
	[ -z "$(git stash list)" ]
}

@test "ach: names the stash but no conflict when restoring the unstaged changes to FILE fails without one" {
	setup_git_repo
	printf '%s\n' "# Blame ignore file" "" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"
	{
		echo "# My uncommitted header"
		cat .git-blame-ignore-revs
	} >tmp && mv tmp .git-blame-ignore-revs
	local target_hash
	target_hash=$(git rev-parse HEAD)

	# A git stash apply that fails before it merges leaves no unmerged entry,
	# so FILE has no conflict markers for the warning to name.
	run --separate-stderr env PATH="$(failing_git_path "stash apply")" "$SCRIPTS_DIR/ach"
	[ "$status" -eq 0 ]
	assert_output_contains "Successfully updated and committed .git-blame-ignore-revs."
	assert_stderr_contains "Warning: Could not cleanly restore your uncommitted changes to .git-blame-ignore-revs."
	assert_stderr_contains "Your changes are in: git stash show -p stash@{0}"
	assert_stderr_not_contains "conflict markers"
	[ "$(git stash list)" = "stash@{0}: On main: ach: auto-stash .git-blame-ignore-revs" ]
	[ -z "$(git status --porcelain)" ]

	# The stash entry still holds the unstaged changes.
	git stash pop
	grep -q "My uncommitted header" .git-blame-ignore-revs
	grep -q "$target_hash" .git-blame-ignore-revs
}

@test "ach: fails without changes when FILE is a symbolic link to a missing file" {
	setup_git_repo
	ln -s shared/revs .git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Link blame file"
	mkdir shared

	run --separate-stderr "$SCRIPTS_DIR/ach"
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: Cannot add the hash to .git-blame-ignore-revs, because it exists and is not a regular file."
	[ -L .git-blame-ignore-revs ]
	[ ! -e shared/revs ]
	[ -z "$(git status --porcelain)" ]
}

@test "ach: fails with an error when FILE cannot be read" {
	setup_git_repo
	echo "# Blame ignore file" >.git-blame-ignore-revs
	git add .git-blame-ignore-revs
	git commit -m "Add blame file"
	chmod 000 .git-blame-ignore-revs
	if [ -r .git-blame-ignore-revs ]; then
		chmod 644 .git-blame-ignore-revs
		skip "this user can read a file with mode 000"
	fi

	run --separate-stderr "$SCRIPTS_DIR/ach"
	chmod 644 .git-blame-ignore-revs
	[ "$status" -eq 1 ]
	[ "$stderr" = "$(printf '%s\n' "Error: Cannot read .git-blame-ignore-revs." "Make it readable, then run ach again.")" ]
}
