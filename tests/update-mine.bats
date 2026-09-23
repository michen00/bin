#!/usr/bin/env bats

load 'test_helper'

# A failing [[ ]] that is not the last command of a test does not fail the
# test under bash 3.2, so each [[ ]] check below ends with "|| false".

# Stub gh so update-mine can run without network/auth.
# Args become the lines emitted on `gh pr list` / `gh api .../branches`.
# Also prepends SCRIPTS_DIR so update-mine can find sibling scripts (e.g. mergewith).
stub_gh() {
	mkdir -p "$TEST_TEMP_DIR/stubs"
	cat >"$TEST_TEMP_DIR/stubs/gh" <<EOF
#!/usr/bin/env bash
case "\$1" in
  pr|api) printf '%s\n' $(printf '"%s" ' "$@") ;;
  *) exit 0 ;;
esac
EOF
	chmod +x "$TEST_TEMP_DIR/stubs/gh"
	export PATH="$TEST_TEMP_DIR/stubs:$SCRIPTS_DIR:$PATH"
}

# Helper to replace mergewith with a stub that fails and leaves the index
# locked, so that git cannot check out the starting ref again on exit. Call
# stub_gh as well, because it puts the stubs directory first on PATH.
stub_failing_mergewith() {
	mkdir -p "$TEST_TEMP_DIR/stubs"
	cat >"$TEST_TEMP_DIR/stubs/mergewith" <<'EOF'
#!/usr/bin/env bash
touch "$(git rev-parse --git-dir)/index.lock"
exit 1
EOF
	chmod +x "$TEST_TEMP_DIR/stubs/mergewith"
}

# Helper to give the test repository a local bare repository as origin, with
# main pushed and tracked, so that mergewith can pull, fetch and merge
setup_origin() {
	git init --bare --initial-branch=main "$TEST_TEMP_DIR/origin.git"
	git remote add origin "$TEST_TEMP_DIR/origin.git"
	git push -u origin main
}

# Helper to create a branch from main with one commit of its own and push it
# Parameters:
#   $1 - branch name
push_feature_branch() {
	git checkout -b "$1" main
	echo "$1" >"$1.txt"
	git add "$1.txt"
	git commit -m "$1 work"
	git push -u origin "$1"
	git checkout main
}

# Helper to add a commit to main and push it, so that main has changes that
# the feature branches do not have yet
advance_main() {
	echo "main change" >main.txt
	git add main.txt
	git commit -m "main work"
	git push origin main
}

@test "update-mine: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/update-mine"
}

@test "update-mine: -h displays usage information on stdout" {
	run --separate-stderr "$SCRIPTS_DIR/update-mine" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	[ -z "$stderr" ]
}

@test "update-mine: --help displays usage information on stdout" {
	run --separate-stderr "$SCRIPTS_DIR/update-mine" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "reference_branch"
	[ -z "$stderr" ]
}

@test "update-mine: --help lists sections in order with -h, --help last" {
	run "$SCRIPTS_DIR/update-mine" --help
	[ "$status" -eq 0 ]
	[[ "$output" == "Usage: update-mine "*"Arguments:"*"Options:"*"Examples:"* ]] || false
	[[ "$output" == *"  -h, --help  Show this help message and exit."$'\n\n'"Examples:"* ]] || false
}

@test "update-mine: -h works when git is not installed" {
	# usage prints the help with cat, so cat must stay available.
	run --separate-stderr env PATH="$(restricted_path bash basename cat)" "$SCRIPTS_DIR/update-mine" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
}

@test "update-mine: fails with exit 2 when no reference branch specified" {
	run --separate-stderr "$SCRIPTS_DIR/update-mine"
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Missing <reference_branch> argument."* ]] || false
	[[ "$stderr" == *"Use --help for usage information."* ]] || false
	[ -z "$output" ]
}

