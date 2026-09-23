#!/usr/bin/env bats

load 'test_helper'

# A failing [[ ]] that is not the last command of a test does not fail the
# test under bash 3.2, so each [[ ]] check below ends with "|| false".

# Creates stale-branch with an upstream on a local bare remote, then deletes
# that upstream so that the branch is reported as [gone]. The branch has a
# commit that main lacks, so only the [gone] pass selects it.
setup_gone_branch() {
	git init --bare "$TEST_TEMP_DIR/remote.git"
	git remote add origin "$TEST_TEMP_DIR/remote.git"
	git push -u origin main
	git switch -c stale-branch
	git commit --allow-empty -m "Stale work"
	git push -u origin stale-branch
	git switch main
	git push origin --delete stale-branch
}

@test "git-shed: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/git-shed"
}

@test "git-shed: --help displays usage information on stdout" {
	run --separate-stderr "$SCRIPTS_DIR/git-shed" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "TARGET_BRANCH"
	[ -z "$stderr" ]
}

@test "git-shed: -h displays usage information on stdout" {
	run --separate-stderr "$SCRIPTS_DIR/git-shed" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "TARGET_BRANCH"
	[ -z "$stderr" ]
}

@test "git-shed: help follows the standard layout" {
	run --separate-stderr "$SCRIPTS_DIR/git-shed" --help
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "Usage: git-shed [-y] [--dry-run] [--gone-only] [--] [TARGET_BRANCH]" ]
	[[ "$output" == *$'\nArguments:\n'*$'\nOptions:\n'*$'\nExamples:\n'* ]] || false
	[[ "$output" != *"Description:"* ]] || false
	# -h, --help is the last entry under Options:.
	[[ "$output" == *$'\n  -h, --help '*$'Show this help message and exit.\n\nExamples:\n'* ]] || false
	[[ "$output" == *$'\n  git-shed -- -wip '* ]] || false
}

@test "git-shed: --help mentions --gone-only" {
	run "$SCRIPTS_DIR/git-shed" --help
	[ "$status" -eq 0 ]
	assert_output_contains "--gone-only"
}

