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
	assert_output_not_contains "Unknown option"
}

@test "update-mine: accepts --all flag" {
	setup_git_repo

	# This will fail because gh is not configured, but it should accept the flag
	run "$SCRIPTS_DIR/update-mine" --all main
	# Should not fail due to unknown option
	assert_output_not_contains "Unknown option"
}

@test "update-mine: fails with unknown option" {
	run "$SCRIPTS_DIR/update-mine" --unknown main
	[ "$status" -ne 0 ]
	assert_output_contains "Unknown option"
}

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

@test "update-mine: skips branches checked out in another worktree" {
	setup_git_repo
	git checkout -b feature-a
	echo "a" >a.txt && git add a.txt && git commit -m "feature-a work"
	git checkout main

	# Hold feature-a in a second worktree so it's "checked out elsewhere"
	git worktree add "$TEST_TEMP_DIR/other-wt" feature-a

	stub_gh feature-a

	run "$SCRIPTS_DIR/update-mine" main
	assert_output_contains "feature-a"
	assert_output_contains "another worktree"
	assert_output_not_contains "fatal:"
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

	current=$(git branch --show-current)
	[ "$current" = "starting-branch" ]
}