@test "update-mine: fails with exit 2 when two reference branches specified" {
	run --separate-stderr "$SCRIPTS_DIR/update-mine" main develop
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Multiple reference branches specified: 'main' and 'develop'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "update-mine: fails with exit 2 when an empty reference branch precedes another" {
	run --separate-stderr "$SCRIPTS_DIR/update-mine" '' main
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Multiple reference branches specified: '' and 'main'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "update-mine: fails with exit 1 when the reference branch is empty" {
	run --separate-stderr "$SCRIPTS_DIR/update-mine" ''
	[ "$status" -eq 1 ]
	[ "$stderr" = "Error: The reference branch name is empty." ]
	[ -z "$output" ]
}

@test "update-mine: fails with exit 2 on unknown option" {
	run --separate-stderr "$SCRIPTS_DIR/update-mine" --unknown main
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unknown option '--unknown'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "update-mine: fails with exit 2 on unknown short option" {
	run --separate-stderr "$SCRIPTS_DIR/update-mine" -x main
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unknown option '-x'"* ]] || false
	[ -z "$output" ]
}

@test "update-mine: fails when git is not installed" {
	run --separate-stderr env PATH="$(restricted_path bash basename)" "$SCRIPTS_DIR/update-mine" main
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"'git' is required"* ]] || false
	[ -z "$output" ]
}

@test "update-mine: fails when not in a git repository" {
	# We're in TEST_TEMP_DIR which is not a git repo
	run --separate-stderr "$SCRIPTS_DIR/update-mine" main
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Not inside a Git repository."* ]] || false
	[ -z "$output" ]
}

@test "update-mine: fails when gh is not installed" {
	setup_git_repo

	run --separate-stderr env PATH="$(restricted_path bash basename git)" "$SCRIPTS_DIR/update-mine" main
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"'gh' (GitHub CLI) is required"* ]] || false
	[ -z "$output" ]
}

@test "update-mine: fails when mergewith is not on PATH" {
	setup_git_repo
	stub_gh feature-a

	run --separate-stderr env PATH="$(restricted_path bash basename git gh)" "$SCRIPTS_DIR/update-mine" main
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"'mergewith' is required"* ]] || false
	[ -z "$output" ]
}

@test "update-mine: accepts --debug flag and traces to stderr" {
	setup_git_repo
	stub_gh

	run --separate-stderr "$SCRIPTS_DIR/update-mine" --debug main
	[ "$status" -eq 0 ]
	assert_output_contains "Fetching branches with open PRs authored by you..."
	assert_output_contains "No branches found."
	[[ "$stderr" == *"git rev-parse --is-inside-work-tree"* ]] || false
}

@test "update-mine: accepts --all flag" {
	setup_git_repo
	stub_gh

	run --separate-stderr "$SCRIPTS_DIR/update-mine" --all main
	[ "$status" -eq 0 ]
	assert_output_contains "Fetching all non-protected branches"
	assert_output_contains "No branches found."
}

@test "update-mine: fails when the remotes cannot be updated" {
	setup_git_repo
	git remote add origin "$TEST_TEMP_DIR/missing.git"
	stub_gh feature-a

	run --separate-stderr "$SCRIPTS_DIR/update-mine" main
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Failed to update the remote-tracking branches."* ]] || false
	assert_output_not_contains "Processing branch"
}

@test "update-mine: merges the reference branch into each branch and pushes it" {
	setup_git_repo
	setup_origin
	push_feature_branch feature-a
	push_feature_branch feature-b
	advance_main
	stub_gh feature-a feature-b

	run --separate-stderr "$SCRIPTS_DIR/update-mine" main
	[ "$status" -eq 0 ]
	assert_output_contains "Successfully updated and pushed branch: feature-a"
	assert_output_contains "Successfully updated and pushed branch: feature-b"
	[[ "$stderr" != *"Warning:"* ]] || false
	git -C "$TEST_TEMP_DIR/origin.git" merge-base --is-ancestor main feature-a
	git -C "$TEST_TEMP_DIR/origin.git" merge-base --is-ancestor main feature-b
	[ "$(git branch --show-current)" = "main" ]
}

@test "update-mine: skips branches checked out in another worktree with a warning" {
	setup_git_repo
	git checkout -b feature-a
	echo "a" >a.txt && git add a.txt && git commit -m "feature-a work"
	git checkout main

	# Hold feature-a in a second worktree so it's "checked out elsewhere"
	git worktree add "$TEST_TEMP_DIR/other-wt" feature-a

	stub_gh feature-a

	run --separate-stderr "$SCRIPTS_DIR/update-mine" main
	# A skipped branch is not a failure.
	[ "$status" -eq 0 ]
	assert_output_contains "Processing branch: feature-a"
	[[ "$stderr" == *"Warning: Skipping branch feature-a because it is checked out in another worktree."* ]] || false
	assert_output_not_contains "Warning:"
	[[ "$stderr" != *"fatal:"* ]] || false
}

@test "update-mine: warns on stderr and exits 1 when a branch cannot be checked out" {
	setup_git_repo
	stub_gh no-such-branch

	run --separate-stderr "$SCRIPTS_DIR/update-mine" main
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Warning: Failed to check out branch no-such-branch. Skipping..."* ]] || false
	assert_output_not_contains "Warning:"
}