@test "git-shed: rejects dash-prefixed target without --" {
	setup_git_repo

	run --separate-stderr "$SCRIPTS_DIR/git-shed" --dry-run -y -wip
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unknown option '-wip'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "git-shed: rejects a second target branch" {
	setup_git_repo
	git branch develop

	run --separate-stderr "$SCRIPTS_DIR/git-shed" --dry-run -y main develop
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Multiple target branches specified: 'main' and 'develop'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "git-shed: rejects a second target branch after --" {
	setup_git_repo
	git branch develop

	run --separate-stderr "$SCRIPTS_DIR/git-shed" --dry-run -y -- main develop
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Multiple target branches specified: 'main' and 'develop'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "git-shed: rejects target branches on both sides of --" {
	setup_git_repo
	git branch develop

	run --separate-stderr "$SCRIPTS_DIR/git-shed" --dry-run -y main -- develop
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Multiple target branches specified: 'main' and 'develop'"* ]] || false
	[ -z "$output" ]
}

@test "git-shed: --help after extra arguments still prints help" {
	run --separate-stderr "$SCRIPTS_DIR/git-shed" main develop --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	[ -z "$stderr" ]
}

@test "git-shed: fails with an install hint when git is not installed" {
	run --separate-stderr env PATH="$(restricted_path bash basename cat)" "$SCRIPTS_DIR/git-shed" --dry-run -y
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"'git' is required"* ]] || false
	[[ "$stderr" == *"https://git-scm.com/downloads"* ]] || false
	[ -z "$output" ]
}

@test "git-shed: -h works when git is not installed" {
	run --separate-stderr env PATH="$(restricted_path bash basename cat)" "$SCRIPTS_DIR/git-shed" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	[ -z "$stderr" ]
}

@test "git-shed: fails when target branch does not exist" {
	setup_git_repo

	run --separate-stderr "$SCRIPTS_DIR/git-shed" nonexistent-branch
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Branch 'nonexistent-branch' does not exist."* ]] || false
	[ -z "$output" ]
}

# GIT_CEILING_DIRECTORIES stops git from finding a repository above
# TEST_TEMP_DIR, so these tests do not depend on where the temporary
# directory is created.
@test "git-shed: fails outside a git repository instead of reporting a missing branch" {
	mkdir not-a-repo
	cd not-a-repo

	run --separate-stderr env GIT_CEILING_DIRECTORIES="$TEST_TEMP_DIR" "$SCRIPTS_DIR/git-shed" -y --dry-run
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Not inside a git repository."* ]] || false
	[[ "$stderr" != *"does not exist"* ]] || false
	[ -z "$output" ]
}

@test "git-shed: --gone-only fails outside a git repository instead of continuing after the fetch" {
	mkdir not-a-repo
	cd not-a-repo

	run --separate-stderr env GIT_CEILING_DIRECTORIES="$TEST_TEMP_DIR" "$SCRIPTS_DIR/git-shed" -y --dry-run --gone-only
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Not inside a git repository."* ]] || false
	[[ "$stderr" != *"Warning:"* ]] || false
	assert_output_not_contains "Local branches:"
}

@test "git-shed: a failed fetch inside a repository is a warning" {
	setup_git_repo
	git remote add origin "$TEST_TEMP_DIR/missing.git"

	run --separate-stderr "$SCRIPTS_DIR/git-shed" -y --dry-run
	[ "$status" -eq 0 ]
	[[ "$stderr" == *"Warning: git fetch --prune failed"* ]] || false
	[[ "$stderr" != *"Error:"* ]] || false
	assert_output_contains "Done."
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

@test "git-shed: -- with no target branch defaults to main" {
	setup_git_repo

	run --separate-stderr "$SCRIPTS_DIR/git-shed" --dry-run -y --
	[ "$status" -eq 0 ]
	assert_output_contains "No local branches merged into 'main' found."
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

@test "git-shed: answering no at the merged-branch prompt keeps the branch" {
	setup_git_repo
	git switch -c feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git switch main
	git merge feature-branch

	run "$SCRIPTS_DIR/git-shed" main <<<"n"
	[ "$status" -eq 0 ]
	assert_output_contains "Skipping deletion of merged branches."
	git show-ref --verify --quiet refs/heads/feature-branch
}

@test "git-shed: answering yes at the merged-branch prompt deletes the branch" {
	setup_git_repo
	git switch -c feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git switch main
	git merge feature-branch

	run "$SCRIPTS_DIR/git-shed" main <<<"y"
	[ "$status" -eq 0 ]
	assert_output_contains "Deleted branch feature-branch"
	run ! git show-ref --verify --quiet refs/heads/feature-branch
}

@test "git-shed: a yes without a trailing newline at the merged-branch prompt deletes the branch" {
	setup_git_repo
	git switch -c feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git switch main
	git merge feature-branch

	run --separate-stderr "$SCRIPTS_DIR/git-shed" main < <(printf 'y')
	[ "$status" -eq 0 ]
	assert_stderr_not_contains "Error:"
	assert_output_contains "Deleted branch feature-branch"
	run ! git show-ref --verify --quiet refs/heads/feature-branch
}

@test "git-shed: answering no at the stale-branch prompt keeps the branch" {
	mkdir repo
	cd repo
	setup_git_repo
	setup_gone_branch

	run "$SCRIPTS_DIR/git-shed" main <<<"n"
	[ "$status" -eq 0 ]
	assert_output_contains "stale-branch"
	assert_output_contains "Skipping deletion of stale branches."
	git show-ref --verify --quiet refs/heads/stale-branch
}

@test "git-shed: answering yes at the stale-branch prompt deletes the branch" {
	mkdir repo
	cd repo
	setup_git_repo
	setup_gone_branch

	run "$SCRIPTS_DIR/git-shed" main <<<"y"
	[ "$status" -eq 0 ]
	assert_output_contains "Deleted branch stale-branch"
	run ! git show-ref --verify --quiet refs/heads/stale-branch
}

@test "git-shed: a yes without a trailing newline at the stale-branch prompt deletes the branch" {
	mkdir repo
	cd repo
	setup_git_repo
	setup_gone_branch

	run --separate-stderr "$SCRIPTS_DIR/git-shed" main < <(printf 'y')
	[ "$status" -eq 0 ]
	assert_stderr_not_contains "Error:"
	assert_output_contains "Deleted branch stale-branch"
	run ! git show-ref --verify --quiet refs/heads/stale-branch
}

@test "git-shed: fails when stdin ends before the merged-branch prompt is answered" {
	setup_git_repo
	git switch -c feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git switch main
	git merge feature-branch

	run --separate-stderr "$SCRIPTS_DIR/git-shed" main </dev/null
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: Cannot read confirmation from stdin; rerun with -y to delete without prompting."
	assert_output_contains "Branches fully merged into 'main':"
	assert_output_not_contains "Done."
	git show-ref --verify --quiet refs/heads/feature-branch
}

@test "git-shed: fails when stdin is closed at the merged-branch prompt" {
	setup_git_repo
	git switch -c feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git switch main
	git merge feature-branch

	# With "<&-" on the run line, file descriptor 0 would be closed when run
	# creates the pipe that captures output. The read end of that pipe would
	# then become git-shed's stdin, so read would either consume git-shed's
	# own output or block, and the test would hang. This function closes
	# stdin for git-shed alone.
	git_shed_with_closed_stdin() {
		"$SCRIPTS_DIR/git-shed" main <&-
	}

	run --separate-stderr git_shed_with_closed_stdin
	[ "$status" -eq 1 ]
	# The exact match also shows that the diagnostic from bash's read builtin,
	# which lacks the "Error:" prefix, does not reach stderr.
	[ "$stderr" = "Error: Cannot read confirmation from stdin; rerun with -y to delete without prompting." ]
	assert_output_not_contains "Done."
	git show-ref --verify --quiet refs/heads/feature-branch
}

@test "git-shed: fails when stdin ends before the stale-branch prompt is answered" {
	mkdir repo
	cd repo
	setup_git_repo
	setup_gone_branch

	run --separate-stderr "$SCRIPTS_DIR/git-shed" main </dev/null
	[ "$status" -eq 1 ]
	assert_stderr_contains "Error: Cannot read confirmation from stdin; rerun with -y to delete without prompting."
	assert_output_contains "Branches with deleted upstream ([gone]):"
	assert_output_not_contains "Done."
	git show-ref --verify --quiet refs/heads/stale-branch
}

@test "git-shed: warns on stderr before it force-removes a dirty linked worktree" {
	mkdir repo
	cd repo
	setup_git_repo
	git switch -c feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git switch main
	git merge feature-branch
	git worktree add "$TEST_TEMP_DIR/feature-worktree" feature-branch
	echo "uncommitted" >>"$TEST_TEMP_DIR/feature-worktree/feature.txt"

	run --separate-stderr "$SCRIPTS_DIR/git-shed" -y main
	[ "$status" -eq 0 ]
	[[ "$stderr" == *"Warning: could not remove worktree '"*"feature-worktree' (it may be dirty or locked); retrying with --force..."* ]] || false
	[[ "$output" != *"Warning:"* ]] || false
	[ ! -d "$TEST_TEMP_DIR/feature-worktree" ]
	run ! git show-ref --verify --quiet refs/heads/feature-branch
}

@test "git-shed: warns on stderr before it removes a locked linked worktree with --force --force" {
	mkdir repo
	cd repo
	setup_git_repo
	git switch -c feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git switch main
	git merge feature-branch
	git worktree add "$TEST_TEMP_DIR/feature-worktree" feature-branch
	# A single --force does not remove a locked worktree.
	git worktree lock "$TEST_TEMP_DIR/feature-worktree"

	run --separate-stderr "$SCRIPTS_DIR/git-shed" -y main
	[ "$status" -eq 0 ]
	[[ "$stderr" == *"Warning: could not remove worktree '"*"feature-worktree' with --force; retrying with --force --force..."* ]] || false
	[[ "$output" != *"Warning:"* ]] || false
	[ ! -d "$TEST_TEMP_DIR/feature-worktree" ]
	run ! git show-ref --verify --quiet refs/heads/feature-branch
}

@test "git-shed: continues and exits 1 when a merged branch cannot be deleted" {
	setup_git_repo
	git branch feature
	git branch merged2
	git switch -c merged1
	git commit --allow-empty -m "Merged work"
	git switch main
	git merge merged1
	# git branch -d refuses merged1 because the current branch lacks its
	# commit. merged2 points to a commit that the current branch contains.
	git switch feature

	run --separate-stderr "$SCRIPTS_DIR/git-shed" -y main
	[ "$status" -eq 1 ]
	assert_stderr_contains "Warning: could not delete merged branch 'merged1'."
	[ "${lines[${#lines[@]} - 1]}" = "Done." ]
	git show-ref --verify --quiet refs/heads/merged1
	# merged2 sorts after merged1, so its deletion shows that the loop continued.
	run ! git show-ref --verify --quiet refs/heads/merged2
}

@test "git-shed: exits 1 when a stale branch cannot be deleted" {
	mkdir repo
	cd repo
	setup_git_repo
	setup_gone_branch
	# A rebase that stops in a linked worktree detaches its HEAD, so git-shed
	# finds no worktree to remove, and git branch -D still refuses the branch.
	git worktree add "$TEST_TEMP_DIR/rebase-worktree" stale-branch
	run -1 git -C "$TEST_TEMP_DIR/rebase-worktree" rebase --exec false HEAD~1

	run --separate-stderr "$SCRIPTS_DIR/git-shed" -y --gone-only
	[ "$status" -eq 1 ]
	assert_stderr_contains "Warning: could not delete stale branch 'stale-branch'."
	[ "${lines[${#lines[@]} - 1]}" = "Done." ]
	git show-ref --verify --quiet refs/heads/stale-branch
}

# git worktree remove refuses the main worktree even with --force --force, so
# git-shed, run from a linked worktree, cannot remove the main worktree when
# the main worktree has the branch checked out.
@test "git-shed: skips a merged branch and exits 1 when its worktree cannot be removed" {
	mkdir repo
	cd repo
	setup_git_repo
	git switch -c feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git switch main
	git merge feature-branch
	git switch feature-branch
	git worktree add "$TEST_TEMP_DIR/linked-worktree" main
	cd "$TEST_TEMP_DIR/linked-worktree"

	run --separate-stderr "$SCRIPTS_DIR/git-shed" -y main
	[ "$status" -eq 1 ]
	assert_stderr_contains "Warning: skipping merged branch 'feature-branch' (worktree removal failed)."
	[ "${lines[${#lines[@]} - 1]}" = "Done." ]
	[ -d "$TEST_TEMP_DIR/repo" ]
	git show-ref --verify --quiet refs/heads/feature-branch
}

@test "git-shed: skips a stale branch and exits 1 when its worktree cannot be removed" {
	mkdir repo
	cd repo
	setup_git_repo
	setup_gone_branch
	git switch stale-branch
	git worktree add "$TEST_TEMP_DIR/linked-worktree" main
	cd "$TEST_TEMP_DIR/linked-worktree"

	run --separate-stderr "$SCRIPTS_DIR/git-shed" -y --gone-only
	[ "$status" -eq 1 ]
	assert_stderr_contains "Warning: skipping stale branch 'stale-branch' (worktree removal failed)."
	[ "${lines[${#lines[@]} - 1]}" = "Done." ]
	[ -d "$TEST_TEMP_DIR/repo" ]
	git show-ref --verify --quiet refs/heads/stale-branch
}

@test "git-shed: detached HEAD still surfaces merged branches" {
	# When HEAD is detached, `git branch --show-current` is empty. The
	# merged-branch filter must not pass that empty string as a `grep -e`
	# pattern, or every line is matched and `-v` filters them all out,
	# silently disabling merged-branch cleanup.
	setup_git_repo
	git switch -c feature-branch
	echo "feature" >feature.txt
	git add feature.txt
	git commit -m "Add feature"
	git switch main
	git merge feature-branch
	# Detach HEAD onto the merge commit so `git branch --show-current` is empty.
	git checkout --detach HEAD

	run "$SCRIPTS_DIR/git-shed" --dry-run -y main
	[ "$status" -eq 0 ]
	assert_output_contains "feature-branch"
}

@test "git-shed: bare repo does not hard-fail" {
	# Build a non-bare source, create a merged feature branch, then clone
	# bare so the bare clone has refs/heads/main and refs/heads/feature
	# but no working tree. `remove_linked_worktree_for_branch` must
	# tolerate this rather than aborting under `set -e`.
	local source_dir
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