@test "update-mine: continues after a merge failure and exits 1" {
	setup_git_repo
	git branch feature-a
	git branch feature-b

	# There is no origin, so mergewith fails for both branches before it
	# starts a merge.
	stub_gh feature-a feature-b

	run --separate-stderr "$SCRIPTS_DIR/update-mine" main
	[ "$status" -eq 1 ]
	assert_output_contains "Processing branch: feature-a"
	assert_output_contains "Processing branch: feature-b"
	[[ "$stderr" == *"Warning: Failed to merge main into feature-a. Skipping..."* ]] || false
	[[ "$stderr" == *"Warning: Failed to merge main into feature-b. Skipping..."* ]] || false
	assert_output_not_contains "Warning:"
	[ "$(git branch --show-current)" = "main" ]
}

@test "update-mine: aborts a conflicting merge and restores the starting branch" {
	setup_git_repo
	setup_origin
	git checkout -b feature-a
	echo "feature-a version" >README.md
	git commit -am "feature-a edits README"
	git push -u origin feature-a
	git checkout main
	echo "main version" >README.md
	git commit -am "main edits README"
	git push origin main
	stub_gh feature-a

	run --separate-stderr "$SCRIPTS_DIR/update-mine" main
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Warning: Failed to merge main into feature-a. Skipping..."* ]] || false
	run git rev-parse -q --verify MERGE_HEAD
	[ "$status" -ne 0 ]
	[ -z "$(git status --porcelain --untracked-files=no)" ]
	[ "$(git branch --show-current)" = "main" ]
}

@test "update-mine: warns on stderr and exits 1 when a push fails" {
	setup_git_repo
	setup_origin
	push_feature_branch feature-a
	advance_main
	printf '#!/bin/sh\nexit 1\n' >"$TEST_TEMP_DIR/origin.git/hooks/pre-receive"
	chmod +x "$TEST_TEMP_DIR/origin.git/hooks/pre-receive"
	stub_gh feature-a

	run --separate-stderr "$SCRIPTS_DIR/update-mine" main
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Warning: Failed to push branch feature-a. Skipping..."* ]] || false
	assert_output_not_contains "Successfully updated and pushed branch"
}

@test "update-mine: restores starting branch after processing" {
	setup_git_repo
	git checkout -b feature-a
	echo "a" >a.txt && git add a.txt && git commit -m "feature-a work"
	git checkout -b starting-branch main

	stub_gh feature-a

	# mergewith will fail (no origin remote configured) — that's fine; we're
	# verifying the trap restores HEAD even when per-branch processing errors out.
	"$SCRIPTS_DIR/update-mine" main || true

	local current
	current=$(git branch --show-current)
	[ "$current" = "starting-branch" ]
}

@test "update-mine: restores detached HEAD after processing" {
	setup_git_repo
	git checkout -b feature-a
	echo "a" >a.txt && git add a.txt && git commit -m "feature-a work"
	git checkout main
	local starting_sha
	starting_sha=$(git rev-parse HEAD)
	git checkout --detach HEAD

	stub_gh feature-a

	"$SCRIPTS_DIR/update-mine" main || true

	# HEAD should still be detached at the original commit.
	run git symbolic-ref -q --short HEAD
	[ "$status" -ne 0 ]
	[ "$(git rev-parse HEAD)" = "$starting_sha" ]
}

@test "update-mine: warns with a remedy when the starting branch cannot be restored" {
	setup_git_repo
	git branch feature-a
	stub_gh feature-a
	stub_failing_mergewith

	run --separate-stderr "$SCRIPTS_DIR/update-mine" main
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Warning: Could not restore the starting branch 'main'. Run 'git checkout main' to return to it."* ]] || false
	assert_output_not_contains "Warning:"
}

@test "update-mine: warns with a remedy when the detached HEAD cannot be restored" {
	setup_git_repo
	git checkout -b feature-a
	echo "a" >a.txt && git add a.txt && git commit -m "feature-a work"
	git checkout --detach main
	local starting_sha
	starting_sha=$(git rev-parse HEAD)
	stub_gh feature-a
	stub_failing_mergewith

	run --separate-stderr "$SCRIPTS_DIR/update-mine" main
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Warning: Could not restore the detached HEAD at '$starting_sha'. Run 'git checkout --detach $starting_sha' to return to it."* ]] || false
	assert_output_not_contains "Warning:"
}
